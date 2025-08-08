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

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayWindowController(store: store)

        GlobalHotKeyManager.shared.onPressed = { [weak self] in
            self?.overlay.toggle()
        }
        GlobalHotKeyManager.shared.registerCommandControlV()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKeyManager.shared.unregister()
    }
}

