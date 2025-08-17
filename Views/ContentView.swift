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
    
    private let ocrService: OCRServiceProtocol = OCRService()

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
    }

    private var header: some View {
        HStack {
            Text("Clipboard History")
                .font(.headline)
            TextField("Search", text: $viewModel.searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 240)
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
                                        // Check if we have cached text results
                                        if let cachedText = imgContent.cachedText, !cachedText.isEmpty {
                                            let resultItem = viewModel.promoteOrInsertResult(text: cachedText)
                                            viewModel.setPasteboard(to: resultItem)
                                        } else if let cachedBarcode = imgContent.cachedBarcode, !cachedBarcode.isEmpty {
                                            // If barcode has already been extracted for this image, do nothing on text extraction
                                            return
                                        } else {
                                            do {
                                                let text = try await ocrService.extractText(from: imgContent.image)
                                                let textId = text // For now, use text as ID
                                                viewModel.updateImageItemCache(item, cachedText: text, cachedId: textId, cachedBarcode: nil)
                                                let resultItem = viewModel.promoteOrInsertResult(text: text)
                                                viewModel.setPasteboard(to: resultItem)
                                            } catch {
                                                NSSound.beep()
                                            }
                                        }
                                    }
                                }
                            },
                            onExtractBarcode: { item in
                                Task { @MainActor in
                                    if case .image(let imgContent) = item.content {
                                        // Check if we have cached barcode results
                                        if let barcode = imgContent.cachedBarcode, !barcode.isEmpty {
                                            let resultItem = viewModel.promoteOrInsertResult(text: barcode)
                                            viewModel.setPasteboard(to: resultItem)
                                        } else if let cachedText = imgContent.cachedText, !cachedText.isEmpty {
                                            // If text has already been extracted for this image, do nothing on barcode extraction
                                            return
                                        } else {
                                            do {
                                                let code = try await ocrService.extractBarcode(from: imgContent.image)
                                                // Save code to both cachedId and cachedBarcode to differentiate source
                                                viewModel.updateImageItemCache(item, cachedText: nil, cachedId: code, cachedBarcode: code)
                                                let resultItem = viewModel.promoteOrInsertResult(text: code)
                                                viewModel.setPasteboard(to: resultItem)
                                            } catch {
                                                NSSound.beep()
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