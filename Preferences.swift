import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General", shortcut = "Shortcut", refresh = "Refresh"
    var id: Self { self }
    var icon: String {
        switch self { case .general: "gearshape"; case .shortcut: "keyboard"; case .refresh: "arrow.clockwise" }
    }
}

struct Preferences: View {
    @Binding var tab: SettingsTab
    @ObservedObject var shortcuts: GlobalShortcut
    @AppStorage("showAll") private var showAll = false
    @AppStorage("closeAfterOpening") private var closeAfterOpening = true
    @AppStorage("refreshSeconds") private var interval = 2
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError = ""
    @State private var savingLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.icon).font(.system(size: 21)).frame(height: 24)
                            Text(item.rawValue).font(.callout)
                        }.padding(.horizontal, 7).frame(height: 47)
                            .background(tab == item ? Color.primary.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                        .foregroundStyle(tab == item ? Color.accentColor : .secondary)
                        .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }.frame(maxWidth: .infinity).padding(.bottom, 16)
            Text(tab == .shortcut ? "Keyboard shortcut" : tab.rawValue).font(.headline).padding(.leading, 10)
            switch tab {
            case .general:
                card {
                    switchRow("Launch at login", Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval }, set: changeLogin)).disabled(savingLogin)
                    if loginStatus == .requiresApproval {
                        Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    if !loginError.isEmpty { Text(loginError).font(.caption).foregroundStyle(.orange) }
                    Divider()
                    switchRow("Show all listening ports", $showAll)
                    Divider()
                    hint("When off, only development servers are shown.")
                    Divider()
                    switchRow("Close menu after opening", $closeAfterOpening)
                    Divider()
                    hint("Dismiss the menu when you open a server or terminal. Turn off to keep it open.")
                }
                Text("About").font(.headline).padding(.leading, 10).padding(.top, 16)
                card {
                    valueRow("Version", "v" + version("CFBundleShortVersionString") + " (" + version("CFBundleVersion") + ")")
                }
            case .shortcut:
                card {
                    switchRow("Open Ports with a global shortcut", Binding(get: { shortcuts.enabled }, set: shortcuts.setEnabled))
                    Divider()
                    HStack {
                        Text("Shortcut")
                        Spacer()
                        ShortcutRecorder(shortcuts: shortcuts).frame(width: 115, height: 24)
                        Button("Reset") { shortcuts.replace(with: .standard) }
                    }
                    Divider()
                    hint("Press the shortcut anywhere to open Ports with keyboard navigation: arrow keys to select a port, then O to open it, T for the terminal, and K to review stopping it.")
                    if !shortcuts.notice.isEmpty { Text(shortcuts.notice).font(.caption).foregroundStyle(.orange) }
                }
            case .refresh:
                card {
                    valueRow("Live update interval", "\(interval)s")
                    Divider()
                    HStack {
                        Spacer()
                        Slider(value: Binding(get: { Double(interval) }, set: { interval = Int($0.rounded()) }),
                               in: 1...10, step: 1) { Text("Live update interval") }
                            .labelsHidden().frame(width: 198)
                    }
                    Divider()
                    hint("How often CPU, memory, and energy update while the menu is open.")
                }
                card { hint("Energy is an estimate based on CPU usage and wakeups. macOS does not expose true per-process battery drain.") }
            }
            Spacer(minLength: 0)
        }
        .toggleStyle(.switch).controlSize(.small)
        .padding(.horizontal, 20).padding(.bottom, 20)
        .frame(width: 420, height: 416, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    private func switchRow(_ label: String, _ value: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5))
            Spacer()
            Toggle(label, isOn: value).labelsHidden().controlSize(.mini)
        }
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5))
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func version(_ key: String) -> String { Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—" }
    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func changeLogin(_ on: Bool) {
        savingLogin = true
        Task {
            defer { loginStatus = SMAppService.mainApp.status; savingLogin = false }
            do {
                if on { try SMAppService.mainApp.register() }
                else { try await SMAppService.mainApp.unregister() }
                loginError = ""
            } catch { loginError = error.localizedDescription }
        }
    }
}

/// Keep the settings title centered above the three tabs across macOS title-bar styles.
@MainActor final class PreferencesWindow: NSWindow {
    private let heading = NSTextField(labelWithString: "")

    init(tab: SettingsTab) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 416),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        appearance = NSAppearance(named: .darkAqua)
        if let bar = standardWindowButton(.closeButton)?.superview {
            heading.font = .systemFont(ofSize: 13, weight: .semibold)
            heading.textColor = .secondaryLabelColor
            heading.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(heading)
            NSLayoutConstraint.activate([
                heading.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
                heading.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
            ])
        }
        setHeading(tab.rawValue)
    }

    func setHeading(_ text: String) {
        title = text
        heading.stringValue = text
    }
}
