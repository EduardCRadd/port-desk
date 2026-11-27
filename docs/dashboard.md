# Menu bar dashboard and interaction

Purpose: Describe how to identify a preview, review a command and maintain the menu bar panel.

Read this before touching: [SwiftUI views and app state](../PortDesk.swift), [listener rules](listeners.md), [build and verification](architecture.md#build-and-check).

Keywords: menu bar, MenuBarExtra, panel, disclosure, pollTask, port links, keyboard, VoiceOver, command history, Reduce Transparency

## Using the panel

Launch **Port Desk.app** manually, then click the monochrome terminal icon in the menu bar. It opens a 510 × 490-point panel. Development servers appear in a scrollable list ordered by lowest port. Use the project folder and PID to distinguish similar previews. Click a green port or press Return or Space on a focused link to open the default browser. Hover to inspect its URL. Its context menu offers the alternate scheme.

Each project row has two icon buttons. The yellow counterclockwise arrow starts a Restart review and the red square starts a Stop review. Their tooltips and accessible names include the action, project and ports. On a shared port the accessible name also includes the PID. The compact port column fits five-digit ports. Rows with multiple ports stack the numbers vertically.

**Other listeners** and **Command history** each start collapsed. Use either heading’s disclosure chevron to expand it independently. Other listeners shows read-only ports. History displays the latest 120 lines of commands and outcomes for the session, including results received while the panel was closed. With history collapsed, the latest completed Stop or Restart result appears below the disclosure. Expand history to read the full result and copy it with **Copy commands and results**. A Stop result lists any remaining listener on the selected ports. A Restart result identifies returned endpoints and any that are missing.

Both action reviews appear inside the panel. They identify the project, process, ports and signal. Restart lets you edit the launch command while a suggestion loads. Select **Cancel** or press Escape to return to the list. Select the final **Stop** or **Restart** button or press Command-Return to confirm. The Restart review names its editable field **Start command**. While an operation runs, the history heading shows progress and port links stay available.

Click outside to dismiss the panel. Choose **Quit Port Desk** in the panel to end the session. The Quit button is disabled during a server action.

## Appearance and lifecycle

The panel uses a frosted dark backdrop and terminal-green links. Reduce Transparency switches to a solid background. Keep the symbol, hover help and accessible name together when changing row controls. Confirmation controls retain text.

`PortDeskApp` owns the main-actor `Desk` shared across openings. `TerminalBackdrop` observes the panel window’s occlusion state because SwiftUI can retain menu bar content between openings. When visible, `setPanelVisible` starts one task that refreshes immediately, then sleeps four seconds between scans. Hiding the panel cancels the poll loop and its active discovery process. Reopening waits for the cancelled poll to finish before refreshing. **Refresh** or Command-R requests an immediate scan.

Confirmation starts a separate action task. It continues through release checks, Terminal launch and port verification after the panel closes. Keep the session model outside the panel content so a later opening can display its results. The dashboard posts the final summary as an accessibility announcement when the panel is visible and key. Both listener lists lay out rows as they approach the viewport.

## Manual checks

1. Cold-launch in Finder. Open the menu bar icon and verify both disclosures start collapsed. Expand each independently, scroll a long list, and dismiss and reopen the panel.
2. Use two disposable servers with distinct page titles. Activate their port links and check the URL and page title. Exercise a link by keyboard and read the row-action names with accessibility tools.
3. Press Escape in a Stop review and confirm the disposable preview still responds. Open Restart, inspect the start command, confirm with Command-Return and dismiss the panel. Reopen it, read the result with history collapsed, then expand history to inspect the signal, launch command and returned endpoints. Confirm the new server still serves the preview.
4. With disposable IPv4 and IPv6 listeners sharing a port, check that row action labels identify each PID. Stop one, verify the summary names the surviving address and PID, and verify the peer still serves its page.
5. Check panel contrast in the Reduce Transparency appearance. In a VoiceOver session, check row labels, the start-command field, cancellation and whether the final result is spoken once. Quit after all actions finish.

See the [dashboard history](history/dashboard.md) for dated verification and its limits.

## Reference layout

At 2× scale the supplied two-server panel measures about 470 points wide. The header and footer are about 32 and 30 points high, each compact row is 49 points high, and disclosure adds about 125 points. The port column begins 12 points from the edge and the title begins 74 points from it. The settings window measures about 420 × 448 points. Compare panel bounds without the desktop background or window shadow.

PortRow projects listener snapshots into ascending port order. A process owning multiple ports appears on multiple rows and remains one action target. Rows sharing a port preserve their separate process identities.

The menu bar badge counts eligible development processes. A closed panel scans immediately and then about every 30 seconds. An open panel samples each PID once per refresh. Memory is physical footprint in decimal MB. CPU is the change in accumulated Mach CPU ticks divided by elapsed ticks, with 100% representing one busy core. The estimated energy tier is High at 50% CPU or 100 interrupt wakeups per second, Medium at 10% or 20 wakeups per second, and Low below both thresholds. A missing reading appears as a dash. The first reading after opening or PID replacement establishes a new baseline.

Settings has General, Shortcut and Refresh tabs. Show all is shared with the panel. Close menu after opening is on by default. The launch-at-login switch reads the current system service status and links to Login Items if approval is pending. The shortcut defaults to Option-Command-P. Record a letter or number with Command, Control or Option, reset the combination, or disable it. Conflicts are reported in the Shortcut pane. In the panel use the arrow keys to select a port, O to open its URL, T to reveal its Terminal tab and K to review stopping the owning server. Refresh sets the open-panel interval from one to ten seconds.
