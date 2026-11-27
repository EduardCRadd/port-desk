import Foundation

/// Keep Python's optional reverse DNS lookup off the critical path on hosted macOS runners.
func makeHTTPFixtureDirectory() throws -> URL {
    let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
    let fixtureStartup = """
        import socket

        original_getfqdn = socket.getfqdn
        def local_fixture_name(name=""):
            if name in ("127.0.0.1", "::1"):
                return "localhost"
            return original_getfqdn(name)
        socket.getfqdn = local_fixture_name
        """
    do {
        try fixtureStartup.write(to: directory.appendingPathComponent("sitecustomize.py"), atomically: true, encoding: .utf8)
    } catch {
        try? FileManager.default.removeItem(at: directory)
        throw error
    }
    return directory
}

func configureHTTPFixture(_ process: Process, in directory: URL) {
    var environment = ProcessInfo.processInfo.environment
    environment["PYTHONPATH"] = directory.path
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    process.environment = environment
    process.currentDirectoryURL = directory
}

/// Exercise two real listeners in the same working directory on different loopback addresses.
func checkSharedStop(in directory: URL) async throws {
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
}

/// An HTTP server owned by this check. Never signal a PID discovered by port alone.
func startHTTPServer(in directory: URL, host: String, port: Int) throws -> Process {
    let process = Process()
    configureHTTPFixture(process, in: directory)
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", "-m", "http.server", String(port), "--bind", host]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.standardError
    try process.run()
    return process
}

func finish(_ process: Process) {
    if process.isRunning { process.terminate() }
    process.waitUntilExit()
}

func findFixture(_ process: Process) throws -> Listener {
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
