import AppKit
import SwiftUI

/// Hosts `ImageEditorSheet` in its own window, separate from the overlay.
@MainActor
final class ImageEditorWindowController: NSObject, NSWindowDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("ImageEditorWindow")

    private var window: NSWindow?
    private var onClose: (() -> Void)?

    var isOpen: Bool { window != nil }

    /// Opens the editor for `item`. If an editor is already open, brings it to
    /// the front instead, so unsaved edits are never replaced.
    func show(item: ClipboardItem, image: NSImage,
              viewModel: ClipboardListViewModel,
              onClose: @escaping () -> Void) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let editor = ImageEditorSheet(
            item: item,
            baseImage: image,
            onCommit: { [weak self] pngData, mode in
                let saved: Bool
                switch mode {
                case .inPlace: saved = viewModel.saveEditedImage(replacing: item, pngData: pngData)
                case .asNew:   saved = viewModel.insertImage(pngData: pngData, from: item)
                }
                if saved { self?.window?.close() }
                return saved
            },
            onCancel: { [weak self] in self?.window?.close() }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1020, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = Self.windowIdentifier
        window.title = "Edit Image"
        window.isReleasedWhenClosed = false
        // Like Settings: MaClip has no Dock icon, so a window behind other apps is hard to find.
        window.level = .floating
        window.contentViewController = NSHostingController(rootView: editor)
        window.contentMinSize = NSSize(width: 940, height: 600)
        window.setContentSize(NSSize(width: 1020, height: 720))
        window.center()
        window.setFrameAutosaveName("ImageEditorWindow")
        window.delegate = self
        applyTheme(to: window)

        self.window = window
        self.onClose = onClose
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // Covers Save, Save as new, Cancel/Esc and the red close button.
    func windowWillClose(_ notification: Notification) {
        let callback = onClose
        window?.delegate = nil
        window = nil
        onClose = nil
        callback?()
    }

    private func applyTheme(to window: NSWindow) {
        switch AppSettings.shared.theme {
        case .system: window.appearance = nil
        case .light:  window.appearance = NSAppearance(named: .aqua)
        case .dark:   window.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
