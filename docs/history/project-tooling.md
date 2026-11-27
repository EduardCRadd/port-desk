# Project tooling history

Purpose: Record changes to the local build and contributor tools that affect maintenance.

Read this before touching: [Architecture and pinned sources](../architecture.md), [documentation workflow](../documentation-workflow.md).

Keywords: project tooling, SwiftUI Expert, Swift Concurrency, documentation

## 2026-11-27 — Verify source builds on pull requests

The shared verification script checks a fresh checkout locally and on GitHub Actions. The workflow selects Xcode 27.2 and installs the signed Swift.org 6.4.3 release. It checks the compiled deployment target for every architecture. A macOS 14 runtime check still needs a machine running that release.

## 2026-11-27 — Exercise listener checks with the development Python

The fixture used an absolute path to Apple's Python, so a shell upgrade had no effect on the check. The executable now resolves `python3` through its launch environment. With Python 3.15.2 selected, the listener checks passed, including restart command reconstruction, graceful termination and port release. See [build and check](../architecture.md#build-and-check) for interpreter selection in Terminal and Xcode.

## 2026-11-27 — Build and debug with Xcode and Swift 6.4.3

Opening `Tests/Check.swift` on its own produced 23 diagnostics, including missing listener types and parser functions. The script supplied the other source file, but there was no Xcode project defining that compilation unit. Added shared Port Desk and Listener Checks schemes with separate entry points. The terminal script builds the same targets. Both select the Swift 6.4.3 release toolchain and keep macOS 14 as the deployment target.

On an Apple silicon Mac with Xcode 27.2, both schemes built through Apple’s MCP bridge with zero Issue navigator errors. The compiler log identified the installed Swift 6.4.3 toolchain. LLDB stopped at the menu bar scene in a temporary Debug build, and the listener executable passed against its disposable server. Relaunching Xcode after toolchain installation was necessary for the running IDE to detect it. Runtime checks ran on macOS 27.2. See [build and check](../architecture.md#build-and-check) and [Xcode tools for Codex](../architecture.md#xcode-tools-for-codex).

## 2026-11-27 — Add Swift language and concurrency review guides

Reviewed fourteen candidates against the macOS 14 app, its build settings and the existing skill pins. Added Write Swift for value types, lifetime management and Darwin interop, and Swift Concurrency Pro for reviewing detached tasks and cancellation during polling. The existing concurrency guide remains useful for compiler diagnostics and migrations.

The [skill table](../architecture.md#project-local-skills) records both upstream revisions. The Concurrency Pro installation includes its Codex entry point, references and interface assets. Both installations include the upstream MIT license.

## 2026-11-27 — Extend Swift contributor guidance

The dashboard bridges SwiftUI and AppKit, presents changing listener rows and exposes process actions to keyboard and VoiceOver users. Added five project-local skills covering AppKit bridging, SwiftUI accessibility audits, performance diagnosis, Swift Testing and Swift API design. The architecture guide maps each skill to its use and upstream revision.

Verified all 41 new files, including the five MIT licenses, against the pinned Git blobs. The existing listener check command remains the verification entry point for process actions. See [project-local skills](../architecture.md#project-local-skills).

## 2026-11-27 — Establish a reproducible Git baseline

The project previously built from a working directory without Git history. The baseline tracks the app and listener sources, executable build script, icon artwork and symlink, documentation, and both licensed skill copies. Git ignores the generated root app bundle and Finder metadata.

The [build and check commands](../architecture.md#build-and-check) select Swift 6 and target macOS 14 for both the app and the listener checks. Verify a baseline from a temporary clone so the build leaves the working app alone. After the signature and listener checks, `git status --porcelain --untracked-files=all` should produce no output. Dashboard interaction has separate manual checks.

## 2026-11-24 — Add pinned Swift skills and a local documentation system

**Outcome.** Implemented change.

**Reason and cause.** The app’s two Swift sources and existing README described its behavior. Contributors needed reusable macOS and concurrency guidance plus a place to record lifecycle decisions and verification.

**Change.** Installed project-local copies of SwiftUI Expert and Swift Concurrency with their upstream MIT licenses. The pins and maintenance instructions live in the architecture guide. The documentation index maps the dashboard, listener discovery, commands and packaging to their owners.

**Verification and limits.** The installer used explicit revisions and a project-local destination. A Git blob hash comparison covered every installed file against the pinned trees, including the upstream root licenses: 52 files for SwiftUI Expert and 21 for Swift Concurrency. This record covers the initial installation.

**References.** [Pins, sources and licenses](../architecture.md#project-local-skills) · [Working instructions](../../AGENTS.md) · [Documentation index](../INDEX.md)
