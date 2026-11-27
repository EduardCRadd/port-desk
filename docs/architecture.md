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
| [Swift Concurrency Pro](../.agents/skills/swift-concurrency-pro/SKILL.md) · [MIT](../.agents/skills/swift-concurrency-pro/LICENSE) | [bee3f69](https://github.com/twostraws/swift-concurrency-agent-skill/tree/bee3f69ba17142da148d3c5406f148ed62592b69/swift-concurrency-pro) | Review polling and process actions for cancellation, detached task lifetimes and state changes across an `await` |
| [Write Swift](../.agents/skills/write-swift/SKILL.md) · [MIT](../.agents/skills/write-swift/LICENSE) | [64eb3de](https://github.com/emilkowalski/skills/tree/64eb3deb9a5fbfa041faf783e0bc3fd635872e9c/skills/write-swift) | Value types, object lifetimes, errors and C interoperability in listener discovery |
| [Swift Testing Expert](../.agents/skills/swift-testing-expert/SKILL.md) · [MIT](../.agents/skills/swift-testing-expert/LICENSE) | [798e9b1](https://github.com/AvdLee/Swift-Testing-Agent-Skill/tree/798e9b1a2bcac164d4f0c781908199e754f0bab6/swift-testing-expert) | Parameterized parser cases, async waiting and fixture isolation in Swift Testing suites |
| [AppKit–SwiftUI Bridge](../.agents/skills/appkit-swiftui-bridge/SKILL.md) · [MIT](../.agents/skills/appkit-swiftui-bridge/LICENSE) | [f958982](https://github.com/rshankras/claude-code-apple-skills/tree/f9589828e222113d49c7bff417c33038802856ff/skills/macos/appkit-swiftui-bridge) | Representable lifetimes, coordinators and observer cleanup in the dashboard |
| [SwiftUI Accessibility Auditor](../.agents/skills/swiftui-accessibility-auditor/SKILL.md) · [MIT](../.agents/skills/swiftui-accessibility-auditor/LICENSE) | [2fff4d8](https://github.com/rgmez/apple-accessibility-skills/tree/2fff4d8bcf82d5f1a99e31ac8fda72698d5ff3a3/skills/swiftui-accessibility-auditor) | VoiceOver labels, keyboard focus and manual checks for row actions |
| [SwiftUI Performance Audit](../.agents/skills/swiftui-performance-audit/SKILL.md) · [MIT](../.agents/skills/swiftui-performance-audit/LICENSE) | [05ba982](https://github.com/Dimillian/Skills/tree/05ba982bfeb0d77d3c97d4542b0ee15034d05f84/swiftui-performance-audit) | Diagnose repeated list updates, high CPU and hangs using Instruments |
| [Swift API Design Guidelines](../.agents/skills/swift-api-design-guidelines-skill/SKILL.md) · [MIT](../.agents/skills/swift-api-design-guidelines-skill/LICENSE) | [36cdc1b](https://github.com/erikote04/Swift-API-Design-Guidelines-Agent-Skill/tree/36cdc1b5680f5d6c5c52c353a6857d176f4929e8/swift-api-design-guidelines-skill) | Review argument labels and distinguish listener queries from process actions at call sites |

Use the Swift Testing guide when working on a Swift Testing suite. The existing listener checks use the standalone executable in [Build and check](#build-and-check). Check API availability against the macOS 14 target when applying newer AppKit or SwiftUI examples.

Write Swift assumes Swift 6.3 and marks some examples as Swift 6.4. For code shared by the app and listener checks, check the compiler used by both commands. The build script can select Xcode through `DEVELOPER_DIR` while a separate `swiftc` invocation uses Command Line Tools.

The [tooling history](history/project-tooling.md) records the skill installation and Git baseline.
