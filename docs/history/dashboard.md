# Dashboard history

Purpose: Record changes to the dashboard surface, state ownership and interactions.

Read this before touching: [Dashboard guide](../dashboard.md), [presentation and coordinator](../../PortDesk.swift), [bundle settings](../../Port%20Desk.xcodeproj/project.pbxproj).

Keywords: menu bar, disclosure, compact row, polling, accessibility, command history

## 2026-11-27 — Bound listener discovery and cancel panel polling

Sequential reads from lsof could deadlock when its diagnostics filled a pipe. An unresponsive child also held the refresh slot indefinitely. The [discovery runner](../../ListenerDiscovery.swift) now drains both streams, bounds output and run time, and cleans up its child on errors. Closing the panel cancels its poll. The independently confirmed Stop or Restart continues.

The [listener checks](../../Tests/Check.swift) exercise full pipes, empty and unsuccessful exits, timeout, cancellation, process cleanup, recovery and real loopback discovery. See [the lifecycle guide](../dashboard.md#appearance-and-lifecycle).

## 2026-11-24 — Move the full dashboard into the menu bar

**Outcome.** Implemented change.

**Reason and cause.** The standalone window reserved a wide port column, labeled actions and permanent space for command history. Closing a menu bar panel also introduced a lifecycle distinction. Routine discovery should pause while a confirmed restart finishes.

**Change.** The sole app scene is a menu bar panel. The app owns its session state. Panel visibility controls routine polling. Each project row has compact action icons with descriptive help and accessible names, and each final confirmation spells out the action. Other listeners and command history open through independent disclosure chevrons.

**Verification.** On arm64 macOS 27.2 with Swift 6.2.1, the production bundle built for macOS 14.0, passed strict code-signature verification, and had `LSUIElement` enabled. The listener checks passed. In the production panel, the two disclosures toggled independently, Tab reached a port link, and Escape canceled a Stop review. A disposable server restarted after the panel closed, returned its expected HTTP content on the original port and had a new PID.

A temporary test host using the production dashboard and session model verified that both disclosures started collapsed, two preview links opened the corresponding Safari pages, and command history recorded the signal, working directory, launch command, release and return across a closed-panel restart. A separate model check observed no new scan during five seconds hidden and detected a new listener 75 ms after reopening.

**Limits.** Native accessibility inspection checked labels and help. Spoken VoiceOver output and the visual effect of toggling Reduce Transparency were not exercised. The deployment target was checked in the build. The interactive run used macOS 27.2.

**References.** [Current dashboard](../dashboard.md) · [Build and automated check](../architecture.md#build-and-check) · [Listener checks](../../Tests/Check.swift)
