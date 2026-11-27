import AppKit
import Combine
import SwiftUI

private final class PortsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor final class MenuController: NSObject, NSApplicationDelegate {
    private let desk = Desk()
    private var item: NSStatusItem!
    private let panel = PortsPanel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 112),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var preferencesWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var localClicks: Any?
    private var outsideClicks: Any?
    private lazy var shortcuts = GlobalShortcut { [weak self] in self?.showPanel(keyboard: true) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let button = item.button
        button?.image = NSImage(systemSymbolName: "powerplug.fill", accessibilityDescription: "Port Desk")
        button?.imagePosition = .imageLeading
        button?.target = self
        button?.action = #selector(togglePanel)
        desk.$rows.map { $0.filter(\.manageable).count }.removeDuplicates().sink { [weak button] count in
            button?.title = " " + String(count)
            button?.setAccessibilityLabel("Port Desk, \(count) development servers")
        }.store(in: &subscriptions)

        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let root = Dashboard(desk: desk, showSettings: { [weak self] in self?.showSettings() },
                             didOpen: { [weak self] in self?.didOpen() })
            .fixedSize()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.15)).allowsHitTesting(false))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] size in self?.resize(size) }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
        resize(host.fittingSize)
        _ = shortcuts
    }

    private func resize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let top = panel.frame.maxY
        var frame = panel.frame
        frame.size = size
        frame.origin.y = top - size.height
        if frame != panel.frame { panel.setFrame(frame, display: panel.isVisible) }
    }

    @objc private func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel(keyboard: false) }
    }

    private func showPanel(keyboard: Bool) {
        guard let button = item.button, let window = button.window, let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let left = min(max(screen.frame.minX + 4, anchor.midX - panel.frame.width / 2),
                       screen.frame.maxX - panel.frame.width - 4)
        panel.setFrameTopLeftPoint(NSPoint(x: left, y: anchor.minY - 2))
        panel.makeKeyAndOrderFront(nil)
        desk.setPanelVisible(true)
        if keyboard { desk.keyboardRequest += 1 }
        guard localClicks == nil else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClicks = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            if let self, event.window !== self.panel && event.window !== self.item.button?.window {
                self.hidePanel()
            }
            return event
        }
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in self?.hidePanel() }
    }

    private func didOpen() {
        if UserDefaults.standard.object(forKey: "closeAfterOpening") as? Bool ?? true { hidePanel() }
    }

    private func hidePanel() {
        panel.orderOut(nil)
        desk.setPanelVisible(false)
        if let localClicks { NSEvent.removeMonitor(localClicks); self.localClicks = nil }
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks); self.outsideClicks = nil }
    }

    private func showSettings() {
        hidePanel()
        if preferencesWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 418),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = SettingsTab.general.rawValue
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: SettingsWindowContent(shortcuts: shortcuts) { [weak window] title in
                window?.title = title
            })
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hidePanel()
        shortcuts.invalidate()
    }
}

private struct SettingsWindowContent: View {
    @ObservedObject var shortcuts: GlobalShortcut
    let title: (String) -> Void
    @State private var tab = SettingsTab.general
    var body: some View {
        Preferences(tab: $tab, shortcuts: shortcuts)
            .onChange(of: tab) { _, value in title(value.rawValue) }
    }
}

@main struct PortDeskApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let controller = MenuController()
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}
