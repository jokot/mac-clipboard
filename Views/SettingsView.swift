import SwiftUI
import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, shortcuts, storage, privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .shortcuts: return "Shortcuts"
        case .storage: return "Storage"
        case .privacy: return "Privacy"
        }
    }

    /// ⌘1 to ⌘4, in the order of the tabs.
    var shortcut: String {
        "\u{2318}\((Self.allCases.firstIndex(of: self) ?? 0) + 1)"
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "circle.lefthalf.filled"
        case .shortcuts: return "keyboard"
        case .storage: return "internaldrive"
        case .privacy: return "hand.raised"
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var accentStore = AccentStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject var viewModel: ClipboardListViewModel
    @State private var tab: SettingsTab = .general
    @ObservedObject private var focus = SettingsFocusState.shared
    /// The focusable controls of the visible tab, in order.
    @State private var controlIDs: [String] = []
    @State private var isCapturingHotkey = false
    /// The extract shortcut that waits for new keys, or nil.
    @State private var extractCapture: ExtractKind?

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Rectangle().fill(Theme.line).frame(height: 1)
            ScrollViewReader { proxy in
            ScrollView {
                Group {
                    switch tab {
                    case .general:
                        GeneralTab(settings: settings, applyTheme: applyTheme)
                    case .appearance:
                        AppearanceTab(settings: settings, applyTheme: applyTheme)
                    case .shortcuts:
                        ShortcutsTab(settings: settings,
                                     isCapturingHotkey: $isCapturingHotkey,
                                     extractCapture: $extractCapture,
                                     hotKeyDescription: hotKeyDescription)
                    case .storage:
                        StorageTab(settings: settings, viewModel: viewModel)
                    case .privacy:
                        PrivacyTab(settings: settings, viewModel: viewModel,
                                   addApplicationViaPicker: addApplicationViaPicker)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
            .onPreferenceChange(SettingsFocusIDsKey.self) { controlIDs = $0 }
            .onChange(of: focus.focused) { id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
            }
            }
        }
        .frame(width: SettingsWindowController.contentSize.width, height: SettingsWindowController.contentSize.height)
        .shortcutsPanel(.settings, title: "Settings", note: "A ring shows the control that takes the keys.") {
            [SettingsKeyMap.table.groups()]
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsCommand)) { note in
            if let command = note.object as? SettingsCommand { perform(command) }
        }
        .onAppear { setWindowTitle() }
        .onChange(of: tab) { _ in
            focus.focused = nil
            isCapturingHotkey = false
            extractCapture = nil
            setWindowTitle()
        }
        .background(HotkeyCapturingView(isCapturing: Binding(
            get: { isCapturingHotkey || extractCapture != nil },
            set: { if !$0 { isCapturingHotkey = false; extractCapture = nil } }
        )) { keyCode, modifiers in
            switch extractCapture {
            case .text:
                settings.extractTextKeyCode = keyCode
                settings.extractTextModifiers = modifiers
                extractCapture = nil
            case .code:
                settings.extractCodeKeyCode = keyCode
                settings.extractCodeModifiers = modifiers
                extractCapture = nil
            case nil:
                updateHotkey(keyCode: keyCode, modifiers: modifiers)
            }
        })
    }

    /// Icon tabs under the title bar, like the System Settings windows of other Mac apps.
    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { item in
                Button(action: { tab = item }) {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 17))
                            .foregroundColor(tab == item ? Theme.accentText : .secondary)
                            .frame(height: 20)
                        Text(item.title)
                            .font(.system(size: 11))
                            .foregroundColor(tab == item ? .primary : .secondary)
                        Text(item.shortcut)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 76, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tab == item ? Theme.tileFill : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(item.title) (\(item.shortcut))")
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            ShortcutsButton(scope: .settings).padding(.trailing, 12)
        }
    }

    private func perform(_ command: SettingsCommand) {
        switch command {
        case .tab(let selected):
            tab = selected
        case .nextControl:
            focus.focused = SettingsFocus.move(in: controlIDs, from: focus.focused, by: 1)
        case .previousControl:
            focus.focused = SettingsFocus.move(in: controlIDs, from: focus.focused, by: -1)
        case .activate:
            send(.activate)
        case .stepBack:
            send(.step(-1))
        case .stepForward:
            send(.step(1))
        case .removeSelectedApp:
            guard let id = focus.focused, id.hasPrefix("app:") else {
                // No app has the focus: remove the app that a click selected.
                NotificationCenter.default.post(name: .settingsRemoveSelectedApp, object: nil)
                return
            }
            let next = SettingsFocus.afterRemoving(id, from: controlIDs)
            send(.remove)
            focus.focused = next
        case .close, .showShortcuts:
            break
        }
    }

    private func send(_ action: SettingsControlAction) {
        guard let id = focus.focused else { return NSSound.beep() }
        NotificationCenter.default.post(name: .settingsControlAction, object: SettingsControlEvent(id: id, action: action))
    }

    private func setWindowTitle() {
        SettingsWindowController.shared.window?.title = tab.title
    }

    private var hotKeyDescription: String {
        HotkeyUtils.description(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
    }

    private func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        HotKeyService.shared.unregister()
        settings.hotkeyKeyCode = keyCode
        settings.hotkeyModifiers = modifiers
        HotKeyService.shared.register(keyCode: keyCode, modifiers: modifiers)
        isCapturingHotkey = false
    }

    private func addApplicationViaPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
            let alert = NSAlert()
            alert.messageText = "Couldn't read bundle identifier"
            alert.informativeText = "The selected file does not look like a valid macOS app."
            alert.runModal()
            return
        }

        if settings.excludedBundleIDs.contains(bundleID) { return }   // already excluded; no-op

        let displayName = AppMetadata.shared.displayName(for: bundleID) ?? bundleID
        let count = viewModel.items.filter { $0.sourceBundleID == bundleID }.count

        let alert = NSAlert()
        alert.messageText = "Exclude \(displayName) from history?"
        alert.informativeText = "MaClip will no longer save clips copied from \(displayName). You can re-enable this in Settings → Privacy."
        alert.addButton(withTitle: "Exclude")
        alert.addButton(withTitle: "Cancel")

        let checkbox = NSButton(checkboxWithTitle: "Also remove \(count) existing clip\(count == 1 ? "" : "s") from history",
                                target: nil, action: nil)
        checkbox.state = .on
        checkbox.isHidden = (count == 0)
        alert.accessoryView = checkbox

        if alert.runModal() == .alertFirstButtonReturn {
            settings.excludedBundleIDs.append(bundleID)
            if checkbox.state == .on && count > 0 {
                viewModel.purgeItems(matchingBundleID: bundleID)
            }
        }
    }

    private func applyTheme(_ theme: AppTheme) {
        NSApp.appearance = theme.nsAppearance
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    let applyTheme: (AppTheme) -> Void
    @State private var showingRestoreConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Pasting") {
                SettingsRow(title: "Paste on selection", caption: "Paste the clip into the app that you used before.") {
                    SettingsSwitch(label: "Paste on selection", isOn: $settings.pasteOnClick)
                        .settingsFocus("pasteOnClick", toggle: $settings.pasteOnClick)
                }
                AccessibilityRow()
                SettingsRow(title: "Move clip to top on selection") {
                    SettingsSwitch(label: "Move clip to top on selection", isOn: $settings.moveTopOnClick)
                        .settingsFocus("moveTopOnClick", toggle: $settings.moveTopOnClick)
                }
            }

            SettingsSection(title: "Clip window") {
                SettingsRow(title: "Close when idle", caption: "Close the window when you do not type, click or scroll in it.") {
                    SettingsSwitch(label: "Close when idle", isOn: $settings.autoDismissOverlayEnabled)
                        .settingsFocus("closeWhenIdle", toggle: $settings.autoDismissOverlayEnabled)
                }
                SettingsRow(title: "Close after") {
                    Picker("Close after", selection: $settings.autoDismissOverlayTimeout) {
                        Text("5 seconds").tag(TimeInterval(5))
                        Text("10 seconds").tag(TimeInterval(10))
                        Text("20 seconds").tag(TimeInterval(20))
                        Text("30 seconds").tag(TimeInterval(30))
                        Text("1 minute").tag(TimeInterval(60))
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!settings.autoDismissOverlayEnabled)
                    .settingsFocus("closeAfter", enabled: settings.autoDismissOverlayEnabled,
                                   choice: $settings.autoDismissOverlayTimeout, values: [5, 10, 20, 30, 60])
                }
            }

            SettingsSection(title: "Reset") {
                SettingsRow(title: "Restore default settings",
                            caption: "Sets every setting back to its default. Your clips, the clip limit and encryption do not change.") {
                    Button("Restore Defaults\u{2026}") { showingRestoreConfirm = true }
                        .settingsFocus("restoreDefaults") { showingRestoreConfirm = true }
                }
            }
        }
        .alert("Restore default settings?", isPresented: $showingRestoreConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Restore") { restoreDefaults() }
        } message: {
            Text("MaClip sets the theme, the accent color, pasting, the clip window, the shortcuts, the list of apps and concealed clips back to their defaults. Your clips, the clip limit and encryption do not change.")
        }
    }

    private func restoreDefaults() {
        settings.restoreDefaultSettings()
        applyTheme(settings.theme)
        NotificationCenter.default.post(name: .themeChanged, object: nil)
        HotKeyService.shared.unregister()
        HotKeyService.shared.register(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
    }
}

private struct AccessibilityRow: View {
    @ObservedObject private var access = AccessibilityAccess.shared
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Accessibility access")
                    StatusBadge(isOn: access.isGranted)
                }
                Text(access.isGranted ? "MaClip can paste for you."
                                      : "MaClip copies the clip, and you press \u{2318}V.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 12)
            if !access.isGranted {
                Button("Allow\u{2026}") {
                    AccessibilityPromptWindowController.shared.show(afterCopy: false)
                }
                .settingsFocus("allowAccessibility") {
                    AccessibilityPromptWindowController.shared.show(afterCopy: false)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
        .onAppear { access.refresh() }
        .onReceive(poll) { _ in access.refresh() }
    }
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    @ObservedObject var settings: AppSettings
    @Binding var isCapturingHotkey: Bool
    @Binding var extractCapture: ExtractKind?
    let hotKeyDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Clip window") {
                SettingsRow(title: "Open MaClip") {
                    ShortcutField(shortcut: hotKeyDescription, isRecording: isCapturingHotkey) {
                        extractCapture = nil
                        isCapturingHotkey = true
                    }
                    .settingsFocus("openShortcut") {
                        extractCapture = nil
                        isCapturingHotkey = true
                    }
                }
            }

            SettingsSection(title: "Paste from the last image",
                            footer: "Take a screenshot with \u{2303}\u{21E7}\u{2318}4, then press a shortcut in any app. MaClip reads the newest image clip and pastes the result. \u{2318}V still pastes the image.") {
                extractRow("Paste text", kind: .text, enabled: $settings.extractTextHotkeyEnabled,
                           keyCode: settings.extractTextKeyCode, modifiers: settings.extractTextModifiers)
                extractRow("Paste QR code or barcode", kind: .code, enabled: $settings.extractCodeHotkeyEnabled,
                           keyCode: settings.extractCodeKeyCode, modifiers: settings.extractCodeModifiers)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("In the clip window")
                    .font(.system(size: 13, weight: .semibold))
                ShortcutColumnsView(columns: ClipKeyMap.listColumns(globalKeys: []))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.hoverFill))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line, lineWidth: 1))
                Text("Press \u{2318}/ in any MaClip window to see its keys. In Settings, \u{21E5} moves between the controls, and space turns a switch on or off.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The list of keys is the last focus stop of the tab, so ↓ and ⇥ scroll to it.
            // It has no action.
            .settingsFocus("clipWindowKeys") { _ in }
        }
    }

    private func extractRow(_ title: String, kind: ExtractKind, enabled: Binding<Bool>,
                            keyCode: UInt32, modifiers: UInt32) -> some View {
        HStack(spacing: 12) {
            SettingsSwitch(label: title, isOn: enabled)
                .settingsFocus("\(kind)Enabled", toggle: enabled)
            Text(title)
                .foregroundColor(enabled.wrappedValue ? .primary : .secondary)
            Spacer(minLength: 12)
            ShortcutField(shortcut: HotkeyUtils.description(keyCode: keyCode, modifiers: modifiers),
                          isRecording: extractCapture == kind,
                          isEnabled: enabled.wrappedValue) {
                isCapturingHotkey = false
                extractCapture = kind
            }
            .settingsFocus("\(kind)Shortcut", enabled: enabled.wrappedValue) {
                isCapturingHotkey = false
                extractCapture = kind
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
    }
}

// MARK: - Storage

private struct StorageTab: View {
    @ObservedObject private var accentStore = AccentStore.shared
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: ClipboardListViewModel
    @ObservedObject private var focus = SettingsFocusState.shared
    @FocusState private var isNumberFocused: Bool
    /// The number in the field. It takes effect only on Apply or ↩.
    @State private var draftMaxItems: Int?
    @State private var failure: String?
    @State private var isShowingClearConfirm = false

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        return formatter
    }()

    private var draft: Int { draftMaxItems ?? settings.maxItems }

    private var draftBinding: Binding<Int> {
        Binding(get: { draft }, set: { draftMaxItems = $0 })
    }

    private var canApply: Bool { MaxItemsDraft.canApply(draft: draft, saved: settings.maxItems) }

    /// Without a change, the caption says what the limit does. With a change, it says what Apply does.
    private var maxItemsNote: (text: String, isWarning: Bool) {
        guard let note = MaxItemsDraft.note(draft: draft, saved: settings.maxItems, count: viewModel.items.count) else {
            return ("MaClip deletes the oldest clip when the list is full.", false)
        }
        return (note.text, note.isWarning)
    }

    private func applyMaxItems() {
        guard canApply else { return }
        viewModel.setMaxItems(draft)
        draftMaxItems = nil
    }

    private var encryption: Binding<Bool> {
        Binding(
            get: { settings.encryptHistory },
            set: { enabled in
                if !viewModel.setHistoryEncryption(enabled) {
                    failure = enabled
                        ? "MaClip could not read or create the encryption key. Your history did not change."
                        : "MaClip could not read the encryption key. Your history stays encrypted."
                }
            }
        )
    }

    private func restoreEarlierClips() {
        if viewModel.restoreEncryptedHistory() {
            settings.encryptedHistoryNoticeDismissed = true
        } else {
            failure = "MaClip could not read the encryption key. Your earlier clips are still on disk. Try again, and click Allow when macOS asks."
        }
    }

    /// 0 means Never.
    private var cleanDays: Binding<Int> {
        Binding(
            get: { settings.autoCleanEnabled ? settings.autoCleanDays : 0 },
            set: { days in
                settings.autoCleanEnabled = days > 0
                if days > 0 { settings.autoCleanDays = days }
                viewModel.applyAutoClean()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "History") {
                SettingsRow(title: "Keep up to", caption: maxItemsNote.text, captionIsWarning: maxItemsNote.isWarning) {
                    HStack(spacing: 6) {
                        TextField("Clips", value: draftBinding, formatter: Self.numberFormatter, onCommit: applyMaxItems)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Theme.accent, lineWidth: draft != settings.maxItems ? 1.5 : 0)
                            )
                            .focused($isNumberFocused)
                            // ⇥ to the field puts the cursor in it. ⇥ again takes it out.
                            .settingsFocus("maxItems") { action in
                                if action == .activate { isNumberFocused = true }
                            }
                            .onChange(of: focus.focused) { id in isNumberFocused = id == "maxItems" }
                        Text("clips").foregroundColor(.secondary)
                        Button("Apply", action: applyMaxItems)
                            .buttonStyle(AccentButtonStyle())
                            .opacity(canApply ? 1 : 0.4)
                            .disabled(!canApply)
                            .padding(.leading, 4)
                            .help("Keep up to \(draft) clips (\u{21A9})")
                            .settingsFocus("applyMaxItems", enabled: canApply, press: applyMaxItems)
                    }
                }
                SettingsRow(title: "Delete clips older than") {
                    Picker("Delete clips older than", selection: cleanDays) {
                        Text("Never").tag(0)
                        Text("1 day").tag(1)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .settingsFocus("deleteOlderThan", choice: cleanDays, values: [0, 1, 7, 30])
                }
            }

            SettingsSection(title: "Encryption") {
                SettingsRow(title: "Encrypt history on disk",
                            caption: "MaClip keeps the key in your login Keychain. macOS can ask for your password after each MaClip update.") {
                    SettingsSwitch(label: "Encrypt history on disk", isOn: encryption)
                        .settingsFocus("encryptHistory", toggle: encryption)
                }
                if viewModel.hasEncryptedHistoryToRestore {
                    SettingsRow(title: "Earlier encrypted clips",
                                caption: "From MaClip 1.9 to 1.11. macOS asks for your password one time.") {
                        Button("Restore\u{2026}", action: restoreEarlierClips)
                            .settingsFocus("restoreEarlierClips", press: restoreEarlierClips)
                    }
                }
            }

            SettingsSection(title: "Clear") {
                SettingsRow(title: "Clear history",
                            caption: "Deletes all \(viewModel.items.count) clips and their images. You cannot undo this.") {
                    Button("Clear History\u{2026}") { isShowingClearConfirm = true }
                        .foregroundColor(.red)
                        .disabled(viewModel.items.isEmpty)
                        .settingsFocus("clearHistory", enabled: !viewModel.items.isEmpty) { isShowingClearConfirm = true }
                }
            }
        }
        .alert("Could not change encryption", isPresented: Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
        .alert("Clear all history?", isPresented: $isShowingClearConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) { viewModel.clearHistory() }
        } message: {
            Text("This deletes all clips and their images. You cannot undo this.")
        }
    }
}

// MARK: - Privacy

private struct PrivacyTab: View {
    @ObservedObject private var accentStore = AccentStore.shared
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: ClipboardListViewModel
    let addApplicationViaPicker: () -> Void
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Don\u{2019}t save clips from these apps")
                    .font(.system(size: 13, weight: .semibold))
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                                appRow(bundleID)
                            }
                            if settings.excludedBundleIDs.isEmpty {
                                Text("No apps. Click + to add one.")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }
                        }
                        .padding(4)
                    }
                    .frame(height: 190)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    HStack(spacing: 0) {
                        Button(action: addApplicationViaPicker) {
                            Image(systemName: "plus").frame(width: 28, height: 24).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .settingsFocus("addApp", press: addApplicationViaPicker)
                        .help("Add an app")
                        .accessibilityLabel("Add an app")
                        Rectangle().fill(Theme.line).frame(width: 1, height: 16)
                        Button(action: removeSelected) {
                            Image(systemName: "minus").frame(width: 28, height: 24).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(selection == nil)
                        .settingsFocus("removeApp", enabled: selection != nil, press: removeSelected)
                        .help("Remove the selected app")
                        .accessibilityLabel("Remove the selected app")
                        Spacer()
                        Text("\(settings.excludedBundleIDs.count) apps")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.trailing, 10)
                    }
                    .padding(.horizontal, 4)
                    .frame(height: 30)
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.hoverFill))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line, lineWidth: 1))
            }

            SettingsSection(title: "MaClip") {
                HStack(spacing: 12) {
                    AppIconView().frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save clips that you copy in MaClip")
                        Text(settings.saveMaClipClips
                             ? "Text that you copy in the clip editor, and screenshots that you take while MaClip is open, become clips."
                             : "Off: text that you copy in the clip editor, and screenshots that you take while MaClip is open, are not saved.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    SettingsSwitch(label: "Save clips that you copy in MaClip", isOn: $settings.saveMaClipClips)
                        .settingsFocus("saveMaClipClips", toggle: $settings.saveMaClipClips)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 44)
            }

            SettingsSection(title: "Concealed clips") {
                SettingsRow(title: "Don\u{2019}t save concealed clips",
                            caption: "Password managers mark passwords as concealed when you copy them.") {
                    SettingsSwitch(label: "Don\u{2019}t save concealed clips", isOn: $settings.skipConcealedItems)
                        .settingsFocus("skipConcealed", toggle: $settings.skipConcealedItems)
                }
                SettingsRow(title: "Delete concealed clips after") {
                    Picker("Delete concealed clips after", selection: $settings.concealedClearTimeout) {
                        Text("5 seconds").tag(TimeInterval(5))
                        Text("10 seconds").tag(TimeInterval(10))
                        Text("20 seconds").tag(TimeInterval(20))
                        Text("30 seconds").tag(TimeInterval(30))
                        Text("1 minute").tag(TimeInterval(60))
                        Text("2 minutes").tag(TimeInterval(120))
                        Text("5 minutes").tag(TimeInterval(300))
                        Text("10 minutes").tag(TimeInterval(600))
                        Text("15 minutes").tag(TimeInterval(900))
                        Text("30 minutes").tag(TimeInterval(1800))
                        Text("Never").tag(TimeInterval(-1))
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(settings.skipConcealedItems)
                    .settingsFocus("concealedTimeout", enabled: !settings.skipConcealedItems,
                                   choice: $settings.concealedClearTimeout,
                                   values: [5, 10, 20, 30, 60, 120, 300, 600, 900, 1800, -1])
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsRemoveSelectedApp)) { _ in removeSelected() }
    }

    private func appRow(_ bundleID: String) -> some View {
        let isSelected = selection == bundleID
        return HStack(spacing: 10) {
            if let icon = AppMetadata.shared.icon(for: bundleID) {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            let installedName = AppMetadata.shared.displayName(for: bundleID)
            Text(installedName ?? Self.knownNames[bundleID] ?? bundleID)
            if installedName == nil {
                Text("\u{00B7} not installed").font(.system(size: 11)).foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            Spacer()
            if installedName != nil || Self.knownNames[bundleID] != nil {
                Text(bundleID)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }
        }
        .foregroundColor(isSelected ? .white : .primary)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isSelected ? Theme.accent : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { selection = isSelected ? nil : bundleID }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // Each app takes the focus in turn. ⌫ removes the focused app, and space selects it.
        .settingsFocus("app:\(bundleID)") { action in
            switch action {
            case .remove:
                settings.excludedBundleIDs.removeAll { $0 == bundleID }
                if selection == bundleID { selection = nil }
            case .activate:
                selection = isSelected ? nil : bundleID
            case .step:
                break
            }
        }
    }

    /// Names of the default password managers, for when the app is not installed.
    private static let knownNames: [String: String] = [
        "com.agilebits.onepassword7": "1Password 7",
        "com.1password.1password": "1Password",
        "com.bitwarden.desktop": "Bitwarden",
        "com.apple.keychainaccess": "Keychain Access",
        "com.dashlane.dashlanephonefinal": "Dashlane",
        "com.lastpass.LastPassMacDesktop": "LastPass",
    ]

    private func removeSelected() {
        guard let selection else { return }
        settings.excludedBundleIDs.removeAll { $0 == selection }
        self.selection = nil
    }
}

// MARK: - Window

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()
    /// Tall enough for the whole preview of the Appearance tab. On a smaller screen the window
    /// is shorter, with room for the title bar and a margin, and the tab scrolls.
    static var contentSize: CGSize {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return CGSize(width: 680, height: min(720, screen - 68))
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.level = .floating  // Ensure it appears above the overlay window
        // Do not resolve the shared viewModel here to avoid startup ordering issues
        window.contentViewController = NSHostingController(rootView: EmptyView())

        super.init(window: window)
        window.delegate = self
        window.initialFirstResponder = window.contentView

        // The keys of Settings, from `SettingsKeyMap`, while Settings is the key window.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow,
                  let combo = KeyCombo(event: event) else { return event }
            // While a shortcut field records new keys, every key goes to it.
            if let recorder = window.firstResponder as? HotkeyView, recorder.isCapturing { return event }
            let panel = ShortcutsPanelState.shared
            if panel.isVisible(.settings) {
                if combo == KeyCombo(.escape) || combo == .command("/") { panel.hide(.settings) }
                return nil
            }
            // The number field takes the typing keys. Esc takes the cursor out of it.
            if (window.firstResponder as? NSTextView)?.isFieldEditor == true {
                if combo == KeyCombo(.escape) {
                    window.makeFirstResponder(nil)
                    return nil
                }
                guard SettingsKeyMap.worksInTextField(combo) else { return event }
            }
            switch SettingsKeyMap.table.command(for: combo) {
            case .close:
                window.close()
            case .showShortcuts:
                panel.toggle(.settings)
            case .some(let command):
                NotificationCenter.default.post(name: .settingsCommand, object: command)
            case nil:
                return event
            }
            return nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        ShortcutsPanelState.shared.hide(.settings)
        SettingsFocusState.shared.focused = nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        // Always resolve the shared viewModel from AppDelegate
        if let shared = AppDelegate.shared {
            window?.contentViewController = NSHostingController(rootView: SettingsView(viewModel: shared.viewModel))
        } else if let appDelegate = NSApp.delegate as? AppDelegate {
            window?.contentViewController = NSHostingController(rootView: SettingsView(viewModel: appDelegate.viewModel))
            // Also set shared for future calls
            AppDelegate.shared = appDelegate
        } else {
            assertionFailure("AppDelegate not available - Settings should only be shown after app launch")
            // As a last resort, keep the window empty to avoid using a wrong instance
            window?.contentViewController = NSHostingController(rootView: Text("Unable to load settings"))
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: ClipboardListViewModel())
    }
}
