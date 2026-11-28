import Darwin
import Foundation

enum Action: String {
    case stop = "Stop"
    case forceStop = "Force"
    case restart = "Restart"
}

struct RemainingListener: Equatable {
    let id: Int32
    let endpoint: Endpoint
}

enum ActionOutcome: Equatable {
    case stopped(remaining: [RemainingListener])
    case restarted(returned: Set<Endpoint>, missing: Set<Endpoint>)
    case failed(String)

    var summary: String {
        func list(_ endpoints: Set<Endpoint>) -> String { endpoints.map(\.displayAddress).sorted().joined(separator: ", ") }
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

enum StopSignal: String, Sendable {
    case terminate = "TERM"
    case force = "KILL"

    var number: Int32 { self == .force ? SIGKILL : SIGTERM }
}

enum SignalResult {
    case sent
    case stale
    case failed(String)
}

struct ActionWorkflow: Sendable {
    var listeners: @Sendable () async throws -> [Listener]
    var signal: @Sendable (Listener, StopSignal) async -> SignalResult
    var launch: @Sendable (String, String) async throws -> Void
    var sleep: @Sendable (Duration) async throws -> Void

    static let live = ActionWorkflow(
        listeners: { try scan() },
        signal: { selected, signal in
            // Check identity again immediately before the syscall to limit the PID-reuse window.
            guard let expected = selected.fingerprint, identity(processInfo(selected.id)) == expected else { return .stale }
            guard kill(selected.id, signal.number) == 0 else { return .failed(String(cString: strerror(errno))) }
            return .sent
        },
        launch: { try terminalLaunch(directory: $0, command: $1) },
        sleep: { try await Task.sleep(for: $0) }
    )

    @concurrent func perform(_ action: Action, on selected: Listener, command: String = "",
                             record: @Sendable (String) async -> Void = { _ in }) async -> ActionOutcome {
        let stale = "The listener changed. Refresh and select it again."
        do {
            let snapshot = try await listeners()
            guard selected.manageable, let directory = selected.directory,
                  let current = snapshot.first(where: { $0.id == selected.id }),
                  current.manageable, current.directory == directory, current.fingerprint == selected.fingerprint,
                  current.endpoints == selected.endpoints, action != .restart || current.executable == selected.executable else {
                return .failed(stale)
            }

            let peers = snapshot.filter { $0.id != selected.id && !$0.ports.isDisjoint(with: selected.ports) }
            if action == .restart && (!peers.isEmpty || !selected.sharedPorts.isEmpty) {
                guard RestartBinding.matches(command, selected: selected) else {
                    return .failed("Restart blocked before Stop. Use a supported command that explicitly binds to the selected address and port.")
                }
                guard peers.allSatisfy({ peer in
                    peer.fingerprint != nil && !peer.endpoints.contains { endpoint in
                        selected.endpoints.contains { $0.couldConflict(with: endpoint) }
                    }
                }) else {
                    return .failed("Restart blocked before Stop. Another listener may conflict with the selected address.")
                }
            }

            let delivery: StopSignal = action == .forceStop ? .force : .terminate
            let attempt = await signal(selected, delivery)
            if case .stale = attempt { return .failed(stale) }
            await record("$ kill -\(delivery.rawValue) \(selected.id)")
            if case .failed(let error) = attempt { return .failed(error) }

            let afterStop = try await waitForStop(of: selected, after: delivery)
            let remaining = afterStop.flatMap { row in
                row.endpoints.filter { selected.ports.contains($0.port) }
                    .map { RemainingListener(id: row.id, endpoint: $0) }
            }.sorted {
                ($0.endpoint.port, $0.endpoint.displayAddress, $0.id) < ($1.endpoint.port, $1.endpoint.displayAddress, $1.id)
            }
            let stopped = ActionOutcome.stopped(remaining: remaining)
            guard action == .restart else { return stopped }
            await record(stopped.summary)
            return await relaunch(selected, directory: directory, command: command, peers: peers, afterStop: afterStop, record: record)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func waitForStop(of selected: Listener, after signal: StopSignal) async throws -> [Listener] {
        for attempt in 1...30 {
            let overlapping = try await listeners().filter { !$0.ports.isDisjoint(with: selected.ports) }
            let stillListening = overlapping.contains { row in
                row.id == selected.id && (row.fingerprint == nil || row.fingerprint == selected.fingerprint)
            }
            if !stillListening { return overlapping }
            if attempt < 30 { try await sleep(.milliseconds(200)) }
        }
        throw DeskError("The selected server is still listening after SIG\(signal.rawValue). Check its terminal.")
    }

    private func relaunch(_ selected: Listener, directory: String, command: String, peers: [Listener],
                          afterStop: [Listener], record: @Sendable (String) async -> Void) async -> ActionOutcome {
        func ownersUnchanged(_ snapshot: [Listener]) -> Bool {
            snapshot.allSatisfy { owner in
                let endpoints = owner.endpoints.filter { selected.ports.contains($0.port) }
                return endpoints.isEmpty || peers.contains { peer in
                    owner.id == peer.id && owner.fingerprint == peer.fingerprint && endpoints.isSubset(of: peer.endpoints)
                }
            }
        }
        do {
            if !peers.isEmpty || !selected.sharedPorts.isEmpty {
                guard RestartBinding.matches(command, selected: selected) else {
                    return .failed("Selected server stopped. Restart blocked because its command no longer proves the reviewed bind.")
                }
            }
            guard ownersUnchanged(afterStop), try await ownersUnchanged(listeners()) else {
                return .failed("Selected server stopped. Restart blocked because another listener claimed a reviewed port.")
            }
            let issued = "$ cd -- " + quote(directory) + " && " + command
            do {
                try await launch(directory, command)
            } catch {
                await record(issued)
                throw error
            }
            await record(issued)
            var found = Set<Endpoint>()
            for attempt in 1...40 {
                let candidates = try await listeners().filter { row in
                    guard let identity = row.fingerprint, row.uid == selected.uid, row.directory == directory else { return false }
                    return !(row.id == selected.id && identity == selected.fingerprint)
                        && !peers.contains { $0.id == row.id && $0.fingerprint == identity }
                }
                found = selected.endpoints.intersection(candidates.flatMap(\.endpoints))
                if found == selected.endpoints || attempt == 40 { break }
                try await sleep(.milliseconds(350))
            }
            return .restarted(returned: found, missing: selected.endpoints.subtracting(found))
        } catch {
            return .failed("Selected server stopped. " + error.localizedDescription)
        }
    }
}
