import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ClipboardStore
    var onSelect: (ClipboardItem) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}

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
            Spacer()
            Button(action: { onOpenSettings() }) {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            Button(action: { NotificationCenter.default.post(name: .overlayCloseRequested, object: nil) }) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(store.allItems()) { item in
                    itemRow(for: item)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(item)
                        }
                    Divider()
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func itemRow(for item: ClipboardItem) -> some View {
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
                        .textSelection(.enabled)
                    Text(item.date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environmentObject(ClipboardStore())
    }
}

