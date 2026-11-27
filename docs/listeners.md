# Listener discovery and server commands

Purpose: Explain how Port Desk identifies a listener, constructs its preview URL and verifies a stop or restart.

Read this before touching: [Listener model and scanner](../Ports.swift), [action coordinator and Terminal launcher](../PortDesk.swift), [automated checks](../Tests/Check.swift).

Keywords: lsof, PID, IPv4, IPv6, localhost, HTTPS, SIGTERM, restart, Terminal

## Discovery and preview URLs

`scan(previewSchemes: true)` runs macOS `lsof` with TCP LISTEN filters, parses NUL-delimited fields and groups endpoints by PID. The scanner reads the process identity, owner, executable and working directory. Manageable rows require a matching current user, an eligible working directory, a process start fingerprint, and a recognized runtime or executable under the working directory. A directory inside an application bundle's Contents is excluded. Other processes appear read-only. Scan errors surface in the dashboard.

Preview links use one endpoint per port. An unshared wildcard uses `localhost`. A shared port uses the selected listener's numeric address or its family-specific loopback for a wildcard. For example, an explicit IPv6 loopback on port 3000 yields `http://[::1]:3000`. Port 443 and recognized TLS launch flags select HTTPS. The context menu offers the other scheme.

## Stop and restart

A confirmation captures a listener snapshot. On execution, `stop` rechecks the current user, PID fingerprint and complete port set, records the attempted signal, then sends SIGTERM. Release checks detect a supervisor or other replacement that claims an old port. A rejected stale selection can be retried from a refreshed row.

Restart waits for release, then uses a temporary user-executable command file to launch Terminal. The file removes itself when run. A fresh interactive login shell changes into the original working directory and executes the reviewed command. Suggestions cover a Next.js dev script with supported flags, simple Node entry scripts and Python HTTP servers. For a custom launch, enter the full command and required settings. A replacement launched in Terminal continues in its own session.

Port Desk checks every original port for a listener with the same user and working directory. The log identifies returned and missing ports. If a port remains occupied or the launch fails, inspect the history and Terminal. This check establishes listening status at that point. Open the preview to check application readiness.

## Verification

The [build guide](architecture.md#build-and-check) runs the scanner and stop fixture. To exercise restart, use a disposable server in a distinct working folder, review its shell command and confirm the original port returns there. For a multi-port server, check the partial-return case as well as full recovery. Inspect the browser response separately using its port link.
