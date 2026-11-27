import AppKit
import Carbon
import SwiftUI

struct Shortcut: Equatable {
    let code: UInt32
    let modifiers: UInt32
    let label: String

    static let standard = Self(code: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | optionKey), label: "⌥⌘P")

    init(code: UInt32, modifiers: UInt32, label: String) {
        self.code = code
        self.modifiers = modifiers
        self.label = label
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.isDisjoint(with: [.command, .option, .control]),
              let key = event.charactersIgnoringModifiers?.uppercased(), key.count == 1,
              let scalar = key.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) else { return nil }
        var mask: UInt32 = 0
        var glyphs = ""
        for (flag, carbon, glyph) in [(NSEvent.ModifierFlags.control, controlKey, "⌃"),
                                        (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")] {
            if flags.contains(flag) { mask |= UInt32(carbon); glyphs += glyph }
        }
        self.init(code: UInt32(event.keyCode), modifiers: mask, label: glyphs + key)
    }
}

@MainActor final class GlobalShortcut: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var shortcut: Shortcut
    @Published var notice = ""
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let open: () -> Void
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, open: @escaping () -> Void) {
        self.defaults = defaults
        self.open = open
        enabled = defaults.object(forKey: "shortcutEnabled") as? Bool ?? true
        if let stored = defaults.dictionary(forKey: "shortcut"),
           let code = stored["code"] as? UInt32, let modifiers = stored["modifiers"] as? UInt32,
           let label = stored["label"] as? String {
            shortcut = Shortcut(code: code, modifiers: modifiers, label: label)
        } else { shortcut = .standard }
    }

    func connect() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout.size(ofValue: id), nil, &id) == noErr,
                  id.signature == 0x5044534B, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().open()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr {
            enabled = false
            notice = "Keyboard shortcuts are unavailable in this session."
        } else if enabled {
            setEnabled(true)
        }
    }

    private func register(_ key: Shortcut) -> EventHotKeyRef? {
        var result: EventHotKeyRef?
        let status = RegisterEventHotKey(key.code, key.modifiers, EventHotKeyID(signature: 0x5044534B, id: 1),
                                         GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &result)
        return status == noErr ? result : nil
    }

    func setEnabled(_ value: Bool) {
        if value && registration == nil {
            registration = register(shortcut)
            if registration == nil {
                notice = "This shortcut is unavailable. Record a different combination."
                enabled = false
                return
            }
        } else if !value, let registration {
            UnregisterEventHotKey(registration)
            self.registration = nil
        }
        enabled = value
        notice = ""
        defaults.set(value, forKey: "shortcutEnabled")
    }

    func replace(with key: Shortcut) {
        if enabled && key != shortcut {
            guard let next = register(key) else {
                notice = "This shortcut is already in use."
                return
            }
            if let registration { UnregisterEventHotKey(registration) }
            registration = next
        }
        shortcut = key
        notice = ""
        defaults.set(["code": key.code, "modifiers": key.modifiers, "label": key.label], forKey: "shortcut")
    }

    func invalidate() {
        if let registration { UnregisterEventHotKey(registration); self.registration = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}

/// The recorder receives keys only while it is the first responder in Settings.
struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var shortcuts: GlobalShortcut

    final class RecorderButton: NSButton {
        var capture: ((NSEvent) -> Void)?
        var normalTitle = ""
        var recording = false
        override var acceptsFirstResponder: Bool { true }
        @objc func begin() {
            window?.makeFirstResponder(self)
            recording = true
            title = "Press shortcut…"
        }
        override func resignFirstResponder() -> Bool {
            recording = false
            title = normalTitle
            return super.resignFirstResponder()
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording, window?.isKeyWindow == true else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            recording = false
            title = normalTitle
            if event.keyCode != kVK_Escape { capture?(event) }
        }
    }

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.target = button
        button.action = #selector(RecorderButton.begin)
        button.bezelStyle = .rounded
        button.setAccessibilityLabel("Record global shortcut")
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.normalTitle = shortcuts.shortcut.label
        if !button.recording { button.title = button.normalTitle }
        button.capture = { event in
            if let key = Shortcut(event: event) { shortcuts.replace(with: key) }
            else { shortcuts.notice = "Use a letter or number with Command, Option or Control." }
        }
    }
}
