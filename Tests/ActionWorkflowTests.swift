import Foundation
import Testing

private func server(_ pid: Int32, ports: [Int]) -> Listener {
    var row = Listener(id: pid)
    row.name = "python"
    row.uid = getuid()
    row.directory = "/tmp/test-project"
    row.fingerprint = Identity(uid: getuid(), seconds: UInt64(pid), micros: 0)
    row.endpoints = Set(ports.map { Endpoint("127.0.0.1:\($0)", family: "IPv4")! })
    return row
}

// Each test owns its observations. The last snapshot persists for timeout tests.
private actor Fixture {
    var snapshots: [[Listener]]
    var signals: [Int32] = []
    var commands: [String] = []
    var history: [String] = []
    let signalResult: SignalResult
    let launchError: DeskError?

    init(_ snapshots: [[Listener]], signal: SignalResult = .sent, launchError: DeskError? = nil) {
        self.snapshots = snapshots
        self.signalResult = signal
        self.launchError = launchError
    }

    func read() -> [Listener] { snapshots.count > 1 ? snapshots.removeFirst() : snapshots.first ?? [] }
    func signal(_ row: Listener) -> SignalResult {
        signals.append(row.id)
        return signalResult
    }
    func launch(_ directory: String, _ command: String) throws {
        commands.append(command)
        if let launchError { throw launchError }
    }
    func log(_ line: String) { history.append(line) }
    nonisolated var workflow: ActionWorkflow {
        ActionWorkflow(listeners: { await self.read() }, signal: { await self.signal($0) },
                       launch: { try await self.launch($0, $1) }, sleep: { _ in })
    }
}

@Test func changedProcessRejectsStaleSelection() async {
    let selected = server(123, ports: [3000])
    var replacement = selected
    replacement.fingerprint = Identity(uid: getuid(), seconds: 999, micros: 0)
    let fixture = Fixture([[replacement]])
    let result = await fixture.workflow.perform(.stop, on: selected)
    guard case .failed = result else { Issue.record("Expected stale selection"); return }
    #expect(await fixture.signals.isEmpty)
}

@Test func failedSignalIsRecordedAndPreventsLaunch() async {
    let selected = server(123, ports: [3000])
    let fixture = Fixture([[selected]], signal: .failed("Permission denied"))
    let result = await fixture.workflow.perform(.restart, on: selected, command: "server") { await fixture.log($0) }
    #expect(result == .failed("Permission denied"))
    #expect(await fixture.history == ["$ kill -TERM 123"])
    #expect(await fixture.commands.isEmpty)
}

@Test func terminalFailureIsReported() async {
    let selected = server(123, ports: [3000])
    let fixture = Fixture([[selected], []], launchError: DeskError("Terminal unavailable"))
    let result = await fixture.workflow.perform(.restart, on: selected, command: "server")
    #expect(result == .failed("Terminal unavailable"))
    #expect(await fixture.commands == ["server"])
}

@Test func restartReportsPartialReturn() async {
    let selected = server(123, ports: [3000, 3001])
    let replacement = server(124, ports: [3001])
    let fixture = Fixture([[selected], [], [replacement]])
    let result = await fixture.workflow.perform(.restart, on: selected, command: "server")
    #expect(result == .restarted(returned: [3001], missing: [3000]))
}
