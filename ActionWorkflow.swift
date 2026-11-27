import Darwin
import Foundation

enum Action: String {
    case stop = "Stop"
    case restart = "Restart"
}

enum ActionOutcome: Equatable {
    case stopped(ports: Set<Int>)
    case restarted(returned: Set<Int>, missing: Set<Int>)
    case failed(String)

    var summary: String {
        func list(_ ports: Set<Int>) -> String { ports.sorted().map(String.init).joined(separator: ", ") }
        switch self {
        case .stopped(let ports):
            return "Port \(list(ports)) released."
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
                  current.manageable, current.fingerprint == selected.fingerprint, current.ports == selected.ports else {
                return .failed(stale)
            }

            let attempt = await signal(selected)
            if case .stale = attempt { return .failed(stale) }
            await record("$ kill -TERM \(selected.id)")
            if case .failed(let error) = attempt { return .failed(error) }

            try await waitForRelease(of: selected)
            let stopped = ActionOutcome.stopped(ports: selected.ports)
            guard action == .restart else { return stopped }
            await record(stopped.summary)
            await record("$ cd -- " + quote(directory) + " && " + command)
            try await launch(directory, command)
            return try await observeRestart(of: selected)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func waitForRelease(of selected: Listener) async throws {
        for attempt in 1...30 {
            let overlapping = try await listeners().filter { !$0.ports.isDisjoint(with: selected.ports) }
            if overlapping.isEmpty { return }
            guard overlapping.contains(where: { $0.id == selected.id && $0.fingerprint == selected.fingerprint }) else {
                throw DeskError("Another listener owns a selected port. Check the refreshed list.")
            }
            if attempt < 30 { try await sleep(.milliseconds(200)) }
        }
        throw DeskError("The port is still in use after SIGTERM. Check the server’s terminal.")
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
