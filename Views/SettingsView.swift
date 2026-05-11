import SwiftUI
import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject var viewModel: ClipboardListViewModel
    @State private var isCapturingHotkey = false
    @State private var newHotkeyModifiers: UInt32 = 0
    @State private var newHotkeyKeyCode: UInt32 = 0
    @State private var isShowingClearConfirm: Bool = false
    @State private var cleanOlderThanDays: String = "7"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Hotkey Configuration
            GroupBox("Hotkey") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current: \(hotKeyDescription)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button(isCapturingHotkey ? "Press new hotkey..." : "Change Hotkey") {
                        startCapturingHotkey()
                    }
                    .foregroundColor(isCapturingHotkey ? .orange : .blue)
                    
                    Text("Press the hotkey to show the clipboard overlay.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Display Settings
            GroupBox("Display") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Theme", selection: $settings.theme) {
                        Text("System").tag(AppTheme.system)
                        Text("Light").tag(AppTheme.light)
                        Text("Dark").tag(AppTheme.dark)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: settings.theme) { newTheme in
                        applyTheme(newTheme)
                        NotificationCenter.default.post(name: .themeChanged, object: nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Storage Settings
            GroupBox("Storage") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Maximum Items:")
                        Spacer()
                        TextField("", value: $settings.maxItems, formatter: NumberFormatter())
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                            .onChange(of: settings.maxItems) { newValue in
                                viewModel.applyMaxItems(newValue)
                            }
                    }
                    
                    Toggle("Auto-clean old items", isOn: $settings.autoCleanEnabled)
                    
                    HStack {
                        Text("Clean items older than:")
                        Spacer()
                        TextField("7", text: $cleanOlderThanDays)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 60)
                        Text("days")
                    }
                    .padding(.leading)
                    .disabled(!settings.autoCleanEnabled)
                    .opacity(settings.autoCleanEnabled ? 1.0 : 0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Privacy Settings
            GroupBox("Privacy") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Excluded Apps")
                        .font(.subheadline.bold())
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                                HStack(spacing: 8) {
                                    if let icon = AppMetadata.shared.icon(for: bundleID) {
                                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                                    } else {
                                        Image(systemName: "questionmark.app.dashed").frame(width: 18, height: 18)
                                    }
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(AppMetadata.shared.displayName(for: bundleID) ?? bundleID)
                                            .font(.body)
                                        Text(bundleID).font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button(action: {
                                        settings.excludedBundleIDs.removeAll { $0 == bundleID }
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 2)
                            }
                            if settings.excludedBundleIDs.isEmpty {
                                Text("No apps excluded.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                    Button("+ Add Application…") {
                        addApplicationViaPicker()
                    }
                    Text("Clips copied from these apps will never be saved to your history.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider().padding(.vertical, 4)

                    Toggle("Skip concealed clipboard items", isOn: $settings.skipConcealedItems)
                    HStack {
                        Text("Auto-clear concealed items after")
                        Spacer()
                        Picker("", selection: $settings.concealedClearTimeout) {
                            Text("30 sec").tag(TimeInterval(30))
                            Text("1 min").tag(TimeInterval(60))
                            Text("2 min").tag(TimeInterval(120))
                            Text("5 min").tag(TimeInterval(300))
                            Text("10 min").tag(TimeInterval(600))
                            Text("15 min").tag(TimeInterval(900))
                            Text("30 min").tag(TimeInterval(1800))
                        }
                        .pickerStyle(.menu)
                        .frame(width: 110)
                        .disabled(settings.skipConcealedItems)
                    }
                    Text("Items marked secret by apps like 1Password are kept with redacted preview, then removed automatically. Turn the toggle on to skip them entirely.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Behavior Settings
            GroupBox("Behavior") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Paste on selection", isOn: $settings.pasteOnClick)
                    Text("Automatically paste to the previous app when selecting an item.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 24)

                    Toggle("Move item to top on selection", isOn: $settings.moveTopOnClick)
                    Text("When selecting an item, move it to the top of the history list.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
            
            // Action Buttons
            HStack {
                Button("Clear All History") {
                    isShowingClearConfirm = true
                }
                .foregroundColor(.red)
                
                Spacer()
                
                Button("About MaClip") {
                    InfoWindow.show()
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundColor(.secondary)
                
                Button("Close") {
                    NSApp.keyWindow?.close()
                }
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(HotkeyCapturingView(isCapturing: $isCapturingHotkey) { keyCode, modifiers in
            updateHotkey(keyCode: keyCode, modifiers: modifiers)
        })
        .alert("Clear all history?", isPresented: $isShowingClearConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) { viewModel.clearHistory() }
        } message: {
            Text("This will remove all clipboard items from the list.")
        }
    }
    
    private var hotKeyDescription: String {
        HotkeyUtils.description(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
    }
    
    private func startCapturingHotkey() {
        isCapturingHotkey = true
    }
    
    private func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        // Unregister old hotkey
        HotKeyService.shared.unregister()
        
        // Update settings
        settings.hotkeyKeyCode = keyCode
        settings.hotkeyModifiers = modifiers
        
        // Register new hotkey
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
        switch theme {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system:
            NSApp.appearance = nil
        }
    }
}

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
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
        
        // Local monitor: catch Command+, while Settings is key and close
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.isKeyWindow == true else { return event }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," {
                self.window?.close()
                return nil
            }
            return event
        }
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