# Listener discovery and server commands

Purpose: Explain how Port Desk identifies a listener, constructs its preview URL and verifies a stop or restart.

Read this before touching: [Listener model and scanner](../Ports.swift), [action workflow](../ActionWorkflow.swift), [Terminal launcher](../TerminalLauncher.swift), [automated checks](../Tests/Check.swift).

Keywords: lsof, PID, IPv4, IPv6, localhost, HTTPS, SIGTERM, restart, Terminal

## Discovery and preview URLs

`scan(previewSchemes: true)` runs macOS `lsof` with TCP LISTEN filters, parses NUL-delimited fields and groups endpoints by PID. The scanner reads the process identity, owner, executable and working directory. Manageable rows require a matching current user, an eligible working directory, a process start fingerprint, and a recognized runtime or executable under the working directory. A directory inside an application bundle's Contents is excluded. Other processes appear read-only. Scan errors surface in the dashboard.

Preview links use one endpoint per port. An unshared wildcard uses `localhost`. A shared port uses the selected listener's numeric address or its family-specific loopback for a wildcard. For example, an explicit IPv6 loopback on port 3000 yields `http://[::1]:3000`. Port 443 and recognized TLS launch flags select HTTPS. The context menu offers the other scheme.

[ListenerDiscovery](../ListenerDiscovery.swift) owns each lsof child and reads standard output and error together. A scan has a five-second deadline and a 16 MiB output limit. On timeout or cancellation it kills and reaps its own child. An unsuccessful scan throws, so a process action cannot treat missing data as a released port. Exit code 1 with empty output and diagnostics is lsof’s normal empty-list result.

## Stop and restart

A confirmation captures a listener snapshot. The dashboard submits the reviewed command and snapshot to `ActionWorkflow.perform`, records its progress, and displays its outcome. On execution, the workflow rechecks the current user, PID fingerprint and complete set of addresses and ports, records the attempted signal, then sends SIGTERM. Stop succeeds once the selected server no longer listens on its reviewed ports. The result lists every remaining listener on those ports by address and PID, including a replacement or a peer using another address family. A rejected stale selection can be retried from a refreshed row.

Restart checks port ownership before Stop and again immediately before handing the command to Terminal. On an exclusive port the reviewed command may be custom. On a shared port Port Desk requires an explicit numeric bind matching the reviewed address, a known port and identifiable peers on distinct concrete addresses. It recognizes Python’s `-m http.server`, direct `next dev`, and `npm run dev --` with a plain Next dev script. Complex shell commands, unknown Node scripts, wildcard binds and shared commands whose multiple endpoints cannot be inferred are blocked before signalling. If a new owner appears after Stop, the workflow records that the server stopped and skips the launch. A process may still claim a socket after the final observation.

To launch, Port Desk uses a temporary user-executable command file to launch Terminal. The file removes itself when run. A fresh interactive login shell changes into the original working directory and executes the reviewed command. Suggestions cover a Next.js dev script with supported flags, simple Node entry scripts and Python HTTP servers. For a custom launch, enter the full command and required settings. A replacement launched in Terminal continues in its own session.

Port Desk checks each original address, address family and port for a listener with the same user and working directory. It excludes surviving peers from the preflight scan. The log identifies returned and missing endpoints. If a port remains occupied or the launch fails, inspect the history and Terminal. This check establishes listening status at that point. Open the preview to check application readiness.

## Verification

The [build guide](architecture.md#build-and-check) runs [controlled Swift Testing cases](../Tests/ActionWorkflowTests.swift) and the scanner and stop fixture. To exercise restart, use a disposable server in a distinct working folder, review its shell command and confirm the original port returns there. For a multi-port server, check the partial-return case as well as full recovery. Inspect the browser response separately using its port link.

The [listener history](history/listeners.md) records changes to these checks and outcomes.

The shared-port fixture serves a temporary page from one directory on an ephemeral port with distinct IPv4 and IPv6 loopback listeners. It verifies the selected IPv4 listener stops, checks the surviving IPv6 PID and endpoint in the result, and requests the page again from that peer.

The same fixture then restarts a fresh IPv4 listener using the reviewed command in a disposable shell. It verifies the replacement PID owns the selected endpoint, checks that the original IPv6 peer kept its identity, and fetches both pages. Exercise the interactive Terminal handoff separately on a desktop Mac.

The Terminal button locates an existing Terminal.app window and tab by the selected process’s controlling TTY. Discovery checks the parent chain and displays Unknown when it cannot attribute a session to Terminal. Revealing a tab rechecks identity and TTY, then requests Automation access on demand. Restart remains a separate command that launches a new shell.

Kill all captures one eligible listener per PID at review time and displays every affected port. Each confirmed Stop independently revalidates that snapshot and records the result. Read-only processes shown by Show all never enter the bulk review.
