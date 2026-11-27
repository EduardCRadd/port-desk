import Foundation

@main struct Check {
    static func main() throws {
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
        let service = Process()
        service.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        service.arguments = ["-m", "http.server", "0", "--bind", "127.0.0.1"]
        service.standardOutput = FileHandle.nullDevice
        service.standardError = FileHandle.nullDevice
        try service.run()
        defer { if service.isRunning { service.terminate(); service.waitUntilExit() } }
        var fixture: Listener?
        for _ in 0..<45 {
            fixture = try scan().first { $0.id == service.processIdentifier }
            if fixture != nil { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard let fixture, fixture.manageable else { throw DeskError("Disposable HTTP listener or its process identity was unavailable.") }
        precondition(restartSuggestion(fixture).contains("http.server " + fixture.portText + " --bind 127.0.0.1"))
        var stale = fixture
        stale.fingerprint = nil
        do { try stop(stale) { _ in fatalError("Stale listener was signalled") }; fatalError("Accepted stale listener") }
        catch is DeskError {}
        var issued = ""
        try stop(fixture) { issued = $0 }
        try waitForRelease(fixture)
        precondition(issued == "kill -TERM " + String(service.processIdentifier))
        print("Passed parser, quoting, live discovery, stale selection, graceful stop and port release.")
    }
}
