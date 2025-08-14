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
        .frame(width: 480, height: 400)
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

// MARK: - Hotkey Capturing View
struct HotkeyCapturingView: NSViewRepresentable {
    @Binding var isCapturing: Bool
    let onCaptured: (UInt32, UInt32) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = HotkeyView()
        view.onHotkeyCaptured = onCaptured
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let hotkeyView = nsView as? HotkeyView {
            hotkeyView.isCapturing = isCapturing
        }
    }
}

class HotkeyView: NSView {
    var isCapturing = false {
        didSet {
            if isCapturing {
                window?.makeFirstResponder(self)
            }
        }
    }
    
    var onHotkeyCaptured: ((UInt32, UInt32) -> Void)?
    
    override var acceptsFirstResponder: Bool { isCapturing }
    
    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }
        
        // Don't capture single modifier keys or escape
        if event.keyCode == 53 { // Escape
            isCapturing = false
            return
        }
        
        let modifiers = event.modifierFlags
        var carbonModifiers: UInt32 = 0
        
        if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        
        // Require at least one modifier
        guard carbonModifiers != 0 else {
            NSSound.beep()
            return
        }
        
        onHotkeyCaptured?(UInt32(event.keyCode), carbonModifiers)
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