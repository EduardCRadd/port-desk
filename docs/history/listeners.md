# Listener history

Purpose: Record changes to listener discovery, process actions and their verification.

Read this before touching: [Listeners and commands](../listeners.md), [action workflow](../../ActionWorkflow.swift), [controlled tests](../../Tests/ActionWorkflowTests.swift).

Keywords: listener, SIGTERM, process identity, restart, Terminal, Swift Testing

## 2026-11-27 — Distinguish a stopped process from a vacant port

Stop used to report failure if a second listener kept serving on the same port number. It now identifies the selected process by PID and start time and reports the surviving endpoints and PIDs. The pre-signal check compares reviewed endpoints to catch address changes on the same port number. Controlled tests exercise both cases.

## 2026-11-27 — Exercise action failures without signalling live servers

Restart previously mixed polling, signalling and Terminal launches into dashboard updates. The action workflow now receives those operations as dependencies. Swift Testing exercises stale selection, failed SIGTERM, failed Terminal launch and partial port return. The standalone fixture also runs Stop through the same workflow against its own loopback server. The launch-failure case uses a simulated Terminal and does not verify interactive shell configuration.
