# Architecture and local build

Purpose: Locate the code, build tools and project-local guidance that produce Port Desk.

Read this before touching: [App entry point](../PortDesk.swift), [process inspection](../Ports.swift), [build script](../build.sh), [listener checks](../Tests/Check.swift).

Keywords: architecture, Swift 6, macOS 14, SwiftUI, AppKit, build, signing, icon, agent skills

## Ownership

Port Desk is a native macOS utility. `PortDeskApp` owns the session’s single `Desk` and presents the dashboard in a SwiftUI `MenuBarExtra` with the window style. SwiftUI owns presentation, while AppKit supplies the frosted backdrop, panel visibility notifications and clipboard. [Dashboard](dashboard.md) covers its controls and state. [Listeners and commands](listeners.md) covers the Darwin process APIs, local TCP discovery, validation and Terminal integration.

The [Xcode project](../Port%20Desk.xcodeproj/project.pbxproj) owns the sources, build settings and packaging for both shared schemes. The app and the Listener Checks executable share discovery, [the action workflow](../ActionWorkflow.swift), and [the Terminal launcher](../TerminalLauncher.swift). Each executable has one `@main` entry point. The **Action Tests** bundle exercises the same sources with controlled observations, signals, timing, and launches. Press ⌘U in either shared scheme to run its Swift Testing cases.

The app target generates the bundle metadata, including `LSUIElement` for menu-bar-only launch, and signs locally. Xcode compiles the [Icon Composer asset](../Assets/PortDesk.icon/icon.json) into the catalog and fallback ICNS. The [PNG artwork](../Assets/PortDesk.png) remains available for reuse.

## Build and check

Use Xcode 27.2 and the [Swift 6.4.3 release toolchain for macOS](https://www.swift.org/install/macos/). Choose the macOS package installer and install for the current user. If Xcode was open during installation, quit and relaunch it so its build service discovers the new toolchain. Both schemes use Swift 6 language mode and a macOS 14 deployment target. With Xcode in its standard location, check the installed compiler using:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun --toolchain org.swift.643202611191a swiftc --version
```

The version output should include `6.4.3`. A plain `swiftc --version` can report a different Command Line Tools compiler. For a differently named Xcode installation, set `DEVELOPER_DIR` to its `Contents/Developer` directory.

Open **Port Desk.xcodeproj**, select **My Mac**, then choose a shared scheme. **Port Desk** runs the debug app with ⌘R and supports source breakpoints. **Listener Checks** runs the existing executable with ⌘R and prints its result in the debug console. Opening `Tests/Check.swift` as a standalone program leaves `parseListeners`, `Endpoint` and other declarations in `Ports.swift` out of scope. Open the project and run the Listener Checks scheme to compile both files together.

For a terminal build, run these commands from a checkout:

```sh
./build.sh
codesign --verify --strict 'Port Desk.app'
./build.sh --check
```

The [script](../build.sh) builds the shared schemes with temporary Derived Data. Its default action copies the signed Release bundle into the checkout. Run it in a temporary checkout to verify without overwriting a running app bundle. With `--check`, the script runs the Swift Testing bundle and the Listener Checks executable. The listener check uses a disposable loopback HTTP server and signals its own fixture. Its assertions cover parsing, URL selection, quoting, discovery, a stale selection, graceful stop and port release. For interaction and accessibility, use the [dashboard checks](dashboard.md#manual-checks).

The listener check launches `python3 -m http.server` through `PATH`. To verify your development interpreter, run `python3 --version` and `./build.sh --check` from the same terminal. Python 3.15.2 has been verified. When launched from Finder, Xcode uses its own environment and may select a different Python. The app itself has no Python dependency.

From a temporary clean clone, run `./scripts/verify.sh` for the pull request checks. It verifies the selected Xcode and Swift versions, the Release bundle signature and deployment target, the listener fixture, and the final Git status. The GitHub Actions source build uses the same script on an Apple silicon runner. For active development, use the individual build commands above.

## Xcode tools for Codex

Open the project in Xcode. In **Xcode → Settings → Intelligence → Model Context Protocol**, choose **While Xcode is Open** for external agents. Register Apple's bridge once per Codex installation:

```sh
codex mcp add xcode --env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer -- /usr/bin/xcrun mcpbridge
codex mcp get xcode
```

In a Codex session with the server loaded, call `XcodeListWindows` and look for the path ending in `Port Desk.xcodeproj`. If Xcode prompts for access, review the request there. If the tool is missing from an existing session, start a fresh session. If it lists no project, open the project file in Xcode. See [Apple’s external-agent instructions](https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode).

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

Use the [project toolchain and schemes](#build-and-check) when validating Swift language examples from contributors’ skills.

The [tooling history](history/project-tooling.md) records the skill installation and Git baseline.
