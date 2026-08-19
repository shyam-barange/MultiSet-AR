#!/bin/bash
# Everything that must pass before a change is considered done.
#
# The two Clip gates run here rather than as Xcode build phases: they inspect
# built products, which user-script sandboxing forbids, and running them against
# a real Release build is a truer check than an intermediate one.
set -euo pipefail

cd "$(dirname "$0")/.."
DERIVED="${DERIVED_DATA:-$(mktemp -d)/dd}"
SIM_ID="${SIM_ID:-}"

if [ -z "$SIM_ID" ]; then
    SIM_ID=$(xcrun simctl list devices available --json \
        | python3 -c "
import json,sys
data = json.load(sys.stdin)['devices']
for runtime in sorted(data, reverse=True):
    for device in data[runtime]:
        if 'iPhone' in device['name']:
            print(device['udid']); sys.exit(0)
sys.exit('no iPhone simulator available')
")
fi

section() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

section "Package tests"
# Run from each package directory: the scheme names only resolve against the
# package, not against the app project at the repo root.
FAILED=0
for package in MultiSetUI MultiSetKit MultiSetARCore; do
    echo "--- $package"
    if ! ( cd "Packages/$package" && xcodebuild test -scheme "$package" \
            -destination "id=$SIM_ID" -derivedDataPath "$DERIVED" 2>&1 \
            | grep -E "Executed [0-9]+ tests|error:|\*\* TEST" | sort -u ) ; then
        FAILED=1
    fi
done
[ "$FAILED" -eq 0 ] || { echo "package tests failed" >&2; exit 1; }

section "Build both targets (Release)"
xcodebuild build -project "MultiSet AR.xcodeproj" -scheme "MultiSet AR" \
    -configuration Release -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO -quiet 2>&1 \
    | grep -E "error:|warning:" | grep -v "not stripping" | sort -u || true

export BUILT_PRODUCTS_DIR="$DERIVED/Build/Products/Release-iphoneos"

section "App Clip size gate"
./Scripts/check-clip-size.sh

section "App Clip credential gate"
./Scripts/check-clip-secrets.sh

section "Asset gates"
./Scripts/check-bundled-assets.sh

printf '\n\033[1;32mAll checks passed.\033[0m\n'
