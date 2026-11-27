# Menu bar dashboard and interaction

Purpose: Describe how to identify a preview, review a command and maintain the menu bar panel.

Read this before touching: [SwiftUI views and app state](../PortDesk.swift), [listener rules](listeners.md), [build and verification](architecture.md#build-and-check).

Keywords: menu bar, MenuBarExtra, panel, disclosure, pollTask, port links, keyboard, VoiceOver, command history, Reduce Transparency

## Using the panel

Launch **Port Desk.app** manually, then click the monochrome terminal icon in the menu bar. It opens a 510 × 490-point panel. Development servers appear in a scrollable list ordered by lowest port. Use the project folder and PID to distinguish similar previews. Click a green port or press Return or Space on a focused link to open the default browser. Hover to inspect its URL. Its context menu offers the alternate scheme.

Each project row has two icon buttons. The yellow counterclockwise arrow starts a Restart review and the red square starts a Stop review. Their tooltips and accessible names include the action, project and ports. The compact port column fits five-digit ports. Rows with multiple ports stack the numbers vertically.

**Other listeners** and **Command history** each start collapsed. Use either heading’s disclosure chevron to expand it independently. Other listeners shows read-only ports. History displays the latest 120 lines of commands and outcomes for the session, including results received while the panel was closed. Use **Copy commands and results** when the log has entries.

Both action reviews appear inside the panel. They identify the project, process, ports and signal. Restart lets you edit the launch command while a suggestion loads. Select **Cancel** or press Escape to return to the list. The final **Stop** or **Restart** button spells out the action. While an operation runs, the history heading shows progress and port links stay available.

Click outside to dismiss the panel. Choose **Quit Port Desk** in the panel to end the session. The Quit button is disabled during a server action.

## Appearance and lifecycle

The panel uses a frosted dark backdrop and terminal-green links. Reduce Transparency switches to a solid background. Keep the symbol, hover help and accessible name together when changing row controls. Confirmation controls retain text.

`PortDeskApp` owns the main-actor `Desk` shared across openings. `TerminalBackdrop` observes the panel window’s occlusion state because SwiftUI can retain menu bar content between openings. When visible, `setPanelVisible` starts one task that refreshes immediately, then sleeps four seconds between scans. Hiding the panel cancels the poll loop and its active discovery process. Reopening waits for the cancelled poll to finish before refreshing. **Refresh** or Command-R requests an immediate scan.

Confirmation starts a separate action task. It continues through release checks, Terminal launch and port verification after the panel closes. Keep the session model outside the panel content so a later opening can display its results.

## Manual checks

1. Cold-launch in Finder. Open the menu bar icon and verify both disclosures start collapsed. Expand each independently, scroll a long list, and dismiss and reopen the panel.
2. Use two disposable servers with distinct page titles. Activate their port links and check the URL and page title. Exercise a link by keyboard and read the row-action names with accessibility tools.
3. Cancel a Stop review. Confirm a Restart for a disposable process and immediately dismiss the panel. Reopen it and expand history to check the release, launch command and returned ports. Copy the log and confirm the restarted preview still serves its page.
4. Inspect the panel with Reduce Transparency enabled. Quit from the panel after all actions finish.

See the [dashboard history](history/dashboard.md) for dated verification and its limits.
