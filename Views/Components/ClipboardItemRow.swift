import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let onSelect: (ClipboardItem) -> Void
    let onRemove: () -> Void
    var isSelected: Bool = false
    
    var onExtractText: ((ClipboardItem) -> Void)? = nil
    var onExtractBarcode: ((ClipboardItem) -> Void)? = nil
    var onExcludeApp: ((String) -> Void)? = nil

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
            .contextMenu {
                if let bundleID = item.sourceBundleID, let onExcludeApp {
                    let name = AppMetadata.shared.displayName(for: bundleID) ?? bundleID
                    Button("Exclude \"\(name)\" from history") { onExcludeApp(bundleID) }
                } else {
                    Text("Source unknown for this clip")
                        .foregroundColor(.secondary)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch item.content {
        case .text(let string):
            TextItemContent(string: string,
                            date: item.date,
                            bundleID: item.sourceBundleID,
                            isConcealed: item.isConcealed,
                            concealedExpiresAt: item.concealedExpiresAt,
                            isOCRResult: item.isOCRResult,
                            isHovered: isHovered,
                            fullItem: item,
                            onRemove: onRemove)
        case .image(let imgContent):
            ImageItemContent(imgContent: imgContent,
                             item: item,
                             bundleID: item.sourceBundleID,
                             isConcealed: item.isConcealed,
                             concealedExpiresAt: item.concealedExpiresAt,
                             isOCRResult: item.isOCRResult,
                             isHovered: isHovered,
                             onRemove: onRemove,
                             onExtractText: onExtractText,
                             onExtractBarcode: onExtractBarcode)
        case .url(let url):
            URLItemContent(url: url,
                           date: item.date,
                           bundleID: item.sourceBundleID,
                           isConcealed: item.isConcealed,
                           concealedExpiresAt: item.concealedExpiresAt,
                           isOCRResult: item.isOCRResult,
                           isHovered: isHovered,
                           fullItem: item,
                           onRemove: onRemove)
        }
    }
}

// MARK: - Private subviews (Option B)

private struct TextItemContent: View {
    let string: String
    let date: Date
    let bundleID: String?
    let isConcealed: Bool
    let concealedExpiresAt: Date?
    let isOCRResult: Bool
    let isHovered: Bool
    let fullItem: ClipboardItem
    let onRemove: () -> Void

    @State private var revealedUntil: Date? = nil

    private var isCurrentlyRevealed: Bool {
        guard let revealedUntil else { return false }
        return revealedUntil > Date()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            let primary = ContentTagDetector.primaryTag(for: fullItem)
            if primary == .color {
                ColorSwatchView(hex: string)
                    .frame(width: 28)
            } else {
                Image(systemName: primary?.symbolName ?? "doc.on.clipboard")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 6) {
                let displayString = (isConcealed && !isCurrentlyRevealed)
                    ? String(repeating: "•", count: min(8, max(1, string.count)))
                    : TextPreview.preview(for: string)
                Text(displayString)
                    .font(.body)
                    .lineLimit(4)
                HStack(spacing: 8) {
                    Text(date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if isConcealed {
                        ConcealedBadge(expiresAt: concealedExpiresAt)
                    }
                }
            }
            Spacer()
            if isOCRResult {
                OCRBadge()
            }
            if isConcealed && isHovered {
                RevealButton {
                    revealedUntil = Date().addingTimeInterval(5)
                    Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
                        Task { @MainActor in
                            revealedUntil = nil
                        }
                    }
                }
            }
            SourceIconBadge(bundleID: bundleID)
            if isHovered {
                pillButton(label: "Delete", systemImage: "trash", color: .red,
                           outlineOpacity: 0.35, fillsWidth: false, action: onRemove)
            }
        }
        .padding(.trailing, 10)
    }
}

private struct ImageItemContent: View {
    let imgContent: ImageContent
    let item: ClipboardItem
    let bundleID: String?
    let isConcealed: Bool
    let concealedExpiresAt: Date?
    let isOCRResult: Bool
    let isHovered: Bool
    let onRemove: () -> Void
    var onExtractText: ((ClipboardItem) -> Void)? = nil
    var onExtractBarcode: ((ClipboardItem) -> Void)? = nil

    @State private var loadedImage: NSImage? = nil
    @State private var revealedUntil: Date? = nil

    private var isCurrentlyRevealed: Bool {
        guard let revealedUntil else { return false }
        return revealedUntil > Date()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 8) {
                imageView
                    .frame(maxWidth: .infinity, maxHeight: 200)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .overlay {
                        if isConcealed && !isCurrentlyRevealed {
                            ZStack {
                                Color.black.opacity(0.45)
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .cornerRadius(8)
                        }
                    }

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

                HStack(spacing: 8) {
                    Text(item.date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if isConcealed {
                        ConcealedBadge(expiresAt: concealedExpiresAt)
                    }
                    Spacer()
                    if isOCRResult {
                        OCRBadge()
                    }
                    if isConcealed && isHovered {
                        RevealButton {
                            revealedUntil = Date().addingTimeInterval(5)
                            Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
                                Task { @MainActor in
                                    revealedUntil = nil
                                }
                            }
                        }
                    }
                    SourceIconBadge(bundleID: bundleID)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, 2)
    }
    
    @ViewBuilder
    private var imageView: some View {
        Group {
            if let image = effectiveImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.secondary.opacity(0.1)
                    .overlay(ProgressView())
                    .task {
                        if case .file(let url) = imgContent.source {
                            if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
                                self.loadedImage = img
                            }
                        }
                    }
            }
        }
    }
    
    // Use memory image if available, otherwise use loaded image
    private var effectiveImage: NSImage? {
        if case .memory(let img) = imgContent.source {
            return img
        }
        return loadedImage
    }
}

private struct URLItemContent: View {
    let url: URL
    let date: Date
    let bundleID: String?
    let isConcealed: Bool
    let concealedExpiresAt: Date?
    let isOCRResult: Bool
    let isHovered: Bool
    let fullItem: ClipboardItem
    let onRemove: () -> Void

    @State private var revealedUntil: Date? = nil

    private var isCurrentlyRevealed: Bool {
        guard let revealedUntil else { return false }
        return revealedUntil > Date()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ContentTagDetector.primaryTag(for: fullItem)?.symbolName ?? "link")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                let displayString: String = {
                    if isConcealed && !isCurrentlyRevealed {
                        let n = min(8, max(1, url.absoluteString.count))
                        return String(repeating: "•", count: n)
                    }
                    return url.absoluteString
                }()
                Text(displayString)
                    .font(.body)
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 8) {
                    Text(date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if isConcealed {
                        ConcealedBadge(expiresAt: concealedExpiresAt)
                    }
                }
            }
            Spacer()
            if isOCRResult {
                OCRBadge()
            }
            if isConcealed && isHovered {
                RevealButton {
                    revealedUntil = Date().addingTimeInterval(5)
                    Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
                        Task { @MainActor in
                            revealedUntil = nil
                        }
                    }
                }
            }
            SourceIconBadge(bundleID: bundleID)
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

private struct SourceIconBadge: View {
    let bundleID: String?

    var body: some View {
        Group {
            if let bundleID,
               let icon = AppMetadata.shared.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .help(AppMetadata.shared.displayName(for: bundleID) ?? bundleID)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
                    .help("Unknown source")
            }
        }
    }
}

private struct ConcealedBadge: View {
    let expiresAt: Date?
    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            if let expiresAt, expiresAt < Date.distantFuture {
                let remaining = max(0, Int(expiresAt.timeIntervalSince(now)))
                Text(formatRemaining(seconds: remaining))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .onReceive(timer) { now = $0 }
    }

    private func formatRemaining(seconds: Int) -> String {
        if seconds >= 60 {
            return "\(seconds / 60)m"
        }
        return "\(seconds)s"
    }
}

private struct OCRBadge: View {
    var body: some View {
        Image(systemName: "text.viewfinder")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .help("Extracted from image")
    }
}

private struct ColorSwatchView: View {
    let hex: String
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Self.color(fromHex: hex) ?? Color.gray)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .frame(width: 22, height: 22)
    }

    private static func color(fromHex hex: String) -> Color? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        // Accept 3 / 6 / 8 hex digits.
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6 || s.count == 8,
              let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((value & 0xFF000000) >> 24) / 255.0
            g = Double((value & 0x00FF0000) >> 16) / 255.0
            b = Double((value & 0x0000FF00) >> 8)  / 255.0
            a = Double( value & 0x000000FF)        / 255.0
        } else {
            r = Double((value & 0xFF0000) >> 16) / 255.0
            g = Double((value & 0x00FF00) >> 8)  / 255.0
            b = Double( value & 0x0000FF)        / 255.0
            a = 1.0
        }
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}

private struct RevealButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "eye")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .help("Reveal for 5 seconds")
        }
        .buttonStyle(.plain)
    }
}
