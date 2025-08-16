import Cocoa
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class OverlayWindowController: NSObject {
    private var window: NSWindow?
    private let viewModel: ClipboardListViewModel
    private let onCloseRequested: (() -> Void)?
    private var escMonitor: Any?
    private var backgroundView: NSVisualEffectView?
    
    // Track the previously active app to restore focus and paste into it
    private var previousActiveApp: NSRunningApplication?
    internal var autoPastePending: Bool = false  // Make this internal so KeyCatcherView can access

    init(viewModel: ClipboardListViewModel, onCloseRequested: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onCloseRequested = onCloseRequested
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(closeRequested), name: .overlayCloseRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsRequested), name: .overlayOpenSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeChanged, object: nil)
     }

     deinit {
         NotificationCenter.default.removeObserver(self)
     }

    @objc private func themeChanged() {
        applyTheme()
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
        // Capture the app that was frontmost before we activate our window
        previousActiveApp = NSWorkspace.shared.frontmostApplication
        
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
                    guard let self = self else { return nil }
                    // Hide immediately and only refocus the previous app (no paste)
                    self.hideImmediatelyRefocusOnly()
                    return nil
                }
                return event
            }
        }

        applyTheme()
        // Ensure overlay window stays key when toggled via hotkey
        window.level = .floating
    }

    func hide() {
        window?.orderOut(nil)
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        onCloseRequested?()
        
        // If a selection triggered hide, auto-paste into the previously active app
        if autoPastePending {
            autoPastePending = false
            reactivatePreviousAppAndPaste()
        }
    }
    
    func hideImmediatelyAndPaste() {
        // Hide window first for instant visual response
        window?.orderOut(nil)
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        onCloseRequested?()
        
        // Then handle focus switch and paste in background
        if autoPastePending {
            autoPastePending = false
            reactivatePreviousAppAndPaste()
        }
    }

    private func createWindow() {
        let content = ContentView(viewModel: viewModel, onSelect: { [weak self] item in
            guard let self else { return }
            self.viewModel.setPasteboard(to: item)
            self.viewModel.promote(item)
            // Mark that we want to auto-paste after hiding the overlay
            self.autoPastePending = true
            self.hideImmediatelyAndPaste()
        }, onOpenSettings: { [weak self] in
            self?.openSettings()
        })
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


    @objc private func closeRequested() {
        hideImmediatelyRefocusOnly()
    }

    @objc private func openSettingsRequested() {
        openSettings()
    }

    private func openSettings() {
        SettingsWindowController.shared.show()
        applyTheme()
    }
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
    
    func reactivatePreviousAppAndPaste() {
        guard let app = previousActiveApp else { return }
        AppFocusService.shared.switchToAppAndPaste(app)
    }
    
    func reactivatePreviousAppOnly() {
        guard let app = previousActiveApp else { return }
        AppFocusService.shared.switchToAppOnly(app)
    }

    func hideImmediatelyRefocusOnly() {
        // Hide window first for instant visual response
        window?.orderOut(nil)
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        onCloseRequested?()
        // Only refocus the previous app, do not paste
        reactivatePreviousAppOnly()
    }
}

