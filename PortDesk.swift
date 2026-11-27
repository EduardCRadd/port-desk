import Accessibility
import AppKit
import SwiftUI

private let terminalGreen = Color(.sRGB, red: 0, green: 1, blue: 0)

extension Action {
    var symbol: String { self == .stop ? "stop.fill" : "arrow.counterclockwise" }

    var color: Color {
        switch self {
        case .restart: Color(.sRGB, red: 1, green: 208/255, blue: 100/255) // #FFD064
        case .stop: Color(.sRGB, red: 1, green: 103/255, blue: 100/255) // #FF6764
        }
    }
}

private struct ServerActionStyle: ButtonStyle {
    let action: Action
    var compact = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .padding(.horizontal, compact ? 0 : 12)
            .frame(minWidth: compact ? 30 : nil, minHeight: 28)
            .background {
                RoundedRectangle(cornerRadius: 6).fill(action.color)
                    .brightness(configuration.isPressed ? -0.12 : 0)
            }
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.45)
    }
}

struct Selection: Identifiable {
    let id = UUID()
    let row: Listener
    let action: Action
}

@MainActor final class Desk: ObservableObject {
    @Published var rows = [Listener]()
    @Published var actionMessage = ""
    @Published var scanError = ""
    @Published var busy = false
    @Published var loaded = false
    @Published var log = [String]()
    @Published private(set) var lastOutcome: ActionOutcome?
    private var scanning = false
    private var pollTask: Task<Void, Never>?

    private(set) var panelVisible = false
    private var previousSamples: [Int32: ResourceSample] = [:]
    @Published private(set) var metrics: [Int32: ProcessMetrics] = [:]

    init() { setPanelVisible(false) }

    func setPanelVisible(_ visible: Bool) {
        if pollTask != nil && visible == panelVisible { return }
        panelVisible = visible
        let previous = pollTask
        previous?.cancel()
        previousSamples.removeAll()
        pollTask = Task {
            await previous?.value
            while !Task.isCancelled {
                await refresh()
                let interval = UserDefaults.standard.object(forKey: "refreshSeconds") as? Int ?? 2
                do { try await Task.sleep(for: PollSchedule(visible: visible, interval: interval).delay) }
                catch { return }
            }
        }
    }

    func refresh() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        do {
            let visible = panelVisible
            let (result, samples) = try await Self.discover(visible: visible)
            try Task.checkCancellation()
            guard visible == panelVisible else { return }
            metrics = samples.map { pid, sample in
                (pid, ProcessMetrics(sample, previous: previousSamples[pid], secondsPerTick: ProcessMetrics.secondsPerTick))
            }.reduce(into: [:]) { $0[$1.0] = $1.1 }
            previousSamples = samples
            rows = result
            scanError = ""
            loaded = true
        } catch is CancellationError {
            // Closing the panel cancels its poll without displaying a scan error.
        } catch { scanError = error.localizedDescription }
    }

    @concurrent private static func discover(visible: Bool) async throws -> ([Listener], [Int32: ResourceSample]) {
        let rows = try scan(previewSchemes: visible)
        var samples: [Int32: ResourceSample] = [:]
        if visible {
            for row in rows {
                try Task.checkCancellation()
                samples[row.id] = ResourceSample.read(row)
            }
        }
        return (rows, samples)
    }

    func append(_ line: String) {
        log.append(line)
        if log.count > 120 { log.removeFirst() }
    }

    func stopAll(_ captured: [Listener]) async {
        guard !busy, !captured.isEmpty else { return }
        busy = true
        defer { busy = false }
        var results: [String] = []
        for row in captured {
            let outcome = await ActionWorkflow.live.perform(.stop, on: row) { await self.append($0) }
            let line = "\(row.project) (PID \(row.id)): " + outcome.summary
            append(line)
            results.append(line)
        }
        lastOutcome = nil
        actionMessage = results.joined(separator: "\n")
        await refresh()
    }

    func perform(_ selection: Selection, command: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let row = selection.row
        actionMessage = ""
        append("\(Date.now.formatted(date: .omitted, time: .standard))  \(selection.action.rawValue) · \(row.project) · \(row.portText)")
        lastOutcome = nil
        let outcome = await ActionWorkflow.live.perform(selection.action, on: row, command: command) { message in
            await self.append(message)
        }
        lastOutcome = outcome
        append(outcome.summary)
        await refresh()
    }
}

struct Review: View {
    let selection: Selection
    let cancel: () -> Void
    let run: (String) -> Void
    @State private var command = ""
    @State private var edited = false

    var body: some View {
        let row = selection.row
        VStack(alignment: .leading, spacing: 16) {
            Text("\(selection.action.rawValue) \(row.project)?").font(.title2.bold())
            Text("This stops \(row.name) (PID \(String(row.id))) on \(row.ports.count == 1 ? "port" : "ports") \(row.portText).")
            Text("kill -TERM \(String(row.id))").foregroundStyle(terminalGreen).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            if selection.action == .restart {
                Divider()
                Text("Start command").font(.headline)
                Text("Terminal runs this command in a new shell after the selected server stops. Shared ports require an explicit bind to the selected address.")
                    .foregroundStyle(.secondary)
                Text("cd -- " + quote(row.directory ?? "")).foregroundStyle(terminalGreen).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                TextField("Enter the server’s launch command", text: Binding(get: { command }, set: { edited = true; command = $0 }))
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                    .accessibilityLabel("Start command")
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(selection.action.rawValue, systemImage: selection.action.symbol) { run(command) }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(ServerActionStyle(action: selection.action))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(selection.action == .restart && command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: selection.id) {
            guard selection.action == .restart else { return }
            let suggestion = await Task.detached { restartSuggestion(row) }.value
            if !Task.isCancelled && !edited { command = suggestion }
        }
    }
}

// On macOS 14 the SwiftUI window has an opaque backing beneath its content.
struct TerminalBackdrop: NSViewRepresentable {
    let desk: Desk
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    final class BackdropView: NSVisualEffectView {
        weak var desk: Desk?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
            if let window {
                window.isOpaque = false
                window.backgroundColor = .clear
                NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged),
                    name: NSWindow.didChangeOcclusionStateNotification, object: window)
            }
            visibilityChanged()
        }

        // The menu bar can retain the content view while its panel is closed.
        @objc private func visibilityChanged() {
            desk?.setPanelVisible(window?.occlusionState.contains(.visible) == true)
        }
    }

    func makeNSView(context: Context) -> BackdropView {
        let view = BackdropView()
        view.desk = desk
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: BackdropView, context: Context) {
        view.isHidden = reduceTransparency
    }
}

@main struct PortDeskApp: App {
    @StateObject private var desk = Desk()

    var body: some Scene {
        MenuBarExtra {
            Dashboard(desk: desk)
        } label: {
            Image(systemName: "powerplug.fill")
            Text(String(desk.rows.filter(\.manageable).count))
        }.menuBarExtraStyle(.window)
    }
}
