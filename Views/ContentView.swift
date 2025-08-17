import SwiftUI
import AppKit
import Combine
import Foundation

struct ContentView: View {
    @ObservedObject var viewModel: ClipboardListViewModel
    var onSelect: (ClipboardItem) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    @State private var isShowingClearConfirm: Bool = false
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool
    @State private var extractionAlert: ExtractionAlert?

    private let ocrService: OCRServiceProtocol = OCRService()

    struct ExtractionAlert: Identifiable {
        let id = UUID()
        let message: String
    }

    init(viewModel: ClipboardListViewModel,
         onSelect: @escaping (ClipboardItem) -> Void = { _ in },
         onOpenSettings: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onSelect = onSelect
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.filteredItems.isEmpty {
                GeometryReader { proxy in
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundColor(.secondary)
                        Text("No items yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, max(48, proxy.size.height * 0.3))
                }
            } else {
                list
            }
        }
        .frame(minWidth: 480, minHeight: 480)
        .ignoresSafeArea(.container, edges: .top)
        .onReceive(NotificationCenter.default.publisher(for: .overlayFocusSearch)) { _ in
            isSearchFocused = true
        }
        .alert(item: $extractionAlert) { alert in
            Alert(title: Text("No Result"), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    private var header: some View {
        HStack {
            Text("Clipboard History")
                .font(.headline)
            TextField("Search", text: $viewModel.searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 240)
                .focused($isSearchFocused)
            Spacer()
            Button(action: { isShowingClearConfirm = true }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            Button(action: { onOpenSettings() }) {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            Button(action: { NotificationCenter.default.post(name: .overlayCloseRequested, object: nil) }) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .alert("Clear all history?", isPresented: $isShowingClearConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) { viewModel.clearHistory() }
        } message: {
            Text("This will remove all clipboard items from the list.")
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
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
                                                let resultItem = viewModel.promoteOrInsertResult(text: cachedText)
                                                viewModel.setPasteboard(to: resultItem)
                                                return
                                            }
                                        }

                                        // No cached text yet: perform OCR
                                        do {
                                            let text = try await ocrService.extractText(from: imgContent.image)
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
                                            let resultItem = viewModel.promoteOrInsertResult(text: text)
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
                                                let resultItem = viewModel.promoteOrInsertResult(text: barcode)
                                                viewModel.setPasteboard(to: resultItem)
                                                return
                                            }
                                        }

                                        // No cached barcode yet: perform detection
                                        do {
                                            let code = try await ocrService.extractBarcode(from: imgContent.image)
                                            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !trimmed.isEmpty else {
                                                // Cache negative result to avoid re-running unnecessarily
                                                viewModel.updateImageItemCache(item, cachedText: nil, cachedId: nil, cachedBarcode: "")
                                                NSSound.beep()
                                                extractionAlert = ExtractionAlert(message: "No barcode detected in the image.")
                                                return
                                            }
                                            viewModel.updateImageItemCache(item, cachedText: nil, cachedId: code, cachedBarcode: code)
                                            let resultItem = viewModel.promoteOrInsertResult(text: code)
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
                            }
                        )
                        .id(item.id)
                        Divider()
                    }
                }
                .padding(12)
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
}