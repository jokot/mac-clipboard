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
            TextItemContent(string: string, date: item.date, isHovered: isHovered, onRemove: onRemove)
        case .image(let imgContent):
            ImageItemContent(imgContent: imgContent, item: item, isHovered: isHovered, onRemove: onRemove, onExtractText: onExtractText, onExtractBarcode: onExtractBarcode)
        case .url(let url):
            URLItemContent(url: url, date: item.date, isHovered: isHovered, onRemove: onRemove)
        }
    }
}

// MARK: - Private subviews (Option B)

private struct TextItemContent: View {
    let string: String
    let date: Date
    let isHovered: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(TextPreview.preview(for: string))
                    .font(.body)
                    .lineLimit(4)
                Text(date, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isHovered {
                pillButton(label: "Delete", systemImage: "trash", color: .red, outlineOpacity: 0.35, fillsWidth: false, action: onRemove)
            }
        }
        .padding(.trailing, 10)
    }
}

private struct ImageItemContent: View {
    let imgContent: ImageContent
    let item: ClipboardItem
    let isHovered: Bool
    let onRemove: () -> Void
    var onExtractText: ((ClipboardItem) -> Void)? = nil
    var onExtractBarcode: ((ClipboardItem) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 8) {
                Image(nsImage: imgContent.image)
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
                            pillButton(label: "Extract Text", systemImage: "text.viewfinder", color: .accentColor, outlineOpacity: 0.35, fillsWidth: true) {
                                onExtractText(item)
                            }
                        }
                        if let onExtractBarcode {
                            pillButton(label: "Extract Code", systemImage: "barcode.viewfinder", color: .accentColor, outlineOpacity: 0.35, fillsWidth: true) {
                                onExtractBarcode(item)
                            }
                        }

                        pillButton(label: "Delete", systemImage: "trash", color: .red, outlineOpacity: 0.35, fillsWidth: false, action: onRemove)
                    }
                    .frame(maxWidth: .infinity)
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

private struct URLItemContent: View {
    let url: URL
    let date: Date
    let isHovered: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "link")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(url.absoluteString)
                    .font(.body)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(date, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                if isHovered {
                    pillButton(label: "Open", systemImage: "safari", color: .accentColor, outlineOpacity: 0.35, fillsWidth: false) {
                        NSWorkspace.shared.open(url)
                        NotificationCenter.default.post(name: .overlayCloseRequested, object: nil)
                    }
                    pillButton(label: "Delete", systemImage: "trash", color: .red, outlineOpacity: 0.35, fillsWidth: false, action: onRemove)
                }
            }
        }
        .padding(.trailing, 10)
    }
}

// MARK: - Small styling helper

@ViewBuilder
private func pillButton(label: String, systemImage: String, color: Color, outlineOpacity: Double, fillsWidth: Bool = false, action: @escaping () -> Void) -> some View {
    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    Button(action: action) {
        Label(label, systemImage: systemImage)
            .font(.callout)
            .foregroundColor(color)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .contentShape(shape)
            .background(
                shape
                    .stroke(color.opacity(outlineOpacity), lineWidth: 1)
            )
    }
    .buttonStyle(.plain)
}