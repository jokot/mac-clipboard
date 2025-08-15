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
            CommandGroup(after: .appSettings) {
                Button("About MaClip") {
                    // Toggle behavior similar to Settings
                    // Reuse singleton-like enum to show; if visible and key, close
                    InfoWindowToggleHelper.toggle()
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Provide a stable shared reference to the AppDelegate for accessing the shared view model
    static var shared: AppDelegate?

    @MainActor let viewModel = ClipboardListViewModel()
    private var overlay: OverlayWindowController!
    private var statusItem: NSStatusItem?
    private let settings = AppSettings.shared

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Assign shared reference
        AppDelegate.shared = self

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
        // Clear shared on terminate
        AppDelegate.shared = nil
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
        menu.addItem(NSMenuItem(title: "About", action: #selector(openInfoFromStatusItem), keyEquivalent: "i"))
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

    @MainActor
    @objc private func openInfoFromStatusItem() {
        InfoWindow.show()
    }
}

// Helper to toggle Info window similar to Settings command
@MainActor
enum InfoWindowToggleHelper {
    static func toggle() {
        // Access the existing controller used by InfoWindow
        // Since InfoWindow wraps a controller internally, show() will create if needed and bring to front.
        // For toggle behavior, try to detect and close if already key.
        if let win = InfoWindowControllerAccessor.sharedCurrentWindow(), win.isVisible, win.isKeyWindow {
            win.close()
        } else {
            InfoWindow.show()
        }
    }
}

// Internal accessor to reach the Info window's NSWindow instance
@MainActor
enum InfoWindowControllerAccessor {
    static func sharedCurrentWindow() -> NSWindow? {
        // There isn't a public accessor; try to find window by title as a safe fallback.
        return NSApp.windows.first(where: { $0.title == "About MaClip" })
    }
}

