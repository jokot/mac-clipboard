import Cocoa
import SwiftUI

final class OverlayWindowController: NSObject {
    private var window: NSWindow?
    private let store: ClipboardStore
    private let onCloseRequested: (() -> Void)?
    private var escMonitor: Any?
    private var backgroundView: NSVisualEffectView?

    init(store: ClipboardStore, onCloseRequested: (() -> Void)? = nil) {
        self.store = store
        self.onCloseRequested = onCloseRequested
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(closeRequested), name: .overlayCloseRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsRequested), name: .overlayOpenSettings, object: nil)
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
        NotificationCenter.default.post(name: .overlayDidShow, object: nil)

        if escMonitor == nil {
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                if event.keyCode == 53 { // Escape key
                    self?.hide()
                    return nil
                }
                return event
            }
        }

        applyTheme()
    }

    func hide() {
        window?.orderOut(nil)
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        onCloseRequested?()
    }

    private func createWindow() {
        let content = ContentView(onSelect: { [weak self] item in
            self?.store.setPasteboard(to: item)
            self?.store.promote(item)
            self?.hide()
        }, onOpenSettings: { [weak self] in
            self?.openSettings()
        }, onOpenInfo: { [weak self] in
            self?.openInfo()
        })
        .environmentObject(store)
        .background(ESCKeyCatcher())

        let hosting = FirstMouseHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Clipboard"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear

        let vev = NSVisualEffectView()
        vev.material = .contentBackground
        vev.state = .active
        vev.blendingMode = .withinWindow
        vev.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = vev

        hosting.translatesAutoresizingMaskIntoConstraints = false
        vev.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: vev.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: vev.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: vev.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: vev.bottomAnchor)
        ])
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        self.window = window
        self.backgroundView = vev
        applyTheme()
    }

    private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    @objc private func closeRequested() {
        hide()
    }

    @objc private func openSettingsRequested() {
        openSettings()
    }

    private func openSettings() {
        SettingsWindow.show(with: store)
        // Apply theme to overlay content window when opened
        applyTheme()

        // Ensure settings appears above overlay
        window?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openInfo() {
        InfoWindow.show()
        NSApp.activate(ignoringOtherApps: true)
    }
}
extension Notification.Name {
    static let themeChanged = Notification.Name("ThemeChanged")
}

private extension OverlayWindowController {
    func applyTheme() {
        guard let window else { return }
        switch AppSettings.shared.theme {
        case .system:
            window.appearance = nil
            backgroundView?.appearance = nil
        case .light:
            let a = NSAppearance(named: .aqua)
            window.appearance = a
            backgroundView?.appearance = a
        case .dark:
            let a = NSAppearance(named: .darkAqua)
            window.appearance = a
            backgroundView?.appearance = a
        }
        window.invalidateShadow()
    }
}

extension Notification.Name {
    static let overlayCloseRequested = Notification.Name("OverlayCloseRequested")
    static let overlayMoveSelectionUp = Notification.Name("OverlayMoveSelectionUp")
    static let overlayMoveSelectionDown = Notification.Name("OverlayMoveSelectionDown")
    static let overlaySelectCurrentItem = Notification.Name("OverlaySelectCurrentItem")
    static let overlayDidShow = Notification.Name("OverlayDidShow")
    static let overlayOpenSettings = Notification.Name("OverlayOpenSettings")
}

private struct ESCKeyCatcher: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        view.onEscape = {
            NotificationCenter.default.post(name: .overlayCloseRequested, object: nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class KeyCatcherView: NSView {
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            onEscape?()
        case 126: // Arrow Up
            NotificationCenter.default.post(name: .overlayMoveSelectionUp, object: nil)
        case 125: // Arrow Down
            NotificationCenter.default.post(name: .overlayMoveSelectionDown, object: nil)
        case 36, 76: // Return or Keypad Enter
            NotificationCenter.default.post(name: .overlaySelectCurrentItem, object: nil)
        default:
            if event.modifierFlags.contains(.command), let chars = event.charactersIgnoringModifiers, chars == "," {
                NotificationCenter.default.post(name: .overlayOpenSettings, object: nil)
                return
            }
            super.keyDown(with: event)
        }
    }
}

