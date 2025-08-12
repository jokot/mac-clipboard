import SwiftUI
import AppKit
import Combine
import Foundation

struct ContentView: View {
    @ObservedObject var viewModel: ClipboardListViewModel
    var onSelect: (ClipboardItem) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    var onOpenInfo: () -> Void = {}
    @State private var isShowingClearConfirm: Bool = false
    @State private var selectedIndex: Int = 0

    init(viewModel: ClipboardListViewModel,
         onSelect: @escaping (ClipboardItem) -> Void = { _ in },
         onOpenSettings: @escaping () -> Void = {},
         onOpenInfo: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onSelect = onSelect
        self.onOpenSettings = onOpenSettings
        self.onOpenInfo = onOpenInfo
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .frame(minWidth: 480, minHeight: 480)
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
            Button(action: { onOpenInfo() }) {
                Image(systemName: "info.circle")
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
                        ClipboardItemRow(item: item, onSelect: onSelect, onRemove: { viewModel.remove(item) }, isSelected: index == selectedIndex)
                            .id(item.id)
                        Divider()
                    }
                }
                .padding(12)
            }
            .onReceive(NotificationCenter.default.publisher(for: .overlayDidShow)) { _ in
                // Reset selection to top and scroll to the first item
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

    private func preview(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 300 { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 300)
        return String(trimmed[..<idx]) + "…"
    }
}

private extension ContentView {
    func moveSelection(_ delta: Int) {
        let count = viewModel.filteredItems.count
        guard count > 0 else { selectedIndex = 0; return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    func selectCurrent() {
        let items = viewModel.filteredItems
        guard items.indices.contains(selectedIndex) else { return }
        let item = items[selectedIndex]
        onSelect(item)
    }
}

// MARK: - Row with hover handling

private struct ClipboardItemRow: View {
    let item: ClipboardItem
    let onSelect: (ClipboardItem) -> Void
    let onRemove: () -> Void
    var isSelected: Bool = false

    @State private var isHovered: Bool = false

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { onSelect(item) }
            .onHover { isHovered = $0 }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((isHovered || isSelected) ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity((isHovered || isSelected) ? 0.35 : 0.1), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var content: some View {
        switch item.content {
        case .text(let string):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text(preview(for: string))
                        .font(.body)
                        .lineLimit(4)
                    Text(item.date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isHovered {
                    Button(action: { onRemove() }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        case .image(let image):
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 360, maxHeight: 200)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    Text(item.date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isHovered {
                    Button(action: { onRemove() }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func preview(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 300 { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 300)
        return String(trimmed[..<idx]) + "…"
    }
}

@MainActor
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: ClipboardListViewModel())
    }
}