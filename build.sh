#!/bin/sh
set -eu
cd "$(dirname "$0")"

case "${1:-}" in
    '') scheme='Port Desk'; configuration=Release ;;
    --check) scheme='Listener Checks'; configuration=Debug ;;
    *) echo 'Usage: ./build.sh [--check]' >&2; exit 2 ;;
esac

# Prefer the selected Xcode; a Command Line Tools selection lacks actool.
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcrun --find actool >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
xcodebuild -project 'Port Desk.xcodeproj' -scheme "$scheme" \
    -configuration "$configuration" -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$work_dir" -quiet build

products="$work_dir/Build/Products/$configuration"
if [ "$scheme" = 'Listener Checks' ]; then
    xcodebuild -project 'Port Desk.xcodeproj' -scheme "$scheme" \
        -configuration "$configuration" -destination "platform=macOS,arch=$(uname -m)" \
        -derivedDataPath "$work_dir" -parallel-testing-enabled NO -quiet test
    "$products/Listener Checks"
else
    # Mirror the complete signed product, removing stale resources on rebuilds.
    /usr/bin/rsync -a --delete "$products/Port Desk.app/" 'Port Desk.app/'
    codesign --verify --strict 'Port Desk.app'
fi
