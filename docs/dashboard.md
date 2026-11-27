# Menu bar dashboard and interaction

Purpose: Describe how to identify a preview, review a command and maintain the menu bar panel.

Read this before touching: [SwiftUI views and app state](../PortDesk.swift), [listener rules](listeners.md), [build and verification](architecture.md#build-and-check).

Keywords: menu bar, MenuBarExtra, panel, disclosure, pollTask, port links, keyboard, VoiceOver, command history, Reduce Transparency

## Using the panel

Click the plug and server count in the menu bar, or use the global shortcut. The blue port opens the selected development preview in the default browser. Show all includes other listeners as read-only rows. The badge and Kill all count development processes even when a process has several port rows.

Click a row or its chevron for PID, command, directory, port, uptime, CPU, memory and estimated energy. Hover over a development row to open its preview, reveal the original Terminal tab or review stopping the process. Terminal attribution requires a verifiable controlling terminal and ancestry. Unknown sessions cannot be revealed. The preview context menu on the row offers the alternate HTTP scheme.

Right-click a row, or select it with the arrow keys and press Control-Return, for Command History or a development server for Restart. History keeps the most recent 120 entries and can be copied. Restart lets you review or edit a launch command. Escape cancels an action review. Command-Return confirms it. Kill all presents the captured targets and all their ports. Confirmed actions continue after dismissal. The result identifies any remaining listener, a partial restart or an individual failure.

## Appearance and lifecycle

MenuController anchors an AppKit panel below its status item. SwiftUI owns the rows, disclosures, reviews and settings. A solid window background replaces the material when Reduce Transparency is enabled. Opening refreshes discovery immediately. Closing switches to count-only discovery. Refresh or Command-R requests a scan while open.

## Manual checks

1. Open the panel with its status button and the global shortcut from another app. Verify keyboard selection, O, T and K, cancellation, and focus after reopening.
2. Use disposable servers to verify a shared-port stop, bulk review, Terminal matching and an unknown session. Repeat browser and terminal opening with both dismissal settings. See [listener verification](listeners.md#verification).
3. Compare both lists, each inspector, row highlights, help text and the three settings tabs against the reference states below. Verify the recording control, shortcut conflict feedback, settings persistence and the version displayed from the bundle.
4. Check the panel at increased contrast and reduced transparency. Use a dedicated accessibility session for spoken VoiceOver feedback.
5. Run `./scripts/check-dashboard.sh /tmp/port-desk-captures` from the checkout for ten fixture captures and the controlled polling checks. Images use synthetic server names, deterministic resource samples and native controls. Native tooltip timing and the desktop material need a windowed check.

## Reference layout

At 2× scale the supplied two-server panel measures about 470 points wide. The header and footer are about 32 and 30 points high, each compact row is 49 points high, and disclosure adds about 125 points. The port column begins 12 points from the edge and the title begins 74 points from it. The settings window measures about 420 × 448 points. Compare panel bounds without the desktop background or window shadow.

PortRow projects listener snapshots into ascending port order. A process owning multiple ports appears on multiple rows and remains one action target. Rows sharing a port preserve their separate process identities.

The menu bar badge counts eligible development processes. A closed panel scans immediately and then about every 30 seconds. An open panel samples each PID once per refresh. Memory is physical footprint in decimal MB. CPU is the change in accumulated Mach CPU ticks divided by elapsed ticks, with 100% representing one busy core. The estimated energy tier is High at 50% CPU or 100 interrupt wakeups per second, Medium at 10% or 20 wakeups per second, and Low below both thresholds. A missing reading appears as a dash. The first reading after opening or PID replacement establishes a new baseline.

Settings has General, Shortcut and Refresh tabs. Show all is shared with the panel. Close menu after opening is on by default. The launch-at-login switch reads the current system service status and links to Login Items if approval is pending. The shortcut defaults to Option-Command-P. Record a letter or number with Command, Control or Option, reset the combination, or disable it. Conflicts are reported in the Shortcut pane. In the panel use the arrow keys to select a port, O to open its URL, T to reveal its Terminal tab and K to review stopping the owning server. Refresh sets the open-panel interval from one to ten seconds.
