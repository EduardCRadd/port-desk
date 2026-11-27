import Accessibility
import AppKit
import SwiftUI

struct Dashboard: View {
    @ObservedObject var desk: Desk
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @AppStorage("showAll") private var showAll = false
    @State private var expanded: PortRow.ID?
    @State private var hovered: PortRow.ID?
    @State private var selection: PortRow.ID?
    @State private var review: Selection?
    @State private var history = false
    @FocusState private var listFocused: Bool

    private var rows: [PortRow] { PortRow.list(desk.rows, showAll: showAll) }

    var body: some View {
        Group {
            if let review {
                Review(selection: review, cancel: { self.review = nil }) { command in
                    self.review = nil
                    Task { await desk.perform(review, command: command) }
                }.id(review.id).padding().frame(height: 300)
            } else if history {
                historyView
            } else {
                ports
            }
        }
        .frame(width: 470)
        .background {
            ZStack {
                TerminalBackdrop(desk: desk)
                if opaque { Color(nsColor: .windowBackgroundColor) }
            }.ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onChange(of: desk.busy) { wasBusy, busy in
            if wasBusy, !busy, let message = desk.lastOutcome?.summary, NSApp.keyWindow != nil {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    private var ports: some View {
        let displayed = rows
        let hasDetail = displayed.contains { $0.id == expanded }
        let listHeight = min(416, max(49, displayed.count * 49 + (hasDetail ? 125 : 0)))
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Ports").font(.headline.bold())
                Spacer()
                Button { Task { await desk.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .keyboardShortcut("r").help("Refresh").accessibilityLabel("Refresh")
                Color.clear.frame(width: 16).accessibilityHidden(true)
                Toggle("Show all", isOn: $showAll).toggleStyle(.switch).controlSize(.small)
            }.padding(.horizontal, 12).frame(height: 32)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if displayed.isEmpty {
                            Text(desk.loaded ? "No listening servers" : "Reading ports…")
                                .foregroundStyle(.secondary).frame(height: 48)
                        }
                        ForEach(displayed) { item in portLine(item).id(item.id) }
                    }
                }
                .onChange(of: selection) { _, id in if let id { proxy.scrollTo(id) } }
            }.frame(height: CGFloat(listHeight))
            .focusable().focused($listFocused).focusEffectDisabled()
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress("o") { selectedAction { open($0) } }
            .onKeyPress("k") { selectedAction { confirm(.stop, $0.listener) } }
            if !desk.scanError.isEmpty { Text(desk.scanError).foregroundStyle(.orange).padding(4) }
            if let summary = desk.lastOutcome?.summary, !desk.busy {
                Text(summary).font(.caption).padding(4).textSelection(.enabled)
            }
            Divider()
            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.disabled(desk.busy).keyboardShortcut("q")
            }.padding(.horizontal, 12).frame(height: 29)
        }.buttonStyle(.plain)
    }

    private func portLine(_ item: PortRow) -> some View {
        let row = item.listener
        let metrics = desk.metrics[row.id] ?? ProcessMetrics()
        let active = hovered == item.id || selection == item.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button { open(item) } label: {
                    Text(":" + String(item.endpoint.port)).font(.system(.body, design: .monospaced).bold())
                }.foregroundStyle(.blue).frame(width: 56, alignment: .leading)
                    .disabled(!row.manageable).accessibilityLabel("Open port \(item.endpoint.port)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        Label("Unknown", systemImage: "questionmark.dashed")
                        Label(uptime(row), systemImage: "clock")
                        Label(metrics.cpuText, systemImage: "cpu")
                        Label(metrics.memoryText, systemImage: "memorychip")
                        Label(metrics.energy ?? "—", systemImage: "bolt.fill")
                            .foregroundStyle(metrics.energy == "Low" ? Color.green : Color.secondary)
                    }.labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if active && row.manageable {
                    icon("arrow.up.right.square", "Open " + (url(item)?.absoluteString ?? item.title)) { open(item) }
                    icon("xmark.octagon", "Kill this process") { confirm(.stop, row) }.disabled(desk.busy)
                }
                icon(expanded == item.id ? "chevron.down" : "chevron.right", "Details for \(item.title), PID \(row.id)") {
                    toggle(item)
                }.foregroundStyle(.secondary)
            }.padding(.horizontal, 12).frame(height: 48)
            .contentShape(Rectangle()).onTapGesture { toggle(item) }
            if expanded == item.id { inspector(item) }
            Divider().padding(.leading, 12)
        }
        .background(active ? Color.primary.opacity(0.055) : .clear)
        .onHover { inside in
            if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
        }
        .contextMenu {
            if row.manageable {
                Button("Restart…") { confirm(.restart, row) }.disabled(desk.busy)
                if let alternate = url(item, alternate: true) {
                    Button("Open with " + (alternate.scheme?.uppercased() ?? "")) { NSWorkspace.shared.open(alternate) }
                }
            }
            Button("Command History") { history = true }
        }
    }

    private func icon(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 20, height: 22) }
            .help(label).accessibilityLabel(label)
    }

    private func inspector(_ item: PortRow) -> some View {
        let metrics = desk.metrics[item.listener.id] ?? ProcessMetrics()
        return VStack(alignment: .leading, spacing: 7) {
            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 5) {
                ForEach([("PID", String(item.listener.id)), ("Command", item.listener.name),
                         ("Directory", item.listener.directory ?? "Unavailable")], id: \.0) { pair in
                    GridRow {
                        Text(pair.0).foregroundStyle(.secondary).frame(width: 68, alignment: .leading)
                        Text(pair.1).lineLimit(2).textSelection(.enabled).help(pair.1)
                    }
                }
            }
            Divider()
            HStack(spacing: 15) {
                ForEach([("Port", ":" + String(item.endpoint.port)), ("Uptime", uptime(item.listener)),
                         ("CPU", metrics.cpuText), ("Memory", metrics.memoryText), ("Energy", metrics.energy.map { $0 + " impact" } ?? "—")], id: \.0) { pair in
                    VStack(alignment: .leading) {
                        Text(pair.0).font(.caption2).foregroundStyle(.secondary)
                        Text(pair.1)
                    }
                }
            }
        }.font(.callout).padding(.horizontal, 14).frame(height: 125, alignment: .topLeading)
    }

    private func uptime(_ row: Listener) -> String {
        guard let start = row.fingerprint?.seconds else { return "—" }
        let minutes = max(0, Int(Date().timeIntervalSince1970 - Double(start)) / 60)
        if minutes >= 1440 { return "\(minutes / 1440)d \(minutes / 60 % 24)h" }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private func toggle(_ item: PortRow) {
        selection = item.id
        expanded = expanded == item.id ? nil : item.id
        listFocused = true
    }

    private func move(_ delta: Int) {
        let list = rows
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : list.count)
        selection = list[min(max(0, current + delta), list.count - 1)].id
    }

    private func selectedAction(_ action: (PortRow) -> Void) -> KeyPress.Result {
        guard let item = rows.first(where: { $0.id == selection }), item.listener.manageable else { return .ignored }
        action(item)
        return .handled
    }

    private func url(_ item: PortRow, alternate: Bool = false) -> URL? {
        let https = item.listener.usesHTTPS || item.endpoint.port == 443
        return item.endpoint.url(https: alternate ? !https : https, sharedPort: item.listener.sharedPorts.contains(item.endpoint.port))
    }

    private func open(_ item: PortRow) {
        if item.listener.manageable, let url = url(item) { NSWorkspace.shared.open(url) }
    }

    private func confirm(_ action: Action, _ row: Listener) {
        guard row.manageable, !desk.busy else { return }
        review = Selection(row: row, action: action)
    }

    private var historyView: some View {
        VStack(alignment: .leading) {
            Text("Command History").font(.headline)
            ScrollView {
                Text(desk.log.isEmpty ? "No commands yet." : desk.log.joined(separator: "\n"))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Copy history") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(desk.log.joined(separator: "\n"), forType: .string)
                }
                Spacer()
                Button("Done") { history = false }.keyboardShortcut(.cancelAction)
            }
        }.padding().frame(height: 260)
    }
}
