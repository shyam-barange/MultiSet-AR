#!/bin/sh
# Fails the build if a credential is reachable from the App Clip.
#
# Greps built products, not source: source review cannot catch something pulled
# in transitively, and MultiSetSDK requires a clientId and clientSecret by
# construction. What matters is what ends up in the Clip binary.
#
# On precision. An earlier version failed on any occurrence of "clientSecret",
# which fired on Swift type metadata for MultiSetKit's M2MCredentials — a field
# name, not a secret. A gate with false positives gets ignored. The checks below
# were each verified against a real Release build to confirm they can actually
# fire; run with --self-test to re-verify detection.
set -eu

if [ "${1:-}" = "--self-test" ]; then
    SELF_TEST=1
else
    SELF_TEST=0
fi

if [ -z "${BUILT_PRODUCTS_DIR:-}" ]; then
    echo "check-clip-secrets: not running inside a build; skipping"
    exit 0
fi

CLIP="$BUILT_PRODUCTS_DIR/MultiSet AR.app/AppClips/MultiSet AR Clip.app"
if [ ! -d "$CLIP" ]; then
    echo "check-clip-secrets: no Clip at $CLIP; skipping"
    exit 0
fi

BINARY="$CLIP/MultiSet AR Clip"
STATUS=0

fail() { echo "error: $1" >&2; STATUS=1; }

# 1. The SDK must not be embedded — it cannot run without a clientSecret.
if [ -d "$CLIP/Frameworks" ] && ls "$CLIP/Frameworks" 2>/dev/null | grep -qi 'MultiSetSDK'; then
    fail "MultiSetSDK.framework is embedded in the App Clip."
fi

if [ -f "$BINARY" ]; then
    # 2. …nor linked, nor referenced by symbol.
    if otool -L "$BINARY" 2>/dev/null | grep -qi 'MultiSetSDK'; then
        fail "the App Clip binary links MultiSetSDK."
    fi
    if nm -u "$BINARY" 2>/dev/null | grep -qi 'MultiSetSDK'; then
        fail "the App Clip binary imports MultiSetSDK symbols."
    fi

    # 3. MultiSetConfig is the SDK's credential-bearing type, so its presence
    #    means the SDK was reached however it got linked.
    if strings -a "$BINARY" 2>/dev/null | grep -q 'MultiSetConfig'; then
        fail "found MultiSetConfig in the App Clip binary."
    fi

    # 4. The two endpoints that exchange a credential for a token must stay
    #    unreachable. Both are absent today because nothing in the Clip calls
    #    them and the linker strips them; if that changes, the Clip has grown a
    #    credential path and this fires.
    for endpoint in 'm2m/token' 'auth/login'; do
        if strings -a "$BINARY" 2>/dev/null | grep -q "$endpoint"; then
            fail "the Clip reaches /v1/$endpoint, which exchanges a credential."
        fi
    done

    # 5. No baked-in token or pre-encoded authorization value.
    for pattern in 'eyJ[A-Za-z0-9_-]\{20,\}' 'Basic [A-Za-z0-9+/]\{16,\}'; do
        if strings -a "$BINARY" 2>/dev/null | grep -q "$pattern"; then
            fail "found a credential-shaped literal matching /$pattern/ in the Clip binary."
        fi
    done
fi

# 6. Nothing credential-shaped smuggled through a bundled plist or resource.
for file in "$CLIP"/*.plist "$CLIP"/*.json; do
    [ -f "$file" ] || continue
    if grep -qiE 'clientsecret|client_secret|apikey|api_key|bearer ' "$file"; then
        fail "$(basename "$file") in the Clip looks like it carries a credential."
    fi
done

# Proves the gate can still detect a leak, rather than passing because the
# patterns no longer match anything.
if [ "$SELF_TEST" -eq 1 ]; then
    PROBE=$(mktemp)
    printf 'harmless\neyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\nmore\n' > "$PROBE"
    if strings -a "$PROBE" | grep -q 'eyJ[A-Za-z0-9_-]\{20,\}'; then
        echo "self-test: JWT detection works"
    else
        echo "error: self-test failed — the JWT pattern no longer detects a token." >&2
        STATUS=1
    fi
    printf 'GET /v1/m2m/token HTTP\n' > "$PROBE"
    if strings -a "$PROBE" | grep -q 'm2m/token'; then
        echo "self-test: credential-endpoint detection works"
    else
        echo "error: self-test failed — the endpoint pattern no longer matches." >&2
        STATUS=1
    fi
    rm -f "$PROBE"
fi

if [ "$STATUS" -eq 0 ]; then
    echo "App Clip credential check passed:"
    echo "  · MultiSetSDK is not linked, embedded, or referenced"
    echo "  · no MultiSetConfig in the binary"
    echo "  · /v1/m2m/token and /v1/auth/login are unreachable"
    echo "  · no baked-in tokens, and no credentials in resources"
fi
exit "$STATUS"
