import Cocoa
import SwiftUI

final class OverlayWindowController: NSObject {
    private var window: NSWindow?
    private let store: ClipboardStore
    private let onCloseRequested: (() -> Void)?

    init(store: ClipboardStore, onCloseRequested: (() -> Void)? = nil) {
        self.store = store
        self.onCloseRequested = onCloseRequested
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(closeRequested), name: .overlayCloseRequested, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    var isVisible: Bool {
        return window?.isVisible == true
    }

    func show() {
        if window == nil {
            createWindow()
        }
        guard let window else { return }
        if let screen = NSScreen.main {
            let size = CGSize(width: 520, height: 600)
            let origin = CGPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
        onCloseRequested?()
    }

    private func createWindow() {
        let content = ContentView { [weak self] item in
            self?.store.setPasteboard(to: item)
            self?.store.promote(item)
            self?.hide()
        }
        .environmentObject(store)

        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Clipboard"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.98)
        window.contentView = hosting
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        self.window = window
    }

    @objc private func closeRequested() {
        hide()
    }
}

extension Notification.Name {
    static let overlayCloseRequested = Notification.Name("OverlayCloseRequested")
}

