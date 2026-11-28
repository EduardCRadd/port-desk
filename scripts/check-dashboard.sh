#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcrun --find actool >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun --toolchain org.swift.643202611191a swiftc -swift-version 6 -target "$(uname -m)-apple-macos14.0" \
    Ports.swift ListenerDiscovery.swift RestartBinding.swift ActionWorkflow.swift TerminalLauncher.swift \
    TerminalSession.swift ProcessMetrics.swift PortDesk.swift Dashboard.swift GlobalShortcut.swift Preferences.swift \
    Tests/SharedPortChecks.swift Tests/DashboardChecks.swift -o "$work/check-dashboard"
"$work/check-dashboard" "${1:-$work/captures}"
