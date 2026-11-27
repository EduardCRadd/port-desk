# Dashboard history

Purpose: Record changes to the dashboard surface, state ownership and interactions.

Read this before touching: [Dashboard guide](../dashboard.md), [presentation and coordinator](../../PortDesk.swift), [bundle settings](../../Port%20Desk.xcodeproj/project.pbxproj).

Keywords: menu bar, disclosure, compact row, polling, accessibility, command history

## 2026-11-27 — Show one row per port and add dashboard settings

The former fixed dashboard grouped all ports under a PID and exposed Restart beside every development row. The panel now follows the reference’s per-port layout, with a full process snapshot behind each row. Expanding a port shows its process details. Hover exposes browser, Terminal and reviewed Stop actions. Restart and the session history moved to the contextual menu. Control-Return opens the same actions for a keyboard selection.

A closed panel now refreshes the count of development servers every 30 seconds. Visible resource samples use a separate cadence. Settings stores the display and shortcut preferences and reads the actual login service status.

On arm64 macOS 27.2 the fixture renderer produced seven panel states and three settings panes. Compact and expanded panels measured 470 × 159 and 470 × 284 points. Settings measured 420 × 448 points. Visual inspection led to trailing alignment for switches and values, a centered settings title, and adjusted footer typography. The controlled-clock check exercised closed discovery, visible sampling and dismissal. A real bulk action stopped its selected disposable process and rejected a stale capture. A separate desktop probe opened and dismissed the actual status panel, restored a saved shortcut, observed an exclusive-registration conflict, released the combination and dispatched a Carbon hotkey event to the panel handler. The source build targets macOS 14. Live desktop material, native tooltip bubbles and spoken output are separate from the fixture captures.

[Panel guide](../dashboard.md) · [Dashboard checks](../../Tests/DashboardChecks.swift)

## 2026-11-27 — Expose action results and shorten first layout

**Outcome.** Completed actions leave their summary visible below collapsed history. The menu panel keeps the complete result for later inspection and requests a spoken announcement when it is the visible key window. Shared-port action names include the PID, the editable launch command has a name, and Command-Return confirms a reviewed action.

**Reason and change.** A developer previously had to expand history to learn which endpoints remained after a Stop or returned after a Restart. Both scroll views also built every listener row up front. The dashboard now reads the same outcome as the command log, and lays out listener rows lazily.

**Verification.** On arm64 macOS 27.2, a temporary host using the dashboard and session model exercised Escape in a review, the named command field, a keyboard-confirmed Restart through Terminal and a Stop of that disposable server. The new PID listened on the original port; both results were accessible with history collapsed. A separate check using the final Stop workflow hid the panel through its visibility callback during an action. The fixture stopped, its port was released and the model retained the summary in history. Across nine seconds hidden and nine seconds visible, the model published zero and three routine scan results respectively.

In a debug host rendering 160 synthetic project rows, three runs took 470–512 ms to lay out the original list and 27–31 ms for the lazy list. Twelve jumps across the full list took longer with lazy layout (roughly 0.35 s total versus 0.06 s) as each destination materialized. The host also exercised both Reduce Transparency environment values and verified the AppKit effect view hid for the opaque appearance.

**Limits.** These are local layout timings, not display-frame or energy measurements. Accessibility inspection verified the controls and result text. Spoken output was not independently captured. The release build and strict signature check passed with the Swift 6.4.3 toolchain and macOS 14 target; the interactive checks ran on macOS 27.2.

**References.** [Panel behavior and manual checks](../dashboard.md) · [Action outcome](../../ActionWorkflow.swift) · [Dashboard](../../PortDesk.swift)

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
