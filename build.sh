#!/bin/sh
set -eu
cd "$(dirname "$0")"
bundle='Port Desk.app/Contents'
mkdir -p "$bundle/MacOS" "$bundle/Resources"
# Icon Composer supplies the desktop mask and the fallback ICNS from one master.
if ! xcrun --find actool >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
icon_tmp=$(mktemp -d)
trap 'rm -rf "$icon_tmp"' EXIT
xcrun actool Assets/PortDesk.icon --compile "$icon_tmp" --platform macosx --target-device mac \
    --minimum-deployment-target 14.0 --app-icon PortDesk --output-partial-info-plist "$icon_tmp/info.plist"
cp "$icon_tmp/Assets.car" "$icon_tmp/PortDesk.icns" "$bundle/Resources/"
cat > "$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PortDesk</string>
<key>CFBundleIdentifier</key><string>local.portdesk.dashboard</string>
<key>CFBundleName</key><string>Port Desk</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>PortDesk</string>
<key>CFBundleIconName</key><string>PortDesk</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
swiftc -swift-version 6 -target "$(uname -m)-apple-macos14.0" -O -module-cache-path "${TMPDIR:-/tmp}/port-desk-swift-cache" Ports.swift PortDesk.swift -o "$bundle/MacOS/PortDesk"
codesign --force --sign - "Port Desk.app"
# Refresh Finder’s cached bundle metadata after an in-place rebuild.
touch "Port Desk.app"
