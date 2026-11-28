import AppKit
import SwiftUI

private actor FixtureClock {
    var delays: [Duration] = []
    private var continuation: AsyncStream<Void>.Continuation?
    func sleep(_ duration: Duration) async throws {
        let stream = AsyncStream<Void>.makeStream()
        continuation = stream.continuation
        delays.append(duration)
        for await _ in stream.stream { break }
        try Task.checkCancellation()
    }
    func tick() { continuation?.finish() }
}

private actor FixtureDiscovery {
    var visibleCalls: [Bool] = []
    let listeners: [Listener]

    init() {
        let names = ["sample-studio-site", "small-site", "ControlCenter", "ControlCenter", "node",
                     "Notes Helper", "MacOS", "MacOS", "webstorm", "test-helper"]
        let ports = [3000, 3397, 5000, 7000, 7265, 27124, 30000, 30001, 30002, 30123]
        listeners = names.indices.map { index in
            var row = Listener(id: Int32(96481 - index))
            row.uid = getuid()
            row.name = index < 2 ? "node" : names[index]
            row.fingerprint = Identity(uid: getuid(), seconds: UInt64(Date.now.timeIntervalSince1970) - (index == 0 ? 4080 : 480), micros: 0)
            row.directory = index < 2 ? "/Users/developer/Documents/Work/code/example/local-development-sites/apps/" + names[index] : "/"
            row.terminal = index == 0 ? "/dev/ttys009" : nil
            row.endpoints = [Endpoint("127.0.0.1:\(ports[index])", family: "IPv4")!]
            return row
        }
    }

    func snapshot(_ visible: Bool) -> ([Listener], [Int32: ResourceSample]) {
        visibleCalls.append(visible)
        var samples: [Int32: ResourceSample] = [:]
        if visible {
            for row in listeners {
                samples[row.id] = ResourceSample(identity: row.fingerprint!, timestamp: UInt64(visibleCalls.count) * 1_000_000_000,
                                                 cpuTicks: 4, wakeups: 0, footprint: row.id == 96481 ? 25_000_000 : 201_000_000)
            }
        }
        return (listeners, samples)
    }
}

@main struct DashboardChecks {
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .darkAqua)
        let fixture = FixtureDiscovery()
        let clock = FixtureClock()
        let desk = Desk(discover: { await fixture.snapshot($0) }, wait: { try await clock.sleep($0) })
        func until(_ condition: () async -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(5)
            while !(await condition()) {
                if ContinuousClock.now >= deadline { throw DeskError("Dashboard fixture timed out.") }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        desk.setPanelVisible(false)
        try await until { await clock.delays.count == 1 }
        precondition(desk.metrics.isEmpty)
        await clock.tick()
        try await until { await clock.delays.count == 2 }
        desk.setPanelVisible(true)
        try await until { await clock.delays.count == 3 }
        precondition(desk.metrics.values.allSatisfy { $0.cpu == nil })
        await clock.tick()
        try await until { await clock.delays.count == 4 }
        let calls = await fixture.visibleCalls
        let delays = await clock.delays
        precondition(calls == [false, false, true, true] && delays[0] == .seconds(30))
        precondition(desk.metrics[96481]?.energy == "Low" && desk.metrics[96481]?.memoryText == "25 MB")

        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let domain = "PortDesk.VisualChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let rows = PortRow.list(desk.rows, showAll: false)
        let states: [(String, Bool, Int?, Int?)] = [
            ("01-first-expanded", false, 0, nil), ("02-show-all", true, nil, nil),
            ("03-first-hover", false, nil, 0), ("04-first-expanded-hover", false, 0, 0),
            ("05-hover-kill", false, 0, 1), ("06-hover-open", false, 1, 0),
            ("07-hover-terminal", false, 1, 0)
        ]
        for (name, all, expanded, hover) in states {
            defaults.set(all, forKey: "showAll")
            let view = Dashboard(desk: desk, expanded: expanded.map { rows[$0].id }, hovered: hover.map { rows[$0].id },
                                 showSettings: {}, didOpen: {})
                .defaultAppStorage(defaults).background(Color(nsColor: .windowBackgroundColor))
            try await render(view, width: 470, title: nil, to: folder.appendingPathComponent(name + ".png"))
        }
        defaults.set(false, forKey: "showAll")
        desk.rows = [rows[0].listener]
        desk.reviewStop(rows[0])
        try await render(Dashboard(desk: desk, showSettings: {}, didOpen: {}).defaultAppStorage(defaults),
                         width: 470, title: nil, to: folder.appendingPathComponent("08-inline-stop.png"))
        desk.cancelStop()
        let keys = GlobalShortcut(defaults: defaults) {}
        for tab in SettingsTab.allCases {
            let view = Preferences(tab: .constant(tab), shortcuts: keys).defaultAppStorage(defaults)
            try await render(view, width: 420, title: tab.rawValue, to: folder.appendingPathComponent(tab.rawValue + ".png"))
        }
        let directory = try makeHTTPFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try startHTTPServer(in: directory, host: "127.0.0.1", port: 0)
        defer { finish(first) }
        let second = try startHTTPServer(in: directory, host: "127.0.0.1", port: 0)
        defer { finish(second) }
        let target = try findFixture(first)
        let (_, liveSamples) = try await Desk.liveSnapshot(visible: true)
        precondition(liveSamples[target.id]?.identity == target.fingerprint)
        precondition((liveSamples[target.id]?.footprint ?? 0) > 0)
        var stale = try findFixture(second)
        stale.fingerprint = nil
        await desk.stopAll([target, stale])
        let afterStop = try scan()
        precondition(!afterStop.contains { $0.id == target.id })
        precondition(afterStop.contains { $0.id == stale.id })
        precondition(desk.actionMessage.contains(String(target.id)) && desk.actionMessage.contains(String(stale.id)))
        do {
            try await revealTerminal(stale)
            throw DeskError("Accepted an unknown Terminal session.")
        } catch let error as DeskError {
            precondition(error.message.contains("session changed"))
        }

        let forceTarget = try findFixture(second)
        let forceRow = PortRow.list([forceTarget], showAll: false)[0]
        desk.reviewStop(forceRow)
        desk.cancelStop()
        let before = desk.log
        await desk.confirmStop(.forceStop, for: forceRow.id)
        precondition(second.isRunning && desk.log == before)
        desk.reviewStop(forceRow)
        await desk.confirmStop(.forceStop, for: forceRow.id)
        guard case .stopped = desk.lastOutcome else { throw DeskError("Force did not stop the fixture.") }
        second.waitUntilExit()
        precondition(second.terminationReason == .uncaughtSignal && second.terminationStatus == SIGKILL)
        precondition(desk.log.contains("$ kill -KILL " + String(forceTarget.id)))

        desk.setPanelVisible(false)
        try await until { await clock.delays.count == 5 }
        precondition(desk.metrics.isEmpty)
        print("Verified hidden and visible polling, resource baselines and inline Force and cancel, and eleven rendered dashboard/settings states.")
    }

    @MainActor private static func render<V: View>(_ view: V, width: CGFloat, title: String?, to file: URL) async throws {
        let host = NSHostingView(rootView: view.fixedSize())
        let size = host.fittingSize
        guard abs(size.width - width) < 1, size.height >= 100 else { throw DeskError("Unexpected geometry \(size): \(file.lastPathComponent)") }
        let window: NSWindow
        if let title, let tab = SettingsTab(rawValue: title) { window = PreferencesWindow(tab: tab) }
        else { window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false) }
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.title = title ?? ""
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let content: NSView = title == nil ? host : (host.superview ?? host)
        let bounds = content.bounds
        let expectedHeight: CGFloat
        switch file.deletingPathExtension().lastPathComponent {
        case "02-show-all": expectedHeight = 479
        case "08-inline-stop": expectedHeight = 110
        case "03-first-hover": expectedHeight = 159
        default: expectedHeight = title == nil ? 284 : 448
        }
        guard abs(bounds.height - expectedHeight) <= 2 else {
            throw DeskError("Expected \(expectedHeight) pt for \(file.lastPathComponent), measured \(bounds.height).")
        }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2),
                                         pixelsHigh: Int(bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw DeskError("Could not allocate snapshot.")
        }
        rep.size = bounds.size
        content.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw DeskError("PNG encoding failed.") }
        try png.write(to: file)
        print("\(file.lastPathComponent): \(Int(bounds.width)) × \(Int(bounds.height)) pt")
    }
}
