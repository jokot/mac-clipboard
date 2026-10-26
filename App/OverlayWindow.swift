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
    private var idleTimer: Timer?
    private var idleMonitor: Any?
    private let imageEditor = ImageEditorWindowController()
    private var previewPanel: NSPanel?
    private var previewedItemID: UUID?
    private var lastActivity: Date = Date()

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
                guard let self = self, self.window?.isKeyWindow == true else { return event }
                if event.keyCode == 53 { // Escape key
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
        startIdleTracking()
    }

    func hide() {
        closePreview()
        stopIdleTracking()
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
        closePreview()
        stopIdleTracking()
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

            if AppSettings.shared.moveTopOnClick {
                self.viewModel.promote(item)
            }

            if AppSettings.shared.pasteOnClick && !AccessibilityAccess.shared.isGrantedNow() {
                // Without access, Command+V does not reach the other app. The clip
                // is on the pasteboard, so explain the request one time per launch.
                self.autoPastePending = false
                let previousApp = self.previousActiveApp
                self.hideImmediatelyRefocusOnly()
                if AccessibilityAccess.shared.shouldAskBeforePaste() {
                    AccessibilityPromptWindowController.shared.show(afterCopy: true) {
                        previousApp?.activate(options: [.activateIgnoringOtherApps])
                    }
                }
            } else if AppSettings.shared.pasteOnClick {
                self.autoPastePending = true
                self.hideImmediatelyAndPaste()
            } else {
                self.autoPastePending = false
                self.hideImmediatelyRefocusOnly()
            }
        }, onOpenSettings: { [weak self] in
            self?.openSettings()
        }, onEditImage: { [weak self] item, image in
            self?.openImageEditor(item: item, image: image)
        }, onEdit: { [weak self] item in
            self?.showPreview(item, editing: true)
        }, onPreview: { [weak self] item in
            self?.showPreview(item)
        }, onTogglePreview: { [weak self] item in
            guard let self else { return }
            if self.previewedItemID != nil { self.closePreview() } else { self.showPreview(item) }
        }, onSelectionChange: { [weak self] item in
            // The same clip is already in the preview. Showing it again would end an edit.
            guard let self, self.previewedItemID != nil, item?.id != self.previewedItemID else { return }
            if let item { self.showPreview(item) } else { self.closePreview() }
        })
        .background(ESCKeyCatcher())

        let hosting = FirstMouseHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.acceptsMouseMovedEvents = true
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


    // The editor gets its own window. Hide the overlay while it is open, then
    // return focus to the previous app on close. Otherwise MaClip stays
    // frontmost and the next screenshot is dropped by the self-exclusion rule.
    private func openImageEditor(item: ClipboardItem, image: NSImage) {
        hideForImageEditor()
        imageEditor.show(item: item, image: image, viewModel: viewModel) { [weak self] in
            guard let self, !self.isVisible else { return }
            self.reactivatePreviousAppOnly()
        }
    }

    private func hideForImageEditor() {
        stopIdleTracking()
        window?.orderOut(nil)
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        onCloseRequested?()
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

    private func startIdleTracking() {
        stopIdleTracking()
        guard AppSettings.shared.autoDismissOverlayEnabled else { return }
        lastActivity = Date()
        idleMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] event in
            self?.lastActivity = Date()
            return event
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(self.lastActivity)
                if elapsed >= AppSettings.shared.autoDismissOverlayTimeout {
                    self.stopIdleTracking()
                    self.hideImmediatelyRefocusOnly()
                }
            }
        }
    }

    private func stopIdleTracking() {
        idleTimer?.invalidate()
        idleTimer = nil
        if let idleMonitor {
            NSEvent.removeMonitor(idleMonitor)
            self.idleMonitor = nil
        }
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
    
    // MARK: - Preview

    /// Shows the clip in a panel beside the clip window. The panel is a child window, so it
    /// moves and hides with the clip window, and the clip window keeps the keyboard.
    /// In edit mode, the panel takes the keyboard until Save or Cancel.
    func showPreview(_ item: ClipboardItem, editing: Bool = false) {
        guard let window else { return }
        previewedItemID = item.id
        let view = ClipPreviewView(
            item: item,
            loadImageData: { [weak self] url in self?.viewModel.imageData(at: url) },
            onPaste: { [weak self] in self?.pasteFromPreview(item) },
            onCopyOnly: { [weak self] in
                self?.viewModel.setPasteboard(to: item)
                self?.hideImmediatelyRefocusOnly()
            },
            onEdit: { [weak self] in self?.editFromPreview(item) },
            onClose: { [weak self] in self?.closePreview() },
            isEditing: editing,
            onSave: { [weak self] content in self?.saveEdit(of: item, content: content) },
            onCancelEdit: { [weak self] in self?.endEdit(showing: item) }
        )
        let panel = previewPanel ?? makePreviewPanel()
        previewPanel = panel
        if let effect = panel.contentView as? NSVisualEffectView,
           let hosting = effect.subviews.first as? FirstMouseHostingView<ClipPreviewView> {
            hosting.rootView = view
        } else {
            let effect = NSVisualEffectView()
            effect.material = .contentBackground
            effect.state = .active
            effect.blendingMode = .withinWindow
            let hosting = FirstMouseHostingView(rootView: view)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: effect.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
            ])
            panel.contentView = effect
        }
        panel.appearance = window.appearance
        // Beside the clip window, on the right if it fits on the screen, else on the left.
        let gap: CGFloat = 12
        let size = NSSize(width: 408, height: window.frame.height)
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var x = window.frame.maxX + gap
        if x + size.width > screen.maxX { x = window.frame.minX - gap - size.width }
        panel.setFrame(NSRect(x: x, y: window.frame.minY, width: size.width, height: size.height), display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
        if editing {
            panel.makeKey()
        } else if panel.isKeyWindow {
            window.makeKey()
        }
    }

    private func saveEdit(of item: ClipboardItem, content: ClipboardItemContent) {
        let updated = viewModel.replaceContent(of: item, with: content) ?? item
        endEdit(showing: updated)
    }

    /// Back to the preview, and the clip window takes the keyboard again.
    private func endEdit(showing item: ClipboardItem) {
        showPreview(item)
        window?.makeKey()
    }

    func closePreview() {
        previewedItemID = nil
        guard let panel = previewPanel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func makePreviewPanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 408, height: 600),
                            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Only a click in selectable text makes the panel key, so the clip window keeps the keys.
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }

    private func pasteFromPreview(_ item: ClipboardItem) {
        viewModel.setPasteboard(to: item)
        if AppSettings.shared.moveTopOnClick { viewModel.promote(item) }
        if AppSettings.shared.pasteOnClick && AccessibilityAccess.shared.isGrantedNow() {
            autoPastePending = true
            hideImmediatelyAndPaste()
        } else {
            autoPastePending = false
            hideImmediatelyRefocusOnly()
        }
    }

    private func editFromPreview(_ item: ClipboardItem) {
        if case .image(let content) = item.content {
            closePreview()
            var image: NSImage?
            switch content.source {
            case .memory(let img): image = img
            case .file(let url): image = viewModel.imageData(at: url).flatMap(NSImage.init(data:))
            }
            if let image { openImageEditor(item: item, image: image) }
        } else {
            showPreview(item, editing: true)
        }
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
        closePreview()
        stopIdleTracking()
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

