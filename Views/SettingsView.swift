import SwiftUI
import AppKit
import Carbon.HIToolbox

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
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
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