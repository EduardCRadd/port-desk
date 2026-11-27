import Darwin
import Foundation

enum Action: String {
    case stop = "Stop"
    case restart = "Restart"
}

struct RemainingListener: Equatable {
    let id: Int32
    let endpoint: Endpoint
}

enum ActionOutcome: Equatable {
    case stopped(remaining: [RemainingListener])
    case restarted(returned: Set<Int>, missing: Set<Int>)
    case failed(String)

    var summary: String {
        func list(_ ports: Set<Int>) -> String { ports.sorted().map(String.init).joined(separator: ", ") }
        switch self {
        case .stopped(let remaining):
            let stopped = "Selected server stopped listening."
            guard !remaining.isEmpty else { return stopped }
            let peers = remaining.map { "\($0.endpoint.displayAddress) (PID \($0.id))" }
            return stopped + " Still listening: " + peers.joined(separator: ", ") + "."
        case let .restarted(returned, missing):
            var lines: [String] = []
            if !returned.isEmpty { lines.append("Listening on \(list(returned)).") }
            if !missing.isEmpty { lines.append("Still missing in the original folder: \(list(missing)). Check Terminal.") }
            return lines.joined(separator: " ")
        case .failed(let message):
            return "Couldn’t finish. " + message
        }
    }
}

enum SignalResult {
    case sent
    case stale
    case failed(String)
}

struct ActionWorkflow: Sendable {
    var listeners: @Sendable () async throws -> [Listener]
    var signal: @Sendable (Listener) async -> SignalResult
    var launch: @Sendable (String, String) async throws -> Void
    var sleep: @Sendable (Duration) async throws -> Void

    static let live = ActionWorkflow(
        listeners: { try scan() },
        signal: { selected in
            // Check identity again immediately before the syscall to limit the PID-reuse window.
            guard let expected = selected.fingerprint, identity(processInfo(selected.id)) == expected else { return .stale }
            guard kill(selected.id, SIGTERM) == 0 else { return .failed(String(cString: strerror(errno))) }
            return .sent
        },
        launch: { try terminalLaunch(directory: $0, command: $1) },
        sleep: { try await Task.sleep(for: $0) }
    )

    @concurrent func perform(_ action: Action, on selected: Listener, command: String = "",
                             record: @Sendable (String) async -> Void = { _ in }) async -> ActionOutcome {
        let stale = "The listener changed. Refresh and select it again."
        do {
            guard selected.manageable, let directory = selected.directory,
                  let current = try await listeners().first(where: { $0.id == selected.id }),
                  current.manageable, current.fingerprint == selected.fingerprint, current.endpoints == selected.endpoints else {
                return .failed(stale)
            }

            let attempt = await signal(selected)
            if case .stale = attempt { return .failed(stale) }
            await record("$ kill -TERM \(selected.id)")
            if case .failed(let error) = attempt { return .failed(error) }

            let remaining = try await waitForStop(of: selected)
            let stopped = ActionOutcome.stopped(remaining: remaining)
            guard action == .restart else { return stopped }
            await record(stopped.summary)
            guard remaining.isEmpty else {
                return .failed("Restart blocked. Another listener owns a selected port.")
            }
            await record("$ cd -- " + quote(directory) + " && " + command)
            try await launch(directory, command)
            return try await observeRestart(of: selected)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func waitForStop(of selected: Listener) async throws -> [RemainingListener] {
        for attempt in 1...30 {
            let overlapping = try await listeners().filter { !$0.ports.isDisjoint(with: selected.ports) }
            let stillListening = overlapping.contains { row in
                row.id == selected.id && (row.fingerprint == nil || row.fingerprint == selected.fingerprint)
            }
            if !stillListening {
                return overlapping.flatMap { row in
                    row.endpoints.filter { selected.ports.contains($0.port) }
                        .map { RemainingListener(id: row.id, endpoint: $0) }
                }.sorted {
                    ($0.endpoint.port, $0.endpoint.displayAddress, $0.id) < ($1.endpoint.port, $1.endpoint.displayAddress, $1.id)
                }
            }
            if attempt < 30 { try await sleep(.milliseconds(200)) }
        }
        throw DeskError("The selected server is still listening after SIGTERM. Check its terminal.")
    }

    private func observeRestart(of selected: Listener) async throws -> ActionOutcome {
        var found = Set<Int>()
        for attempt in 1...40 {
            let candidates = try await listeners().filter { $0.uid == selected.uid && $0.directory == selected.directory }
            found = selected.ports.intersection(candidates.flatMap(\.ports))
            if found == selected.ports || attempt == 40 { break }
            try await sleep(.milliseconds(350))
        }
        return .restarted(returned: found, missing: selected.ports.subtracting(found))
    }
}
