import SwiftUI
import AppKit
import Combine
import Foundation

struct ContentView: View {
    @ObservedObject var viewModel: ClipboardListViewModel
    @ObservedObject private var settings = AppSettings.shared
    var onSelect: (ClipboardItem) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    var onEditImage: (ClipboardItem, NSImage) -> Void = { _, _ in }
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
         onSelect: @escaping (ClipboardItem) -> Void = { _ in },
         onOpenSettings: @escaping () -> Void = {},
         onEditImage: @escaping (ClipboardItem, NSImage) -> Void = { _, _ in }) {
        self.viewModel = viewModel
        self.onSelect = onSelect
        self.onOpenSettings = onOpenSettings
        self.onEditImage = onEditImage
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
            editingImageAlert = "Image too large to edit in v1.11.0 (max 4096 px)."
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
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
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
    private var hintBar: some View {
        HStack(spacing: 16) {
            if !viewModel.filteredItems.isEmpty {
                hint("\u{2191}\u{2193}", "Move")
                hint("\u{21A9}", "Paste")
            }
            hint("esc", "Close")
            Spacer()
            Text(ClipListSummary.text(total: viewModel.items.count,
                                      limit: settings.maxItems,
                                      matches: isSearching ? viewModel.filteredItems.count : nil))
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
                            onRemove: { viewModel.remove(item) },
                            isSelected: index == selectedIndex,
                            onExtractText: { item in
                                Task { @MainActor in
                                    if case .image(let imgContent) = item.content {
                                        // If we have a cached text result (including negative cache as empty string), use it
                                        if let cachedText = imgContent.cachedText {
                                            if cachedText.isEmpty {
                                                NSSound.beep()
                                                extractionAlert = ExtractionAlert(message: "No text found in the image.")
                                                return
                                            } else {
                                                let resultItem = viewModel.promoteOrInsertResult(
                                                    text: cachedText,
                                                    sourceBundleID: item.sourceBundleID,
                                                    isOCRResult: true
                                                )
                                                viewModel.setPasteboard(to: resultItem)
                                                return
                                            }
                                        }

                                        // No cached text yet: perform OCR
                                        do {
                                            var resolvedImage: NSImage?
                                            switch imgContent.source {
                                            case .memory(let img): resolvedImage = img
                                            case .file(let url):
                                                if let data = viewModel.imageData(at: url) { resolvedImage = NSImage(data: data) }
                                            }
                                            guard let imageToProcess = resolvedImage else { throw OCRService.OCRError.imageProcessingFailed }

                                            let text = try await ocrService.extractText(from: imageToProcess)
                                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !trimmed.isEmpty else {
                                                // Cache negative result to avoid re-running unnecessarily
                                                viewModel.updateImageItemCache(item, cachedText: "", cachedId: nil, cachedBarcode: nil)
                                                NSSound.beep()
                                                extractionAlert = ExtractionAlert(message: "No text found in the image.")
                                                return
                                            }
                                            let textId = text
                                            viewModel.updateImageItemCache(item, cachedText: text, cachedId: textId, cachedBarcode: nil)
                                            let resultItem = viewModel.promoteOrInsertResult(
                                                text: text,
                                                sourceBundleID: item.sourceBundleID,
                                                isOCRResult: true
                                            )
                                            viewModel.setPasteboard(to: resultItem)
                                        } catch {
                                            NSSound.beep()
                                            if let ocrError = error as? OCRService.OCRError {
                                                switch ocrError {
                                                case .noTextFound:
                                                    // Cache negative result for next time
                                                    viewModel.updateImageItemCache(item, cachedText: "", cachedId: nil, cachedBarcode: nil)
                                                    extractionAlert = ExtractionAlert(message: "No text found in the image.")
                                                case .imageProcessingFailed, .visionRequestFailed:
                                                    extractionAlert = ExtractionAlert(message: "Failed to extract text from the image.")
                                                case .noBarcodeFound:
                                                    break
                                                }
                                            }
                                        }
                                    }
                                }
                            },
                            onExtractBarcode: { item in
                                Task { @MainActor in
                                    if case .image(let imgContent) = item.content {
                                        // If we have a cached barcode result (including negative cache as empty string), use it
                                        if let barcode = imgContent.cachedBarcode {
                                            if barcode.isEmpty {
                                                NSSound.beep()
                                                extractionAlert = ExtractionAlert(message: "No barcode detected in the image.")
                                                return
                                            } else {
                                                let resultItem = viewModel.promoteOrInsertResult(
                                                    text: barcode,
                                                    sourceBundleID: item.sourceBundleID,
                                                    isOCRResult: true
                                                )
                                                viewModel.setPasteboard(to: resultItem)
                                                return
                                            }
                                        }

                                        // No cached barcode yet: perform detection
                                        do {
                                            var resolvedImage: NSImage?
                                            switch imgContent.source {
                                            case .memory(let img): resolvedImage = img
                                            case .file(let url):
                                                if let data = viewModel.imageData(at: url) { resolvedImage = NSImage(data: data) }
                                            }
                                            guard let imageToProcess = resolvedImage else { throw OCRService.OCRError.imageProcessingFailed }

                                            let code = try await ocrService.extractBarcode(from: imageToProcess)
                                            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !trimmed.isEmpty else {
                                                // Cache negative result to avoid re-running unnecessarily
                                                viewModel.updateImageItemCache(item, cachedText: nil, cachedId: nil, cachedBarcode: "")
                                                NSSound.beep()
                                                extractionAlert = ExtractionAlert(message: "No barcode detected in the image.")
                                                return
                                            }
                                            viewModel.updateImageItemCache(item, cachedText: nil, cachedId: code, cachedBarcode: code)
                                            let resultItem = viewModel.promoteOrInsertResult(
                                                text: code,
                                                sourceBundleID: item.sourceBundleID,
                                                isOCRResult: true
                                            )
                                            viewModel.setPasteboard(to: resultItem)
                                        } catch {
                                            NSSound.beep()
                                            if let ocrError = error as? OCRService.OCRError {
                                                switch ocrError {
                                                case .noBarcodeFound:
                                                    // Cache negative result for next time
                                                    viewModel.updateImageItemCache(item, cachedText: nil, cachedId: nil, cachedBarcode: "")
                                                    extractionAlert = ExtractionAlert(message: "No barcode detected in the image.")
                                                case .imageProcessingFailed, .visionRequestFailed:
                                                    extractionAlert = ExtractionAlert(message: "Failed to detect barcode in the image.")
                                                case .noTextFound:
                                                    break
                                                }
                                            }
                                        }
                                    }
                                }
                            },
                            onExcludeApp: { bundleID in
                                confirmExclude(bundleID: bundleID)
                            },
                            loadImageData: { url in viewModel.imageData(at: url) },
                            onOpenFile: { item in openFile(item) },
                            onRevealInFinder: { item in revealInFinder(item) },
                            onCopyPath: { item in copyFilePath(item) },
                            onEdit: { item, newContent in
                                viewModel.replaceContent(of: item, with: newContent)
                            },
                            onEditImage: { item in
                                openImageEditor(for: item)
                            },
                            onCopyOnly: { item in
                                viewModel.setPasteboard(to: item)
                                NotificationCenter.default.post(name: .overlayCloseRequested, object: nil)
                            }
                        )
                        .id(item.id)
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
            .onReceive(NotificationCenter.default.publisher(for: .overlayMoveSelectionUp)) { _ in moveSelection(-1) }
            .onReceive(NotificationCenter.default.publisher(for: .overlayMoveSelectionDown)) { _ in moveSelection(1) }
            .onReceive(NotificationCenter.default.publisher(for: .overlaySelectCurrentItem)) { _ in selectCurrent() }
            .onChange(of: selectedIndex) { _ in
                let items = viewModel.filteredItems
                guard items.indices.contains(selectedIndex) else { return }
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

    private func moveSelection(_ delta: Int) {
        let items = viewModel.filteredItems
        selectedIndex = max(0, min(items.count - 1, selectedIndex + delta))
    }

    private func selectCurrent() {
        let items = viewModel.filteredItems
        guard items.indices.contains(selectedIndex) else { return }
        onSelect(items[selectedIndex])
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