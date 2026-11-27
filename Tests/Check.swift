import Foundation

@main struct Check {
    static func main() async throws {
        let args = CommandLine.arguments
        if args.count >= 3 && args[1] == "--scan-fixture" {
            try runDiscoveryFixture(Array(args.dropFirst(2)))
            return
        }
        try await checkDiscovery()
        let directory = try makeHTTPFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await checkSharedStop(in: directory)
        let wire = "p23\0cnode\0u501\0\nf8\0n[::1]:3000\0\nf9\0n127.0.0.1:3000\0\nf10\0n*:3002\0\np45\0cOther tool\0u0\0\nf4\0n*:4000\0\n"
        let rows = parseListeners(Data(wire.utf8))
        precondition(rows.count == 2 && rows[0].sortedPorts == [3000, 3002] && rows[1].name == "Other tool")
        let ipv6 = Endpoint("*:3000", family: "IPv6")!
        let ipv4 = Endpoint("*:3002", family: "IPv4")!
        precondition(ipv6.url(https: false)?.absoluteString == "http://localhost:3000")
        precondition(ipv4.url(https: true)?.absoluteString == "https://localhost:3002")
        precondition(Endpoint("[::1]:3000", family: "IPv6")?.url(https: false)?.absoluteString == "http://[::1]:3000")
        let split = parseListeners(Data("p1\0f1\0tIPv6\0n*:3000\0p2\0f2\0tIPv4\0n*:3000\0".utf8))
        precondition(split.count == 2 && split.allSatisfy { $0.sharedPorts == [3000] })
        precondition(ipv6.url(https: false, sharedPort: true)?.absoluteString == "http://[::1]:3000")
        precondition(rows[0].sharedPorts.isEmpty)
        precondition(Endpoint("[2001:db8::1]:443", family: "IPv6")?.url(https: true)?.absoluteString == "https://[2001:db8::1]:443")
        precondition(Endpoint("192.0.2.10:8443", family: "IPv4")?.url(https: false)?.host == "192.0.2.10")
        precondition(hasHTTPSFlag(["next", "dev", "--experimental-https"]))
        precondition(!hasHTTPSFlag(["node", "server.js"]))
        let wildcard = parseListeners(Data("p1\0f3\0tIPv6\0n*:3000\0f4\0tIPv4\0n*:3002\0".utf8))
        precondition(wildcard.first?.previewEndpoints == [ipv6, ipv4])
        precondition(rows[0].previewEndpoints.map(\.browserHost) == ["127.0.0.1", "127.0.0.1"])
        precondition(quote("my project's") == "'my project'\\''s'")
        var helper = Listener(id: 123)
        helper.uid = getuid()
        helper.fingerprint = Identity(uid: getuid(), seconds: 1, micros: 0)
        helper.directory = "/Applications/Editor.app/Contents/MacOS"
        helper.executable = helper.directory! + "/helper"
        precondition(!helper.manageable)
        let service = try startHTTPServer(in: directory, host: "127.0.0.1", port: 0)
        defer { finish(service) }
        let fixture = try findFixture(service)
        precondition(restartSuggestion(fixture).contains("http.server " + fixture.portText + " --bind 127.0.0.1"))
        var stale = fixture
        stale.fingerprint = nil
        let rejected = await ActionWorkflow.live.perform(.stop, on: stale)
        guard case .failed = rejected else { fatalError("Accepted stale listener") }
        let stopped = await ActionWorkflow.live.perform(.stop, on: fixture)
        guard case .stopped = stopped else { fatalError(stopped.summary) }
        print("Passed parser, quoting, live discovery, stale selection, graceful stop and port release.")
    }
}

private func runDiscoveryFixture(_ args: [String]) throws {
    switch args[0] {
    case "flood":
        try FileHandle.standardError.write(contentsOf: Data(repeating: 0x65, count: 256 * 1024))
        try FileHandle.standardOutput.write(contentsOf: Data(repeating: 0x61, count: 256 * 1024))
    case "empty": exit(1)
    case "error":
        try FileHandle.standardError.write(contentsOf: Data("fixture failure".utf8))
        exit(1)
    case "hang":
        try String(getpid()).write(toFile: args[1], atomically: true, encoding: .utf8)
        while true { pause() }
    default: fatalError("Unknown discovery fixture")
    }
}

private func checkDiscovery() async throws {
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    func fixture(_ args: [String], timeout: Duration = .seconds(5)) -> ListenerDiscovery {
        ListenerDiscovery(executable: exe, arguments: ["--scan-fixture"] + args, timeout: timeout)
    }
    let data = try fixture(["flood"]).read()
    precondition(data == Data(repeating: 0x61, count: 256 * 1024))
    let empty = try fixture(["empty"]).read()
    precondition(empty.isEmpty)
    do { _ = try fixture(["error"]).read(); fatalError("Accepted a failed scan") }
    catch let error as DeskError { precondition(error.message.contains("fixture failure")) }

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    func checkReaped(_ marker: URL) async throws {
        let text = try String(contentsOf: marker, encoding: .utf8)
        guard let pid = pid_t(text) else { throw DeskError("Missing fixture PID") }
        let deadline = ContinuousClock.now + .seconds(2)
        while kill(pid, 0) == 0 {
            guard ContinuousClock.now < deadline else { throw DeskError("Discovery fixture was not reaped") }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(errno == ESRCH)
    }
    let timedOut = directory.appendingPathComponent("timeout")
    do {
        _ = try fixture(["hang", timedOut.path], timeout: .seconds(1)).read()
        fatalError("Scan failed to time out")
    } catch let error as DeskError { precondition(error.message.contains("timed out")) }
    try await checkReaped(timedOut)

    let cancelled = directory.appendingPathComponent("cancel")
    let discovery = fixture(["hang", cancelled.path])
    let scanTask = Task.detached { try discovery.read() }
    defer { scanTask.cancel() }
    let deadline = ContinuousClock.now + .seconds(3)
    while !FileManager.default.fileExists(atPath: cancelled.path) {
        guard ContinuousClock.now < deadline else { throw DeskError("The cancellation fixture did not start.") }
        try await Task.sleep(for: .milliseconds(10))
    }
    scanTask.cancel()
    do { _ = try await scanTask.value; fatalError("Cancelled scan returned a result") }
    catch is CancellationError {}
    try await checkReaped(cancelled)
    let recovered = try fixture(["flood"]).read()
    precondition(recovered == data)
    print("Passed full pipes, exit statuses, scan timeout, cancellation, child cleanup and recovery.")
}
