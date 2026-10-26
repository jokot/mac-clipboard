import SwiftUI
import AppKit
import Combine
import Foundation

struct ContentView: View {
    @ObservedObject var viewModel: ClipboardListViewModel
    /// The side with focus and the preview state, shared with the window controller.
    @ObservedObject var windowState: ClipWindowState
    @ObservedObject private var settings = AppSettings.shared
    var onSelect: (ClipboardItem) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    var onEditImage: (ClipboardItem, NSImage) -> Void = { _, _ in }
    /// Opens the preview of a text, link or file clip in edit mode.
    var onEdit: (ClipboardItem) -> Void = { _ in }
    /// Opens the preview for a clip. `onTogglePreview` opens or closes it for the selected clip.
    var onPreview: (ClipboardItem) -> Void = { _ in }
    var onTogglePreview: (ClipboardItem) -> Void = { _ in }
    /// The selected clip changed. An open preview then shows the new clip, or closes when nil.
    var onSelectionChange: (ClipboardItem?) -> Void = { _ in }
    /// ⌘K: shows these actions in a menu under the selected row.
    var onShowActions: ([ClipMenuAction], CGRect?) -> Void = { _, _ in }
    @State private var selectedRowFrame: CGRect?
    @State private var isShowingClearConfirm: Bool = false
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool
    @State private var extractionAlert: ExtractionAlert?
    @State private var editingImageAlert: String?

    private let ocrService: OCRServiceProtocol = OCRService()

    struct ExtractionAlert: Identifiable {
        let id = UUID()
        let message: String
    }

    init(viewModel: ClipboardListViewModel,
         windowState: ClipWindowState,
         onSelect: @escaping (ClipboardItem) -> Void = { _ in },
         onOpenSettings: @escaping () -> Void = {},
         onEditImage: @escaping (ClipboardItem, NSImage) -> Void = { _, _ in },
         onEdit: @escaping (ClipboardItem) -> Void = { _ in },
         onPreview: @escaping (ClipboardItem) -> Void = { _ in },
         onTogglePreview: @escaping (ClipboardItem) -> Void = { _ in },
         onSelectionChange: @escaping (ClipboardItem?) -> Void = { _ in },
         onShowActions: @escaping ([ClipMenuAction], CGRect?) -> Void = { _, _ in }) {
        self.viewModel = viewModel
        self.windowState = windowState
        self.onShowActions = onShowActions
        self.onSelect = onSelect
        self.onOpenSettings = onOpenSettings
        self.onEditImage = onEditImage
        self.onEdit = onEdit
        self.onPreview = onPreview
        self.onTogglePreview = onTogglePreview
        self.onSelectionChange = onSelectionChange
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.hasEncryptedHistoryToRestore && !settings.encryptedHistoryNoticeDismissed {
                restoreNotice
            }
            if viewModel.filteredItems.isEmpty {
                emptyState
            } else {
                list
            }
            hintBar
        }
        .frame(minWidth: 480, minHeight: 480)
        .ignoresSafeArea(.container, edges: .top)
        .overlay {
            // The focus ring shows which side takes the keys while the preview is open.
            if windowState.previewOpen && windowState.pane == .list {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .padding(3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .simultaneousGesture(TapGesture().onEnded { windowState.pane = .list })
        .shortcutsPanel(.clipList, title: "Clip window", note: "Global keys work in any app.") {
            ClipKeyMap.listColumns(globalKeys: globalKeyRows)
        }
        .onReceive(NotificationCenter.default.publisher(for: .overlayFocusSearch)) { _ in
            isSearchFocused = true
        }
        .alert(item: $extractionAlert) { alert in
            Alert(title: Text("No Result"), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .alert("Cannot edit image", isPresented: Binding(
            get: { editingImageAlert != nil },
            set: { if !$0 { editingImageAlert = nil } }
        )) {
            Button("OK") { editingImageAlert = nil }
        } message: {
            Text(editingImageAlert ?? "")
        }
    }

    private func openImageEditor(for item: ClipboardItem) {
        guard case .image(let imgContent) = item.content else { return }
        var img: NSImage?
        switch imgContent.source {
        case .memory(let m):
            img = m
        case .file(let url):
            if let data = viewModel.imageData(at: url) { img = NSImage(data: data) }
        }
        guard let image = img else {
            editingImageAlert = "Could not load image."
            return
        }
        let dim = max(image.size.width, image.size.height)
        guard dim <= 4096 else {
            editingImageAlert = "This image is too large to edit. The limit is 4096 px on each side."
            return
        }
        onEditImage(item, image)
    }

    // Shown after an update from 1.9.0-1.11.x, which encrypted the history.
    private var restoreNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundColor(Theme.warning)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your earlier clips are encrypted").fontWeight(.semibold)
                Text("Restore them in Settings \u{2192} Storage. macOS asks for your password one time.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Restore Clips\u{2026}") { onOpenSettings() }
                        .buttonStyle(AccentButtonStyle())
                    Button("Not Now") { settings.encryptedHistoryNoticeDismissed = true }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.hoverFill))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var header: some View {
        HStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .help("Search the clips. Filter with from:Safari or tag:code.")
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear the search")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.fieldFill))

            Button(action: { onOpenSettings() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")

            Menu {
                Button("Clear History\u{2026}") { isShowingClearConfirm = true }
                Button("About MaClip") { InfoWindow.show() }
                Divider()
                Button("Quit MaClip") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 32, height: 32)
            .help("More")
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .alert("Clear all history?", isPresented: $isShowingClearConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) { viewModel.clearHistory() }
        } message: {
            Text("This deletes all clips and their images. You cannot undo this.")
        }
    }

    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.fieldFill)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: isSearching ? "magnifyingglass" : "doc.on.clipboard")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                )
            if isSearching {
                Text("No clips match").font(.headline)
                Text("Try another word, or filter with from:Safari or tag:code.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No clips yet").font(.headline)
                Text("Copy text, a link, an image or a file in any app. MaClip saves it here.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Keyboard hints at the left, the clip count at the right.
    /// Three or four hints at most, so none of them wraps. ⌘/ shows all the keys.
    private var hintBar: some View {
        HStack(spacing: 14) {
            if windowState.previewOpen {
                hint("\u{2190} \u{2192}", "Switch")
                hint("esc", "Close preview")
            } else if !viewModel.filteredItems.isEmpty {
                hint("\u{2191}\u{2193}", "Move")
                hint("\u{21A9}", "Paste")
                hint("space", "Preview")
            } else {
                hint("esc", "Close")
            }
            hint("\u{2318}/", "Shortcuts")
            Spacer(minLength: 8)
            Text(ClipListSummary.text(total: viewModel.items.count,
                                      limit: settings.maxItems,
                                      matches: isSearching ? viewModel.filteredItems.count : nil))
                .lineLimit(1)
                .fixedSize()
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            KeyLabel(key: key)
            Text(label)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let items = viewModel.filteredItems
                    ForEach(Array(items.indices), id: \.self) { index in
                        let item = items[index]
                        ClipboardItemRow(
                            item: item,
                            onSelect: onSelect,
                            onRemove: { remove(item, at: index) },
                            isSelected: index == selectedIndex,
                            isListFocused: !windowState.previewOpen || windowState.pane == .list,
                            onExtractText: { item in extractText(item) },
                            onExtractBarcode: { item in extractCode(item) },
                            onExcludeApp: { bundleID in
                                confirmExclude(bundleID: bundleID)
                            },
                            loadImageData: { url in viewModel.imageData(at: url) },
                            onOpenFile: { item in openFile(item) },
                            onRevealInFinder: { item in revealInFinder(item) },
                            onCopyPath: { item in copyFilePath(item) },
                            onEdit: { item in
                                selectedIndex = index
                                onEdit(item)
                            },
                            onEditImage: { item in
                                openImageEditor(for: item)
                            },
                            onCopyOnly: { item in copyOnly(item) },
                            onPreview: { item in
                                selectedIndex = index
                                onPreview(item)
                            }
                        )
                        .id(item.id)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: SelectedRowFrameKey.self,
                                                   value: index == selectedIndex ? proxy.frame(in: .global) : nil)
                        })
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayDidShow)) { _ in
                viewModel.searchText = ""
                selectedIndex = 0
                let items = viewModel.filteredItems
                guard let first = items.first else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayCommand)) { note in
                if let command = note.object as? ClipCommand { perform(command) }
            }
            .onPreferenceChange(SelectedRowFrameKey.self) { selectedRowFrame = $0 }
            .onChange(of: selectedIndex) { _ in
                let items = viewModel.filteredItems
                guard items.indices.contains(selectedIndex) else { return }
                onSelectionChange(items[selectedIndex])
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(items[selectedIndex].id, anchor: .center)
                }
            }
            .onChange(of: viewModel.searchText) { _ in
                selectedIndex = 0
                let items = viewModel.filteredItems
                guard let first = items.first else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
        }
    }

    /// The keys from Settings that work in any app, for the shortcuts panel.
    private var globalKeyRows: [ShortcutRow] {
        var rows = [ShortcutRow(label: "Open MaClip",
                                keys: [HotkeyUtils.description(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)])]
        if settings.extractTextHotkeyEnabled {
            rows.append(ShortcutRow(label: "Paste text from image",
                                    keys: [HotkeyUtils.description(keyCode: settings.extractTextKeyCode, modifiers: settings.extractTextModifiers)]))
        }
        if settings.extractCodeHotkeyEnabled {
            rows.append(ShortcutRow(label: "Paste code from image",
                                    keys: [HotkeyUtils.description(keyCode: settings.extractCodeKeyCode, modifiers: settings.extractCodeModifiers)]))
        }
        return rows
    }

    /// Runs a key of the clip window. A key that does not fit the selected clip beeps,
    /// for example ⌘O on a text clip.
    private func perform(_ command: ClipCommand) {
        let items = viewModel.filteredItems
        switch command {
        case .moveUp: moveSelection(-1)
        case .moveDown: moveSelection(1)
        case .pageUp: moveSelection(-8)
        case .pageDown: moveSelection(8)
        case .moveFirst: if !items.isEmpty { selectedIndex = 0 }
        case .moveLast: if !items.isEmpty { selectedIndex = items.count - 1 }
        case .clearHistory: isShowingClearConfirm = true
        case .pasteClip(let number):
            guard items.indices.contains(number - 1) else { return NSSound.beep() }
            onSelect(items[number - 1])
        default:
            guard items.indices.contains(selectedIndex) else { return NSSound.beep() }
            let item = items[selectedIndex]
            if !run(command, on: item) { NSSound.beep() }
        }
    }

    /// Returns false when the command does not fit the clip.
    private func run(_ command: ClipCommand, on item: ClipboardItem) -> Bool {
        switch (command, item.content) {
        case (.paste, _): onSelect(item)
        case (.copyOnly, _): copyOnly(item)
        case (.togglePreview, _): onTogglePreview(item)
        case (.edit, .image): openImageEditor(for: item)
        case (.edit, _): onEdit(item)
        case (.showActions, _): onShowActions(menuActions(for: item), selectedRowFrame)
        case (.delete, _): remove(item, at: selectedIndex)
        case (.excludeApp, _):
            guard let bundleID = item.sourceBundleID else { return false }
            confirmExclude(bundleID: bundleID)
        case (.revealConcealed, _):
            guard item.isConcealed else { return false }
            NotificationCenter.default.post(name: .overlayRevealItem, object: item.id)
        case (.open, .url(let url)): openLink(url)
        case (.open, .file): openFile(item)
        case (.revealInFinder, .file): revealInFinder(item)
        case (.copyPath, .file): copyFilePath(item)
        case (.extractText, .image): extractText(item)
        case (.extractCode, .image): extractCode(item)
        default: return false
        }
        return true
    }

    /// The ⌘K menu: the same actions as the context menu, with their keys.
    private func menuActions(for item: ClipboardItem) -> [ClipMenuAction] {
        var actions = [
            ClipMenuAction(title: "Paste", key: KeyCombo(.returnKey)) { onSelect(item) },
            ClipMenuAction(title: "Copy Only", key: .command("c")) { copyOnly(item) },
            ClipMenuAction(title: "Preview", key: KeyCombo(.space)) { onTogglePreview(item) },
        ]
        switch item.content {
        case .url(let url):
            actions.append(ClipMenuAction(title: "Open Link", key: .command("o")) { openLink(url) })
        case .file:
            actions.append(ClipMenuAction(title: "Open", key: .command("o")) { openFile(item) })
            actions.append(ClipMenuAction(title: "Reveal in Finder", key: .command("r")) { revealInFinder(item) })
            actions.append(ClipMenuAction(title: "Copy Path", key: KeyCombo(.character("c"), [.option, .command])) { copyFilePath(item) })
        case .image:
            actions.append(ClipMenuAction(title: "Extract Text", key: .command("t")) { extractText(item) })
            actions.append(ClipMenuAction(title: "Extract Code", key: .command("b")) { extractCode(item) })
        case .text:
            break
        }
        if item.isConcealed {
            actions.append(ClipMenuAction(title: "Show for 5 Seconds", key: .command("u")) {
                NotificationCenter.default.post(name: .overlayRevealItem, object: item.id)
            })
        }
        actions.append(ClipMenuAction(title: "Edit\u{2026}", key: .command("e")) {
            if case .image = item.content { openImageEditor(for: item) } else { onEdit(item) }
        })
        actions.append(.separator)
        if let bundleID = item.sourceBundleID {
            let name = AppMetadata.shared.displayName(for: bundleID) ?? bundleID
            actions.append(ClipMenuAction(title: "Don\u{2019}t Save Clips from \(name)\u{2026}",
                                          key: KeyCombo(.delete, [.option, .command])) { confirmExclude(bundleID: bundleID) })
            actions.append(.separator)
        }
        let index = selectedIndex
        actions.append(ClipMenuAction(title: "Delete", key: KeyCombo(.delete, .command)) { remove(item, at: index) })
        return actions
    }

    /// Reads the text in an image clip, then copies it as a new text clip at the top.
    /// A result is cached on the clip, also an empty result.
    private func extractText(_ item: ClipboardItem) {
        Task { @MainActor in
            guard case .image(let imgContent) = item.content else { return }
            if let cachedText = imgContent.cachedText {
                guard !cachedText.isEmpty else {
                    NSSound.beep()
                    extractionAlert = ExtractionAlert(message: "No text found in the image.")
                    return
                }
                copyResult(cachedText, from: item)
                return
            }
            do {
                guard let image = image(of: imgContent) else { throw OCRService.OCRError.imageProcessingFailed }
                let text = try await ocrService.extractText(from: image)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    viewModel.updateImageItemCache(item, cachedText: "", cachedId: nil, cachedBarcode: nil)
                    NSSound.beep()
                    extractionAlert = ExtractionAlert(message: "No text found in the image.")
                    return
                }
                viewModel.updateImageItemCache(item, cachedText: text, cachedId: text, cachedBarcode: nil)
                copyResult(text, from: item)
            } catch {
                NSSound.beep()
                switch error as? OCRService.OCRError {
                case .noTextFound:
                    viewModel.updateImageItemCache(item, cachedText: "", cachedId: nil, cachedBarcode: nil)
                    extractionAlert = ExtractionAlert(message: "No text found in the image.")
                case .imageProcessingFailed, .visionRequestFailed:
                    extractionAlert = ExtractionAlert(message: "Failed to extract text from the image.")
                case .noBarcodeFound, nil:
                    break
                }
            }
        }
    }

    /// Reads the QR code or barcode in an image clip, then copies its value as a new text clip.
    private func extractCode(_ item: ClipboardItem) {
        Task { @MainActor in
            guard case .image(let imgContent) = item.content else { return }
            if let barcode = imgContent.cachedBarcode {
                guard !barcode.isEmpty else {
                    NSSound.beep()
                    extractionAlert = ExtractionAlert(message: "No barcode detected in the image.")
                    return
                }
                copyResult(barcode, from: item)
                return
            }
            do {
                guard let image = image(of: imgContent) else { throw OCRService.OCRError.imageProcessingFailed }
                let code = try await ocrService.extractBarcode(from: image)
                guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    viewModel.updateImageItemCache(item, cachedText: nil, cachedId: nil, cachedBarcode: "")
                    NSSound.beep()
                    extractionAlert = ExtractionAlert(message: "No barcode detected in the image.")
                    return
                }
                viewModel.updateImageItemCache(item, cachedText: nil, cachedId: code, cachedBarcode: code)
                copyResult(code, from: item)
            } catch {
                NSSound.beep()
                switch error as? OCRService.OCRError {
                case .noBarcodeFound:
                    viewModel.updateImageItemCache(item, cachedText: nil, cachedId: nil, cachedBarcode: "")
                    extractionAlert = ExtractionAlert(message: "No barcode detected in the image.")
                case .imageProcessingFailed, .visionRequestFailed:
                    extractionAlert = ExtractionAlert(message: "Failed to detect barcode in the image.")
                case .noTextFound, nil:
                    break
                }
            }
        }
    }

    private func image(of content: ImageContent) -> NSImage? {
        switch content.source {
        case .memory(let image): return image
        case .file(let url): return viewModel.imageData(at: url).flatMap(NSImage.init(data:))
        }
    }

    private func copyResult(_ text: String, from item: ClipboardItem) {
        let result = viewModel.promoteOrInsertResult(text: text, sourceBundleID: item.sourceBundleID, isOCRResult: true)
        viewModel.setPasteboard(to: result)
    }

    private func copyOnly(_ item: ClipboardItem) {
        viewModel.setPasteboard(to: item)
        NotificationCenter.default.post(name: .overlayCloseRequested, object: nil)
    }

    private func openLink(_ url: URL) {
        NSWorkspace.shared.open(url)
        NotificationCenter.default.post(name: .overlayCloseRequested, object: nil)
    }

    private func moveSelection(_ delta: Int) {
        let items = viewModel.filteredItems
        selectedIndex = max(0, min(items.count - 1, selectedIndex + delta))
    }

    /// Deletes a clip. The selection stays on the same clip, or moves to the clip below the
    /// deleted one, and an open preview follows it.
    private func remove(_ item: ClipboardItem, at index: Int) {
        viewModel.remove(item)
        let items = viewModel.filteredItems
        guard let next = ClipSelection.index(afterRemoving: index, selected: selectedIndex, newCount: items.count) else {
            selectedIndex = 0
            onSelectionChange(nil)
            return
        }
        selectedIndex = next
        onSelectionChange(items[next])
    }

    private func openFile(_ item: ClipboardItem) {
        guard case .file(let urls) = item.content else { return }
        for url in urls {
            NSWorkspace.shared.open(url)
        }
    }

    private func revealInFinder(_ item: ClipboardItem) {
        guard case .file(let urls) = item.content else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func copyFilePath(_ item: ClipboardItem) {
        guard case .file(let urls) = item.content else { return }
        let joined = urls.map(\.path).joined(separator: "\n")
        viewModel.copyToPasteboardAsText(joined, sourceBundleID: item.sourceBundleID)
    }

    private func confirmExclude(bundleID: String) {
        let displayName = AppMetadata.shared.displayName(for: bundleID) ?? bundleID
        let count = viewModel.items.filter { $0.sourceBundleID == bundleID }.count

        let alert = NSAlert()
        alert.messageText = "Exclude \(displayName) from history?"
        alert.informativeText = "MaClip will no longer save clips copied from \(displayName). You can re-enable this in Settings → Privacy."
        alert.addButton(withTitle: "Exclude")
        alert.addButton(withTitle: "Cancel")

        let checkbox = NSButton(checkboxWithTitle: "Also remove \(count) existing clip\(count == 1 ? "" : "s") from history",
                                target: nil, action: nil)
        checkbox.state = .on
        checkbox.isHidden = (count == 0)
        alert.accessoryView = checkbox

        if alert.runModal() == .alertFirstButtonReturn {
            if !AppSettings.shared.excludedBundleIDs.contains(bundleID) {
                AppSettings.shared.excludedBundleIDs.append(bundleID)
            }
            if checkbox.state == .on && count > 0 {
                viewModel.purgeItems(matchingBundleID: bundleID)
            }
        }
    }
}

/// The frame of the selected row in the window, for the ⌘K menu.
private struct SelectedRowFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
}
