#!/bin/bash
# Copies the app icon masters into both targets' asset catalogs.
#
# ProductionAssets/AppIcon/ holds the masters. The copies inside each
# AppIcon.appiconset are generated output and must never be edited directly —
# three hand-maintained copies of the same three files is guaranteed drift.
#
# Also enforces the one rule that is a hard App Store rejection: an app icon may
# not carry an alpha channel.
set -euo pipefail

cd "$(dirname "$0")/.."

MASTERS="ProductionAssets/AppIcon"
TARGETS=(
    "App/Resources/Assets.xcassets/AppIcon.appiconset"
    "Clip/Assets.xcassets/AppIcon.appiconset"
)

declare -a PAIRS=(
    "app-icon-light.png:AppIcon-Light-Production.png"
    "app-icon-dark.png:AppIcon-Dark-Production.png"
    "app-icon-tinted.png:AppIcon-Tinted-Production.png"
)

status=0

for pair in "${PAIRS[@]}"; do
    master="$MASTERS/${pair%%:*}"
    if [ ! -f "$master" ]; then
        echo "error: missing master $master" >&2
        status=1
        continue
    fi

    alpha=$(sips -g hasAlpha "$master" | tail -1 | awk '{print $2}')
    if [ "$alpha" != "no" ]; then
        echo "error: $master has an alpha channel — App Store will reject it." >&2
        status=1
        continue
    fi

    side=$(sips -g pixelWidth "$master" | tail -1 | awk '{print $2}')
    if [ "$side" != "1024" ]; then
        echo "error: $master is ${side}px wide; the icon must be 1024x1024." >&2
        status=1
        continue
    fi

    for target in "${TARGETS[@]}"; do
        cp "$master" "$target/${pair##*:}"
    done
    echo "synced ${pair%%:*} -> ${pair##*:}  (1024px, opaque)"
done

[ "$status" -eq 0 ] || exit "$status"
echo "App icon synced into ${#TARGETS[@]} catalogs from $MASTERS"
