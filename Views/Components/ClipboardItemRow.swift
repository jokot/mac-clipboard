import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let onSelect: (ClipboardItem) -> Void
    let onRemove: () -> Void
    var isSelected: Bool = false
    
    var onExtractText: ((ClipboardItem) -> Void)? = nil
    var onExtractBarcode: ((ClipboardItem) -> Void)? = nil

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
                        Label("Delete", systemImage: "trash")
                            .font(.callout)
                            .foregroundColor(.red)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.red.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, 10)
        case .image(let image):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 8) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 200)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                    if isHovered {
                        HStack(spacing: 8) {
                            if let onExtractText {
                                Button(action: { onExtractText(item) }) {
                                    Label("Extract Text", systemImage: "text.viewfinder")
                                        .font(.callout)
                                        .foregroundColor(.accentColor)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                        .frame(maxWidth: .infinity)
                                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            if let onExtractBarcode {
                                Button(action: { onExtractBarcode(item) }) {
                                    Label("Extract Code", systemImage: "barcode.viewfinder")
                                        .font(.callout)
                                        .foregroundColor(.accentColor)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                        .frame(maxWidth: .infinity)
                                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }

                            Button(action: { onRemove() }) {
                                Label("Delete", systemImage: "trash")
                                    .font(.callout)
                                    .foregroundColor(.red)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.red.opacity(0.35), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity) // allow the HStack to occupy full width so extracts can expand equally
                    }

                    Text(item.date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, 2)
        }
    }
}