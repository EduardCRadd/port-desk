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
    @Published var scanError = ""
    @Published var busy = false
    @Published var loaded = false
    @Published var log = [String]()
    @Published private(set) var lastOutcome: ActionOutcome?
    private var scanning = false
    private var pollTask: Task<Void, Never>?

    func setPanelVisible(_ visible: Bool) {
        guard visible else {
            pollTask?.cancel()
            return
        }
        if let pollTask, !pollTask.isCancelled { return }
        let previous = pollTask
        pollTask = Task {
            // A rapid reopen waits for the previous cancelled scan to relinquish the refresh slot.
            await previous?.value
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
            }
        }
    }

    func refresh() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        do {
            let result = try await Self.discover()
            try Task.checkCancellation()
            rows = result
            scanError = ""
            loaded = true
        } catch is CancellationError {
            // Closing the panel cancels its poll without displaying a scan error.
        } catch { scanError = error.localizedDescription }
    }

    @concurrent private static func discover() async throws -> [Listener] {
        try scan(previewSchemes: true)
    }

    func append(_ line: String) {
        log.append(line)
        if log.count > 120 { log.removeFirst() }
    }

    func perform(_ selection: Selection, command: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let row = selection.row
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
                Text("Terminal runs this command in a new shell after the port is free. Include any settings your server needs.")
                    .foregroundStyle(.secondary)
                Text("cd -- " + quote(row.directory ?? "")).foregroundStyle(terminalGreen).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                TextField("Enter the server’s launch command", text: Binding(get: { command }, set: { edited = true; command = $0 }))
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(selection.action.rawValue, systemImage: selection.action.symbol) { run(command) }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(ServerActionStyle(action: selection.action))
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
private struct TerminalBackdrop: NSViewRepresentable {
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

struct Dashboard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openURL) private var openURL
    @ObservedObject var desk: Desk
    @State private var review: Selection?
    @State private var showOthers = false
    @State private var showHistory = false

    func rowView(_ row: Listener) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                if row.manageable {
                    ForEach(row.previewEndpoints, id: \.port) { endpoint in
                        let https = row.usesHTTPS || endpoint.port == 443
                        let shared = row.sharedPorts.contains(endpoint.port)
                        if let url = endpoint.url(https: https, sharedPort: shared) {
                            Link(destination: url) {
                                Text(String(endpoint.port)).underline().foregroundStyle(terminalGreen)
                            }
                                .buttonStyle(.plain)
                                .focusable(true, interactions: [.activate, .edit])
                                .onKeyPress(keys: [.return, .space], phases: .down) { _ in
                                    openURL(url)
                                    return .handled
                                }
                                .help(url.absoluteString)
                                .accessibilityLabel("Open \(row.project) preview on port \(String(endpoint.port))")
                                .contextMenu {
                                    if let alternate = endpoint.url(https: !https, sharedPort: shared) {
                                        Link("Open with " + (https ? "HTTP" : "HTTPS"), destination: alternate)
                                    }
                                }
                        } else { Text(String(endpoint.port)) }
                    }
                } else {
                    ForEach(row.sortedPorts, id: \.self) { Text(String($0)).foregroundStyle(.secondary) }
                }
            }
            .font(.system(.body, design: .monospaced, weight: .medium))
            .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.manageable ? row.project : row.name).font(.headline).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Text([row.manageable ? row.name : nil, "PID " + String(row.id)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if row.manageable, let folder = row.directory {
                    Text((folder as NSString).abbreviatingWithTildeInPath)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                        .help(folder).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if row.manageable {
                HStack(spacing: 6) {
                    actionButton(.restart, row: row)
                    actionButton(.stop, row: row)
                }.disabled(desk.busy)
            }
        }.padding(.vertical, 6)
    }

    private func actionButton(_ action: Action, row: Listener) -> some View {
        let description = "\(action.rawValue) \(row.project) on \(row.portText)"
        return Button(action.rawValue, systemImage: action.symbol) {
            review = Selection(row: row, action: action)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(ServerActionStyle(action: action, compact: true))
        .help(description + "…")
        .accessibilityLabel(description)
    }

    private var list: some View {
        let previews = desk.rows.filter(\.manageable)
        let others = desk.rows.filter { !$0.manageable }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Listening ports").font(.title.weight(.semibold))
                    Text("This Mac · \(Set(desk.rows.flatMap(\.ports)).count) TCP ports")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await desk.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r")
            }.padding(.bottom, 10)
            if !desk.scanError.isEmpty { Text(desk.scanError).foregroundStyle(.orange).textSelection(.enabled) }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Development servers").font(.headline).foregroundStyle(.secondary).padding(.vertical, 8)
                    if previews.isEmpty {
                        Text(desk.loaded ? "No development servers listening." : "Reading listening ports…")
                            .foregroundStyle(.secondary).padding(.vertical, 14)
                    }
                    ForEach(previews) { row in Divider(); rowView(row) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            DisclosureGroup(isExpanded: $showOthers) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(others) { row in rowView(row); Divider() }
                        if others.isEmpty { Text("No other listeners.").foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: others.isEmpty ? 24 : 110)
            } label: { Text("Other listeners (\(others.count))").font(.headline) }
            .padding(.vertical, 6)
            Divider()
            DisclosureGroup(isExpanded: $showHistory) {
                history
                if !desk.log.isEmpty {
                    Button("Copy commands and results") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(desk.log.joined(separator: "\n"), forType: .string)
                    }
                }
            } label: {
                HStack {
                    Text("Command history").font(.headline)
                    if desk.busy { ProgressView().controlSize(.small).accessibilityLabel("Server action in progress") }
                }
            }.padding(.vertical, 6)
            Divider()
            HStack {
                Spacer()
                Button("Quit Port Desk") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .disabled(desk.busy)
            }.padding(.top, 8)
        }
    }

    private var history: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    if desk.log.isEmpty { Text("Your stop and restart commands will appear here.").foregroundStyle(.secondary) }
                    ForEach(Array(desk.log.enumerated()), id: \.offset) { i, line in
                        Text(line).foregroundStyle(line.hasPrefix("$ ") ? terminalGreen : .primary).id(i)
                    }
                }.textSelection(.enabled).font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .onChange(of: desk.log, initial: true) { _, lines in
                if !lines.isEmpty { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
            }
        }.frame(height: 82).background(Color.black.opacity(0.23), in: RoundedRectangle(cornerRadius: 7))
    }

    var body: some View {
        Group {
            if let selection = review {
                Review(selection: selection, cancel: { review = nil }) { command in
                    review = nil
                    Task { await desk.perform(selection, command: command) }
                }.id(selection.id)
            } else {
                list
            }
        }
        .padding(16).frame(width: 510, height: 490)
        .background {
            ZStack {
                TerminalBackdrop(desk: desk)
                Color(white: 0.085).opacity(reduceTransparency ? 1 : 0.16)
            }.ignoresSafeArea().allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
    }
}

@main struct PortDeskApp: App {
    @StateObject private var desk = Desk()

    var body: some Scene {
        MenuBarExtra("Port Desk", systemImage: "terminal") {
            Dashboard(desk: desk).tint(terminalGreen)
        }.menuBarExtraStyle(.window)
    }
}
