import Foundation

/// Exercise two real listeners in the same working directory on different loopback addresses.
func checkSharedPortActions() async throws {
    let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let token = UUID().uuidString
    try token.write(to: directory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

    let ipv4 = try startHTTPServer(in: directory, host: "127.0.0.1", port: 0)
    defer { finish(ipv4) }
    let port = try findFixture(ipv4).sortedPorts[0]
    let ipv6 = try startHTTPServer(in: directory, host: "::1", port: port)
    defer { finish(ipv6) }
    let peer = try findFixture(ipv6)
    let selected = try findFixture(ipv4)
    precondition(selected.sharedPorts == [port] && peer.sharedPorts == [port])
    let peerURL = URL(string: "http://[::1]:\(port)/")!
    try checkResponse(at: peerURL, expected: token)

    let outcome = await ActionWorkflow.live.perform(.stop, on: selected)
    guard case let .stopped(remaining) = outcome,
          remaining.contains(where: { $0.id == peer.id && peer.endpoints.contains($0.endpoint) }) else {
        throw DeskError("Stop did not identify the surviving IPv6 listener: " + outcome.summary)
    }
    try checkResponse(at: peerURL, expected: token)
    print("Shared Stop released the IPv4 listener and the original IPv6 peer still serves its page.")
    try await checkSharedRestart(in: directory, port: port, peer: peer, token: token)
}

/// An HTTP server owned by this check. Never signal a PID discovered by port alone.
private func startHTTPServer(in directory: URL, host: String, port: Int) throws -> Process {
    let process = Process()
    process.currentDirectoryURL = directory
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    if host == "::1" {
        // A numeric IPv6 peer has no reason to reverse-resolve its hostname before listening.
        let serveIPv6 = """
            import http.server, socket, socketserver, sys
            class LoopbackServer(socketserver.TCPServer):
                address_family = socket.AF_INET6
            with LoopbackServer(("::1", int(sys.argv[1])), http.server.SimpleHTTPRequestHandler) as server:
                print("IPv6 fixture listening on", server.server_address, file=sys.stderr, flush=True)
                server.serve_forever()
            """
        process.arguments = ["python3", "-c", serveIPv6, String(port)]
    } else {
        process.arguments = ["python3", "-m", "http.server", String(port), "--bind", host]
    }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.standardError
    try process.run()
    return process
}

private func finish(_ process: Process) {
    if process.isRunning { process.terminate() }
    process.waitUntilExit()
}

private func findFixture(_ process: Process) throws -> Listener {
    let deadline = ContinuousClock.now + .seconds(10)
    var observation = "PID absent from the listener scan"
    while process.isRunning && ContinuousClock.now < deadline {
        if let row = try scan().first(where: { $0.id == process.processIdentifier }) {
            if row.manageable { return row }
            observation = "discovered " + row.name + ", cwd=" + (row.directory ?? "<unavailable>")
                + ", same user=" + String(row.uid == getuid()) + ", identity=" + String(row.fingerprint != nil)
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    let status = process.isRunning ? observation : "exit status " + String(process.terminationStatus)
    let invocation = process.arguments?.joined(separator: " ") ?? "HTTP server"
    throw DeskError("Disposable fixture failed (\(invocation), pid \(process.processIdentifier)): \(status).")
}

private func checkResponse(at url: URL, expected: String) throws {
    let request = Process()
    let output = Pipe()
    request.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    request.arguments = ["-q", "--noproxy", "*", "--fail", "--silent", "--show-error",
                         "--max-time", "3", url.absoluteString]
    request.standardOutput = output
    try request.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    request.waitUntilExit()
    guard request.terminationStatus == 0 && String(decoding: data, as: UTF8.self) == expected else {
        throw DeskError("The disposable listener did not serve its fixture at " + url.absoluteString)
    }
}

/// Use the production workflow with a test-owned shell in place of the interactive Terminal window.
private func checkSharedRestart(in directory: URL, port: Int, peer: Listener, token: String) async throws {
    let original = try startHTTPServer(in: directory, host: "127.0.0.1", port: port)
    defer { finish(original) }
    let selected = try findFixture(original)
    let command = restartSuggestion(selected)
    let replacement = Process()
    defer { if replacement.isRunning { finish(replacement) } }

    var workflow = ActionWorkflow.live
    workflow.launch = { folder, reviewedCommand in
        replacement.currentDirectoryURL = URL(fileURLWithPath: folder)
        replacement.executableURL = URL(fileURLWithPath: "/bin/zsh")
        replacement.arguments = ["-c", "exec " + reviewedCommand]
        replacement.standardOutput = FileHandle.nullDevice
        replacement.standardError = FileHandle.nullDevice
        try replacement.run()
    }
    let outcome = await workflow.perform(.restart, on: selected, command: command)
    guard case let .restarted(returned, missing) = outcome,
          returned == selected.endpoints, missing.isEmpty, replacement.isRunning else {
        throw DeskError("Shared-port restart did not restore the IPv4 endpoint: " + outcome.summary)
    }
    let observed = try findFixture(replacement)
    guard observed.endpoints == selected.endpoints,
          try scan().contains(where: { $0.id == peer.id && $0.fingerprint == peer.fingerprint && $0.endpoints == peer.endpoints }) else {
        throw DeskError("The restarted listener or the original IPv6 peer changed unexpectedly.")
    }
    try checkResponse(at: URL(string: "http://127.0.0.1:\(port)/")!, expected: token)
    try checkResponse(at: URL(string: "http://[::1]:\(port)/")!, expected: token)
    print("Shared Restart restored the IPv4 endpoint; both servers serve their expected page.")
}
