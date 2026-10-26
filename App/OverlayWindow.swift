import Cocoa
import SwiftUI
import Combine
import Carbon.HIToolbox

@MainActor
final class OverlayWindowController: NSObject {
    private var window: NSWindow?
    private let viewModel: ClipboardListViewModel
    private let onCloseRequested: (() -> Void)?
    private var keyMonitor: Any?
    private var backgroundView: NSVisualEffectView?
    private var idleTimer: Timer?
    private var idleMonitor: Any?
    private let imageEditor = ImageEditorWindowController()
    private var previewPanel: NSPanel?
    private var previewedItemID: UUID?
    private var lastActivity: Date = Date()
    private let windowState = ClipWindowState()
    private var paneObserver: AnyCancellable?

    // Track the previously active app to restore focus and paste into it
    private var previousActiveApp: NSRunningApplication?
    internal var autoPastePending: Bool = false

    init(viewModel: ClipboardListViewModel, onCloseRequested: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onCloseRequested = onCloseRequested
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(closeRequested), name: .overlayCloseRequested, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeChanged, object: nil)
        // A click on the preview gives it focus. The search field then gives up the text cursor,
        // so typed letters do not go into the search behind the preview.
        paneObserver = windowState.$pane.sink { [weak self] pane in
            guard pane == .preview, let window = self?.window,
                  (window.firstResponder as? NSTextView)?.isFieldEditor == true else { return }
            window.makeFirstResponder(nil)
        }
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
        windowState.pane = .list
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        NotificationCenter.default.post(name: .overlayDidShow, object: nil)

        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown],
                                                          handler: KeyMonitorBlock.make(self) { $0.handleKey($1) })
        }

        applyTheme()
        // Ensure overlay window stays key when toggled via hotkey
        window.level = .floating
        startIdleTracking()
    }

    func hide() {
        tearDown()
        // If a selection triggered hide, auto-paste into the previously active app
        if autoPastePending {
            autoPastePending = false
            reactivatePreviousAppAndPaste()
        }
    }

    func hideImmediatelyAndPaste() {
        tearDown()
        // Then handle focus switch and paste in background
        if autoPastePending {
            autoPastePending = false
            reactivatePreviousAppAndPaste()
        }
    }

    /// Hides the window at once, for an instant visual response, and stops the key handling.
    private func tearDown() {
        closePreview()
        ShortcutsPanelState.shared.hide(.clipList)
        stopIdleTracking()
        window?.orderOut(nil)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        onCloseRequested?()
    }

    private func createWindow() {
        let content = ContentView(viewModel: viewModel, windowState: windowState, onSelect: { [weak self] item in
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
        }, onShowActions: { [weak self] actions, rowFrame in
            self?.showActionMenu(actions, at: rowFrame)
        })

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
        tearDown()
        imageEditor.show(item: item, image: image, viewModel: viewModel) { [weak self] in
            guard let self, !self.isVisible else { return }
            self.reactivatePreviousAppOnly()
        }
    }

    @objc private func closeRequested() {
        hideImmediatelyRefocusOnly()
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

// MARK: - Keys

private extension OverlayWindowController {
    /// One handler for every key in the clip window and the preview. `ClipKeyMap` decides
    /// what the key does from the side with focus, the search field and the edit mode.
    /// Returns nil when MaClip used the key.
    func handleKey(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window || (previewPanel != nil && event.window === previewPanel),
              let combo = KeyCombo(event: event) else { return event }
        let state = keyState(for: event)
        if let command = ClipKeyMap.command(for: combo, state: state) {
            perform(command)
            return nil
        }
        if typeToSearch(event, state: state) { return nil }
        return event
    }

    func keyState(for event: NSEvent) -> ClipKeyState {
        var state = ClipKeyState()
        state.previewOpen = previewedItemID != nil
        state.pane = state.previewOpen ? windowState.pane : .list
        state.editing = windowState.editing
        state.searchFocused = (window?.firstResponder as? NSTextView)?.isFieldEditor == true
        state.searchText = viewModel.searchText
        state.textSelected = ((event.window?.firstResponder as? NSTextView)?.selectedRange().length ?? 0) > 0
        let visible = ShortcutsPanelState.shared.visible
        state.shortcutsVisible = visible == .clipList || visible == .preview
        return state
    }

    func perform(_ command: ClipCommand) {
        switch command {
        case .ignore:
            break
        case .showShortcuts:
            let panel = ShortcutsPanelState.shared
            if let visible = panel.visible, visible == .clipList || visible == .preview {
                panel.hide(visible)
            } else {
                panel.toggle(previewedItemID != nil && windowState.pane == .preview ? .preview : .clipList)
            }
        case .quit:
            NSApp.terminate(nil)
        case .closeWindow:
            hideImmediatelyRefocusOnly()
        case .settings:
            openSettings()
        case .about:
            InfoWindow.show()
        case .back:
            goBack()
        case .focusPreview:
            windowState.pane = .preview
        case .focusList:
            focusList()
        case .focusSearch:
            focusList()
            NotificationCenter.default.post(name: .overlayFocusSearch, object: nil)
        case .scrollUp: scrollPreview(.line(-40))
        case .scrollDown: scrollPreview(.line(40))
        case .scrollPageUp: scrollPreview(.page(-1))
        case .scrollPageDown: scrollPreview(.page(1))
        case .scrollTop: scrollPreview(.edge(top: true))
        case .scrollBottom: scrollPreview(.edge(top: false))
        case .saveEdit:
            NotificationCenter.default.post(name: .previewEditCommand, object: PreviewEditAction.save)
        case .cancelEdit:
            NotificationCenter.default.post(name: .previewEditCommand, object: PreviewEditAction.cancel)
        default:
            // Clip actions need the selected clip, which the list knows.
            NotificationCenter.default.post(name: .overlayCommand, object: command)
        }
    }

    /// Esc: close the preview, else clear the search, else close the window.
    /// `ClipKeyMap` sends Esc in edit mode to `cancelEdit` instead.
    func goBack() {
        if previewedItemID != nil {
            closePreview()
            window?.makeKey()
        } else if !viewModel.searchText.isEmpty {
            viewModel.searchText = ""
        } else {
            hideImmediatelyRefocusOnly()
        }
    }

    func focusList() {
        windowState.pane = .list
        if previewPanel?.isKeyWindow == true { window?.makeKey() }
    }

    /// A letter in the list starts a search with that letter.
    func typeToSearch(_ event: NSEvent, state: ClipKeyState) -> Bool {
        guard !state.searchFocused, !state.editing, !state.shortcutsVisible,
              event.modifierFlags.intersection([.command, .control]).isEmpty,
              let characters = event.characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ scalar in
                  // No space, no control characters and no arrow or function keys.
                  scalar.value > 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
              }) else { return false }
        viewModel.searchText.append(characters)
        focusList()
        NotificationCenter.default.post(name: .overlayFocusSearch, object: nil)
        // ponytail: the search field selects all of its text when it gets focus, one or two
        // run loop turns later. Move the cursor to the end after that, so the next letter adds to the text.
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async {
                guard let editor = self?.window?.firstResponder as? NSTextView, editor.isFieldEditor else { return }
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            }
        }
        return true
    }

    enum PreviewScroll {
        case line(CGFloat), page(CGFloat), edge(top: Bool)
    }

    func scrollPreview(_ scroll: PreviewScroll) {
        guard let root = previewPanel?.contentView, let scrollView = Self.findScrollView(in: root),
              let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let maxOffset = max(0, document.frame.height - clip.bounds.height)
        // The distance from the top of the text, in a flipped or an unflipped document.
        var offset = document.isFlipped ? clip.bounds.origin.y : maxOffset - clip.bounds.origin.y
        switch scroll {
        case .line(let points): offset += points
        case .page(let direction): offset += direction * max(40, clip.bounds.height - 40)
        case .edge(let top): offset = top ? 0 : maxOffset
        }
        offset = min(max(0, offset), maxOffset)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: document.isFlipped ? offset : maxOffset - offset))
        scrollView.reflectScrolledClipView(clip)
    }

    static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView, scrollView.documentView != nil { return scrollView }
        for sub in view.subviews {
            if let found = findScrollView(in: sub) { return found }
        }
        return nil
    }

    /// ⌘K: the actions of the selected clip in a menu under its row. ↑ ↓ choose and ↩ runs.
    func showActionMenu(_ actions: [ClipMenuAction], at rowFrame: CGRect?) {
        guard let content = window?.contentView, !actions.isEmpty else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for action in actions {
            guard let run = action.run else {
                menu.addItem(.separator())
                continue
            }
            let item = ClosureMenuItem(title: action.title, run: run)
            if let combo = action.key, let equivalent = Self.keyEquivalent(for: combo) {
                item.keyEquivalent = equivalent.key
                item.keyEquivalentModifierMask = equivalent.modifiers
            }
            menu.addItem(item)
        }
        let frame = rowFrame ?? CGRect(x: content.bounds.midX, y: 60, width: 0, height: 0)
        let x = max(8, frame.maxX - 260)
        // SwiftUI frames start at the top left. The effect view starts at the bottom left.
        let y = content.isFlipped ? frame.maxY : content.bounds.height - frame.maxY
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: content)
    }

    static func keyEquivalent(for combo: KeyCombo) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        let key: String
        switch combo.key {
        case .character(let c): key = c
        case .returnKey: key = "\r"
        case .space: key = " "
        case .delete: key = "\u{8}"
        case .escape: key = "\u{1B}"
        default: return nil
        }
        var modifiers: NSEvent.ModifierFlags = []
        if combo.modifiers.contains(.control) { modifiers.insert(.control) }
        if combo.modifiers.contains(.option) { modifiers.insert(.option) }
        if combo.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if combo.modifiers.contains(.command) { modifiers.insert(.command) }
        return (key, modifiers)
    }
}

/// A menu item that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func fire() { run() }
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
        windowState.previewOpen = true
        windowState.editing = editing
        if editing { windowState.pane = .preview }
        let view = ClipPreviewView(
            item: item,
            windowState: windowState,
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

    /// Back to the preview, with focus on it, and the clip window takes the keyboard again.
    private func endEdit(showing item: ClipboardItem) {
        showPreview(item)
        windowState.pane = .preview
        window?.makeKey()
    }

    func closePreview() {
        previewedItemID = nil
        windowState.previewOpen = false
        windowState.editing = false
        windowState.pane = .list
        ShortcutsPanelState.shared.hide(.preview)
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
        tearDown()
        // Only refocus the previous app, do not paste
        reactivatePreviousAppOnly()
    }
}
