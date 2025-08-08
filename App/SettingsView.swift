import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var store: ClipboardStore
    var onCancel: () -> Void
    var onSave: () -> Void

    @State private var localKey: HotkeyChoice
    @State private var localModifiers: UInt32
    @State private var localTheme: AppTheme
    @State private var localMaxItems: Int
    @State private var localAutoClean: Bool

    init(store: ClipboardStore, onCancel: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        let s = AppSettings.shared
        _localKey = State(initialValue: HotkeyChoice.allCases.first(where: { $0.keyCode == s.hotkeyKeyCode }) ?? .v)
        _localModifiers = State(initialValue: s.hotkeyModifiers)
        _localTheme = State(initialValue: s.theme)
        _localMaxItems = State(initialValue: s.maxItems)
        _localAutoClean = State(initialValue: s.autoCleanEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Text("Hotkey").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Key").frame(width: 140, alignment: .trailing)
                        Picker("", selection: $localKey) {
                            ForEach(HotkeyChoice.allCases) { choice in
                                Text(choice.rawValue.uppercased()).tag(choice)
                            }
                        }
                        .labelsHidden()
                    }
                    HStack(spacing: 16) {
                        Text("Modifiers").frame(width: 140, alignment: .trailing)
                        Toggle("Cmd (⌘)", isOn: Binding(
                            get: { localModifiers.containsCmd },
                            set: { toggleModifier($0, mask: UInt32(cmdKey)) }
                        ))
                        Toggle("Ctrl (⌃)", isOn: Binding(
                            get: { localModifiers.containsCtrl },
                            set: { toggleModifier($0, mask: UInt32(controlKey)) }
                        ))
                        Toggle("Option (⌥)", isOn: Binding(
                            get: { localModifiers.containsAlt },
                            set: { toggleModifier($0, mask: UInt32(optionKey)) }
                        ))
                        Toggle("Shift (⇧)", isOn: Binding(
                            get: { localModifiers.containsShift },
                            set: { toggleModifier($0, mask: UInt32(shiftKey)) }
                        ))
                    }
                }
                .padding(8)
            }

            GroupBox(label: Text("Appearance").font(.headline)) {
                HStack {
                    Text("Theme").frame(width: 140, alignment: .trailing)
                    Picker("", selection: $localTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue.capitalized).tag(theme)
                        }
                    }
                    .labelsHidden()
                }
                .padding(8)
            }

            GroupBox(label: Text("History").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Maximum items").frame(width: 140, alignment: .trailing)
                        Stepper(value: $localMaxItems, in: 10...1000, step: 10) {
                            Text("\(localMaxItems)").foregroundColor(.secondary)
                        }
                        .frame(maxWidth: 240, alignment: .leading)
                    }
                    HStack {
                        Text("")
                            .frame(width: 140, alignment: .trailing)
                        Toggle("Auto clean old items", isOn: $localAutoClean)
                    }
                }
                .padding(8)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { applyAndSave() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
    }

    private func toggleModifier(_ isOn: Bool, mask: UInt32) {
        if isOn {
            localModifiers = localModifiers | mask
        } else {
            localModifiers = localModifiers & ~mask
        }
    }

    private func applyAndSave() {
        // Persist settings
        settings.hotkeyKeyCode = localKey.keyCode
        settings.hotkeyModifiers = localModifiers
        settings.theme = localTheme
        settings.maxItems = max(10, localMaxItems)
        settings.autoCleanEnabled = localAutoClean

        // Apply hotkey
        GlobalHotKeyManager.shared.unregister()
        GlobalHotKeyManager.shared.register(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)

        // Apply max items immediately
        store.applyMaxItems(settings.maxItems)

        // Notify theme change for overlays still open
        NotificationCenter.default.post(name: .themeChanged, object: nil)
        onSave()
    }
}

final class SettingsWindowController: NSObject {
    private var window: NSWindow?
    private let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let view = SettingsView(store: store, onCancel: { [weak self] in
                self?.window?.close()
            }, onSave: { [weak self] in
                self?.window?.close()
            }).environmentObject(store)
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                                   styleMask: [.titled, .closable],
                                   backing: .buffered,
                                   defer: false)
            window.title = "Settings"
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.level = .modalPanel
            self.window = window
        }

        guard let window else { return }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}

enum SettingsWindow {
    static private var controller: SettingsWindowController?
    static func sharedController() -> SettingsWindowController {
        if let controller { return controller }
        let c = SettingsWindowController(store: ClipboardStore())
        controller = c
        return c
    }

    static func show(with store: ClipboardStore) {
        if controller == nil {
            controller = SettingsWindowController(store: store)
        }
        controller?.show()
    }
}

