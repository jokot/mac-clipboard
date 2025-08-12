import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var viewModel = ClipboardListViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom)
            
            // Hotkey Configuration
            GroupBox("Hotkey") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current: \(hotKeyDescription)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Change Hotkey") {
                        // Not implemented in this MVVM refactor step
                    }
                    .disabled(true)
                    
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
                    
                    if settings.autoCleanEnabled {
                        HStack {
                            Text("Clean items older than:")
                            Spacer()
                            TextField("7", text: .constant("7"))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 60)
                            Text("days")
                        }
                        .padding(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
            
            // Action Buttons
            HStack {
                Button("Clear All History") {
                    viewModel.clearHistory()
                }
                .foregroundColor(.red)
                
                Spacer()
                
                Button("Close") {
                    NSApp.keyWindow?.close()
                }
            }
        }
        .padding(24)
        .frame(width: 480, height: 400)
    }
    
    private var hotKeyDescription: String {
        var components: [String] = []
        
        if settings.hotkeyModifiers.containsCmd { components.append("⌘") }
        if settings.hotkeyModifiers.containsCtrl { components.append("⌃") }
        if settings.hotkeyModifiers.containsAlt { components.append("⌥") }
        if settings.hotkeyModifiers.containsShift { components.append("⇧") }
        
        // Best-effort letter from keyCode (only supports A-Z here)
        let letterMap: [UInt32: String] = [
            0x00:"A",0x0B:"B",0x08:"C",0x02:"D",0x0E:"E",0x03:"F",0x05:"G",0x04:"H",0x22:"I",0x26:"J",
            0x28:"K",0x25:"L",0x2E:"M",0x2D:"N",0x1F:"O",0x23:"P",0x0C:"Q",0x0F:"R",0x01:"S",0x11:"T",
            0x20:"U",0x09:"V",0x0D:"W",0x07:"X",0x10:"Y",0x06:"Z"
        ]
        let key = letterMap[settings.hotkeyKeyCode] ?? "V"
        components.append(key)
        
        return components.joined()
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

class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}