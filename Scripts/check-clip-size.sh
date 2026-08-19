#!/bin/sh
# Fails the build if the App Clip exceeds its uncompressed budget.
#
# iOS 16+ allows 15 MB. The gate is set at 13 MB to leave headroom, because the
# number that matters is Apple's own measurement of the thinned, signed bundle,
# and that is not exactly what we can measure here.
set -eu

LIMIT_MB=13

if [ -z "${BUILT_PRODUCTS_DIR:-}" ]; then
    echo "check-clip-size: not running inside Xcode; skipping"
    exit 0
fi

CLIP="$BUILT_PRODUCTS_DIR/MultiSet AR.app/AppClips/MultiSet AR Clip.app"
if [ ! -d "$CLIP" ]; then
    echo "check-clip-size: no Clip at $CLIP; skipping"
    exit 0
fi

BYTES=$(find "$CLIP" -type f -exec stat -f%z {} + | awk '{total += $1} END {print total}')
MB=$(echo "$BYTES" | awk '{printf "%.2f", $1 / 1048576}')
LIMIT_BYTES=$((LIMIT_MB * 1048576))

echo "App Clip uncompressed size: ${MB} MB (limit ${LIMIT_MB} MB)"

if [ "$BYTES" -gt "$LIMIT_BYTES" ]; then
    echo "error: App Clip is ${MB} MB, over the ${LIMIT_MB} MB budget." >&2
    echo "note: bundled assets and linked frameworks are the usual cause." >&2
    exit 1
fi
