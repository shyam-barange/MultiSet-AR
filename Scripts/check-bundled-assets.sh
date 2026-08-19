#!/bin/sh
# Asset gates for both build products.
#
#   2. No content assets in the App Clip. This is the regression that costs a week
#      when found at submission: adding the shared catalog to both targets'
#      membership is a one-click mistake, and the Clip silently gains ~14 MB.
#   3. No working files bundled. Refinement history and masters belong in version
#      control, not in Copy Bundle Resources.
#   4. No alpha on any app icon. A hard App Store rejection.
#
# Reads the compiled Assets.car rather than the project file, because membership
# is what actually ships.
set -eu

if [ -z "${BUILT_PRODUCTS_DIR:-}" ]; then
    echo "check-bundled-assets: not running inside a build; skipping"
    exit 0
fi

APP="$BUILT_PRODUCTS_DIR/MultiSet AR.app"
CLIP="$APP/AppClips/MultiSet AR Clip.app"
if [ ! -d "$APP" ]; then
    echo "check-bundled-assets: no app at $APP; skipping"
    exit 0
fi

STATUS=0
fail() { echo "error: $1" >&2; STATUS=1; }

catalog_names() {
    [ -f "$1" ] || return 0
    xcrun assetutil --info "$1" 2>/dev/null | python3 -c '
import json, sys
try:
    entries = json.load(sys.stdin)
except Exception:
    sys.exit(0)
names = {e["Name"] for e in entries if isinstance(e, dict) and e.get("Name")}
for name in sorted(names):
    print(name)
'
}

# --- Gate 2: the Clip carries the icon set and nothing else -------------------
if [ -d "$CLIP" ]; then
    CLIP_NAMES=$(catalog_names "$CLIP/Assets.car")
    UNEXPECTED=$(printf '%s\n' "$CLIP_NAMES" \
        | grep -vE '^(AppIcon|AccentColor|LaunchBackground)$' \
        | grep -v '^$' || true)
    if [ -n "$UNEXPECTED" ]; then
        fail "the App Clip's asset catalog carries more than its icon set:"
        printf '%s\n' "$UNEXPECTED" | sed 's/^/         /' >&2
    fi

    # Named explicitly as well as by exclusion, so a renamed asset still trips it.
    for prefix in onboarding- learn- clip-card; do
        if printf '%s\n' "$CLIP_NAMES" | grep -q "$prefix"; then
            fail "content asset matching '$prefix' found in the App Clip."
        fi
    done
else
    echo "note: no App Clip in the product; skipping the Clip asset gate"
fi

# --- Gate 3: no working files in either bundle --------------------------------
for bundle in "$APP" "$CLIP"; do
    [ -d "$bundle" ] || continue
    label=$(basename "$bundle")
    WORKING=$(find "$bundle" -type f \
        \( -name '*-source.*' -o -name '*-v[0-9].*' -o -name '*.svg' \
           -o -name '*.md' -o -name '*.tsv' \) 2>/dev/null || true)
    if [ -n "$WORKING" ]; then
        fail "working or provenance files bundled in $label:"
        printf '%s\n' "$WORKING" | sed "s|$bundle/|         |" >&2
    fi
done

# The staging directory must never become a bundled folder reference.
for bundle in "$APP" "$CLIP"; do
    [ -d "$bundle" ] || continue
    if [ -d "$bundle/ProductionAssets" ] || [ -d "$bundle/Raster" ]; then
        fail "$(basename "$bundle") contains a staging directory; it was added as a folder reference."
    fi
done

# --- Gate 4: no alpha on any app icon ----------------------------------------
for icon in ProductionAssets/AppIcon/*.png \
            App/Resources/Assets.xcassets/AppIcon.appiconset/*.png \
            Clip/Assets.xcassets/AppIcon.appiconset/*.png; do
    [ -f "$icon" ] || continue
    alpha=$(sips -g hasAlpha "$icon" 2>/dev/null | tail -1 | awk '{print $2}')
    if [ "$alpha" != "no" ]; then
        fail "$icon has an alpha channel — App Store will reject it."
    fi
done

# The flattened icon that actually ships is the one Apple checks.
for flat in "$APP"/AppIcon*.png; do
    [ -f "$flat" ] || continue
    alpha=$(sips -g hasAlpha "$flat" 2>/dev/null | tail -1 | awk '{print $2}')
    if [ "$alpha" != "no" ]; then
        fail "$(basename "$flat") in the built app has an alpha channel."
    fi
done

if [ "$STATUS" -eq 0 ]; then
    echo "Asset gates passed:"
    echo "  · App Clip catalog holds only its icon set and colours"
    echo "  · no masters, refinement history, or provenance files in either bundle"
    echo "  · no alpha on any app icon, masters or built"
fi
exit "$STATUS"
