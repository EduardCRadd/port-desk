#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

# Use full Xcode when xcode-select points to the Command Line Tools.
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcrun --find actool >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

xcode_version=$(xcodebuild -version)
printf '%s\n' "$xcode_version"
printf '%s\n' "$xcode_version" | grep -qx 'Xcode 27.2'
swift_version=$(xcrun --toolchain org.swift.643202611191a swiftc --version)
printf '%s\n' "$swift_version"
printf '%s\n' "$swift_version" | grep -Eq 'Swift version 6\.4\.3([[:space:]]|$)'

./build.sh
bundle='Port Desk.app'
codesign --verify --deep --strict --verbose=2 "$bundle"
executable=$(/usr/bin/plutil -extract CFBundleExecutable raw "$bundle/Contents/Info.plist")
build_info=$(xcrun vtool -show-build "$bundle/Contents/MacOS/$executable")
printf '%s\n' "$build_info" | awk '$1 == "minos" { count++; if ($2 != "14.0") bad++ } END { exit (!count || bad) }'

./build.sh --check
./scripts/check-dashboard.sh
status=$(git status --porcelain --untracked-files=all)
if [ -n "$status" ]; then
    printf 'Verification requires a clean checkout:\n%s\n' "$status" >&2
    exit 1
fi
