# Project tooling history

Purpose: Record changes to the local build and contributor tools that affect maintenance.

Read this before touching: [Architecture and pinned sources](../architecture.md), [documentation workflow](../documentation-workflow.md).

Keywords: project tooling, SwiftUI Expert, Swift Concurrency, documentation

## 2026-11-27 — Establish a reproducible Git baseline

The project previously built from a working directory without Git history. The baseline tracks the app and listener sources, executable build script, icon artwork and symlink, documentation, and both licensed skill copies. Git ignores the generated root app bundle and Finder metadata.

The [build and check commands](../architecture.md#build-and-check) select Swift 6 and target macOS 14 for both the app and the listener checks. Verify a baseline from a temporary clone so the build leaves the working app alone. After the signature and listener checks, `git status --porcelain --untracked-files=all` should produce no output. Dashboard interaction has separate manual checks.

## 2026-11-24 — Add pinned Swift skills and a local documentation system

**Outcome.** Implemented change.

**Reason and cause.** The app’s two Swift sources and existing README described its behavior. Contributors needed reusable macOS and concurrency guidance plus a place to record lifecycle decisions and verification.

**Change.** Installed project-local copies of SwiftUI Expert and Swift Concurrency with their upstream MIT licenses. The pins and maintenance instructions live in the architecture guide. The documentation index maps the dashboard, listener discovery, commands and packaging to their owners.

**Verification and limits.** The installer used explicit revisions and a project-local destination. A Git blob hash comparison covered every installed file against the pinned trees, including the upstream root licenses: 52 files for SwiftUI Expert and 21 for Swift Concurrency. This record covers the initial installation.

**References.** [Pins, sources and licenses](../architecture.md#project-local-skills) · [Working instructions](../../AGENTS.md) · [Documentation index](../INDEX.md)
