# Architecture and local build

Purpose: Locate the code, build tools and project-local guidance that produce Port Desk.

Read this before touching: [App entry point](../PortDesk.swift), [process inspection](../Ports.swift), [build script](../build.sh), [listener checks](../Tests/Check.swift).

Keywords: architecture, Swift 6, macOS 14, SwiftUI, AppKit, build, signing, icon, agent skills

## Ownership

Port Desk is a native macOS utility. `PortDeskApp` owns the session’s single `Desk` and presents the dashboard in a SwiftUI `MenuBarExtra` with the window style. SwiftUI owns presentation, while AppKit supplies the frosted backdrop, panel visibility notifications and clipboard. [Dashboard](dashboard.md) covers its controls and state. [Listeners and commands](listeners.md) covers the Darwin process APIs, local TCP discovery, validation and Terminal integration.

[build.sh](../build.sh) is the build entry point. It compiles the two Swift sources with `swiftc -swift-version 6` for the host architecture and macOS 14. The script writes the bundle metadata and resources, then ad-hoc signs **Port Desk.app**. The generated `LSUIElement` flag gives the app its menu-bar-only presence and keeps its icon out of the Dock. Change the source plist embedded in the script when changing bundle settings. Rebuild after editing the [Icon Composer asset](../Assets/PortDesk.icon/icon.json). The asset supplies the compiled catalog and fallback ICNS. The 1024 × 1024 [PNG artwork](../Assets/PortDesk.png) is available for reuse.

## Build and check

Run these commands from the project directory on a Mac with Xcode 26 or later and its developer tools installed.

```sh
./build.sh
codesign --verify --strict 'Port Desk.app'
swiftc -swift-version 6 -target "$(uname -m)-apple-macos14.0" Ports.swift Tests/Check.swift -o /tmp/portdesk-check
/tmp/portdesk-check
```

The build refreshes the app bundle in place. The listener check starts a disposable loopback Python HTTP server and signals its own fixture. Its assertions cover parsing, URL selection, quoting, discovery, a stale selection, graceful stop and port release. Check interaction in the built app separately using the [dashboard checks](dashboard.md#manual-checks).

## Project-local skills

The installed copies live under `.agents/skills/`. Their guidance is for contributors. When updating a skill, verify the chosen upstream revision, copy its root license, check the installed content against that revision and update the pin here.

| Local guide and license | Pinned upstream | Use |
| --- | --- | --- |
| [SwiftUI Expert](../.agents/skills/swiftui-expert-skill/SKILL.md) · [MIT](../.agents/skills/swiftui-expert-skill/LICENSE) | [62bd760](https://github.com/AvdLee/SwiftUI-Agent-Skill/tree/62bd760f005093d1e2e4de5db156e456a5f96400/skills/swiftui-expert-skill) | macOS scenes, layout, state ownership and accessibility |
| [Swift Concurrency](../.agents/skills/swift-concurrency/SKILL.md) · [MIT](../.agents/skills/swift-concurrency/LICENSE) | [3b1580d](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill/tree/3b1580d8398e0b5408b3bf0bada0e941a1cfc642/skills/swift-concurrency) | Actor isolation, task lifetimes and cancellation |

The [tooling history](history/project-tooling.md) records the skill installation and Git baseline.
