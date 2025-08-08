import SwiftUI
import AppKit

@main
struct MacClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No main window; shown via global hotkey instead
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ClipboardStore()
    private var overlay: OverlayWindowController!
    private var statusItem: NSStatusItem?
    private let settings = AppSettings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayWindowController(store: store)

        GlobalHotKeyManager.shared.onPressed = { [weak self] in
            self?.overlay.toggle()
        }
        GlobalHotKeyManager.shared.registerCommandControlV()

        setupStatusItem()

        // Apply initial hotkey from settings
        GlobalHotKeyManager.shared.unregister()
        GlobalHotKeyManager.shared.register(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKeyManager.shared.unregister()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "📋"
            }
            button.target = self
            button.action = #selector(statusItemClicked)
            button.toolTip = "Show Clipboard (Ctrl+Cmd+V)"
        }

        // Status bar menu with Quit option
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Clipboard", action: #selector(statusItemClicked), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettingsFromStatusItem), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit MaClip", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
    }

    @objc private func statusItemClicked() {
        overlay.toggle()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func openSettingsFromStatusItem() {
        SettingsWindow.show(with: store)
        NSApp.activate(ignoringOtherApps: true)
    }
}

