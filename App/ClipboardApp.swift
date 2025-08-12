import SwiftUI
import AppKit

@main
struct MacClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Override the settings command to prevent automatic window creation
        Settings {
            // This will be handled by our custom command below
            EmptyView()
        }
        .handlesExternalEvents(matching: Set<String>())
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    let controller = SettingsWindowController.shared
                    if let win = controller.window, win.isVisible, win.isKeyWindow {
                        win.close()
                    } else {
                        controller.show()
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor private let viewModel = ClipboardListViewModel()
    private var overlay: OverlayWindowController!
    private var statusItem: NSStatusItem?
    private let settings = AppSettings.shared

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent automatic window creation
        NSApp.setActivationPolicy(.prohibited)
        
        overlay = OverlayWindowController(viewModel: viewModel)

        HotKeyService.shared.onPressed = { [weak self] in
            Task { @MainActor in
                self?.overlay.toggle()
            }
        }
        HotKeyService.shared.register(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)

        setupStatusItem()
        
        // Allow app to be activated when needed
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyService.shared.unregister()
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

    @MainActor
    @objc private func statusItemClicked() {
        overlay.toggle()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @MainActor
    @objc private func openSettingsFromStatusItem() {
        SettingsWindowController.shared.show()
    }
}

