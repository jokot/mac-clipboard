import SwiftUI

struct ClipboardItemRow: View {
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
                    Text(TextPreview.preview(for: string))
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
}