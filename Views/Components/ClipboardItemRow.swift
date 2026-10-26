import SwiftUI

/// One clip in the clip window: the kind icon with the source app icon, the content,
/// and at the right the age. On hover and on the selected row, the row actions replace the age.
struct ClipboardItemRow: View {
    let item: ClipboardItem
    let onSelect: (ClipboardItem) -> Void
    let onRemove: () -> Void
    var isSelected: Bool = false
    /// False while the preview has focus. The selected row is then gray, like an inactive selection.
    var isListFocused: Bool = true

    var onExtractText: ((ClipboardItem) -> Void)? = nil
    var onExtractBarcode: ((ClipboardItem) -> Void)? = nil
    var onExcludeApp: ((String) -> Void)? = nil
    /// Reads image bytes from an `Images/*.png` or `Images/*.enc` URL. Required for `.file` image
    /// sources; without it, the preview stays blank.
    var loadImageData: ((URL) -> Data?)? = nil
    var onOpenFile: ((ClipboardItem) -> Void)? = nil
    var onRevealInFinder: ((ClipboardItem) -> Void)? = nil
    var onCopyPath: ((ClipboardItem) -> Void)? = nil
    /// Opens the preview panel in edit mode for a text, link or file clip.
    var onEdit: ((ClipboardItem) -> Void)? = nil
    var onEditImage: ((ClipboardItem) -> Void)? = nil
    /// Puts the clip on the pasteboard without pasting it.
    var onCopyOnly: ((ClipboardItem) -> Void)? = nil
    /// Opens the preview panel for this clip.
    var onPreview: ((ClipboardItem) -> Void)? = nil

    @State private var isHovered: Bool = false
    @State private var revealedUntil: Date? = nil

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: Theme.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? (isListFocused ? Theme.selectedFill : Theme.inactiveSelectedFill)
                                     : (isHovered ? Theme.hoverFill : Color.clear))
            )
            .contentShape(Rectangle())
            .onTapGesture { onSelect(item) }
            .onHover { isHovered = $0 }
            .contextMenu { contextMenu }
            .onReceive(NotificationCenter.default.publisher(for: .overlayRevealItem)) { note in
                if (note.object as? UUID) == item.id, item.isConcealed { reveal() }
            }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        Button("Paste") { onSelect(item) }
            .keyboardShortcut(.return, modifiers: [])
        Button("Copy Only") { onCopyOnly?(item) }
            .keyboardShortcut("c", modifiers: .command)
        if let onPreview {
            Button("Preview") { onPreview(item) }
                .keyboardShortcut(.space, modifiers: [])
        }
        switch item.content {
        case .url(let url):
            Button("Open Link") { openLink(url) }
                .keyboardShortcut("o", modifiers: .command)
        case .file:
            Button("Open") { onOpenFile?(item) }
                .keyboardShortcut("o", modifiers: .command)
            Button("Reveal in Finder") { onRevealInFinder?(item) }
                .keyboardShortcut("r", modifiers: .command)
            Button("Copy Path") { onCopyPath?(item) }
                .keyboardShortcut("c", modifiers: [.option, .command])
        case .image:
            if let onExtractText {
                Button("Extract Text") { onExtractText(item) }
                    .keyboardShortcut("t", modifiers: .command)
            }
            if let onExtractBarcode {
                Button("Extract Code") { onExtractBarcode(item) }
                    .keyboardShortcut("b", modifiers: .command)
            }
        case .text:
            EmptyView()
        }
        if item.isConcealed {
            Button("Show for 5 Seconds") { reveal() }
                .keyboardShortcut("u", modifiers: .command)
        }
        if ClipEdit.canEdit(item.content), let onEdit {
            Button("Edit…") { onEdit(item) }
                .keyboardShortcut("e", modifiers: .command)
        } else if case .image = item.content, let onEditImage {
            Button("Edit…") { onEditImage(item) }
                .keyboardShortcut("e", modifiers: .command)
        }
        Divider()
        if let bundleID = item.sourceBundleID, let onExcludeApp {
            let name = AppMetadata.shared.displayName(for: bundleID) ?? bundleID
            Button("Don\u{2019}t Save Clips from \(name)\u{2026}") { onExcludeApp(bundleID) }
                .keyboardShortcut(.delete, modifiers: [.option, .command])
            Divider()
        }
        Button("Delete", role: .destructive) { onRemove() }
            .keyboardShortcut(.delete, modifiers: .command)
    }

    // MARK: - Content

    private var isRevealed: Bool {
        guard let revealedUntil else { return false }
        return revealedUntil > Date()
    }

    private func reveal() {
        revealedUntil = Date().addingTimeInterval(5)
        Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            Task { @MainActor in revealedUntil = nil }
        }
    }

    private func openLink(_ url: URL) {
        NSWorkspace.shared.open(url)
        NotificationCenter.default.post(name: .overlayCloseRequested, object: nil)
    }

    private var kindSymbol: String {
        if item.isConcealed { return "lock.fill" }
        if item.isOCRResult { return "text.viewfinder" }
        switch item.content {
        case .image: return "photo"
        case .file(let urls):
            guard let first = urls.first, FileManager.default.fileExists(atPath: first.path) else {
                return "questionmark.folder"
            }
            return first.hasDirectoryPath ? "folder" : "doc"
        case .url: return ContentTagDetector.primaryTag(for: item)?.symbolName ?? "link"
        case .text: return ContentTagDetector.primaryTag(for: item)?.symbolName ?? "text.alignleft"
        }
    }

    private var kindTint: Color {
        if item.isConcealed { return Theme.warning }
        if case .text(let string) = item.content, ContentTagDetector.primaryTag(for: item) == .color {
            return ColorParser.color(fromHex: string) ?? .secondary
        }
        return .secondary
    }

    private func masked(_ string: String) -> String {
        String(repeating: "\u{2022}", count: min(12, max(4, string.count)))
    }

    @ViewBuilder
    private var content: some View {
        switch item.content {
        case .image(let imgContent):
            HStack(alignment: .top, spacing: 12) {
                KindTile(systemImage: kindSymbol, tint: kindTint, bundleID: item.sourceBundleID)
                ImagePreview(imgContent: imgContent,
                             isConcealed: item.isConcealed && !isRevealed,
                             loadImageData: loadImageData)
                    .overlay(alignment: .topTrailing) {
                        if showsActions { imageActions.padding(8) }
                    }
                trailing(actions: { EmptyView() })
            }
        default:
            HStack(alignment: .center, spacing: 12) {
                KindTile(systemImage: kindSymbol, tint: kindTint, bundleID: item.sourceBundleID)
                mainText
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing(actions: { rowActions })
            }
        }
    }

    @ViewBuilder
    private var mainText: some View {
        let hidden = item.isConcealed && !isRevealed
        switch item.content {
        case .text(let string):
            let tag = ContentTagDetector.primaryTag(for: item)
            let isCode = tag == .code || tag == .json || tag == .diff
            Text(hidden ? masked(string) : TextPreview.preview(for: string))
                .font(isCode && !hidden ? .system(size: 12, design: .monospaced) : .body)
                .foregroundColor(hidden ? .secondary : .primary)
                .lineLimit(2)
        case .url(let url):
            Text(hidden ? masked(url.absoluteString) : url.absoluteString)
                .foregroundColor(hidden ? .secondary : Theme.accent)
                .lineLimit(1)
                .truncationMode(.middle)
        case .file(let urls):
            let name = urls.first?.lastPathComponent ?? "(unknown)"
            (Text(hidden ? masked(name) : name)
             + Text(urls.count > 1 && !hidden ? "  and \(urls.count - 1) more" : "").foregroundColor(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(urls.prefix(10).map(\.path).joined(separator: "\n")
                      + (urls.count > 10 ? "\n(\(urls.count - 10) more)" : ""))
        case .image:
            EmptyView()
        }
    }

    /// The age, or the clear countdown of a concealed clip. On hover or selection, the actions.
    @ViewBuilder
    private func trailing<A: View>(@ViewBuilder actions: () -> A) -> some View {
        if showsActions && !(A.self == EmptyView.self) {
            HStack(spacing: 2) { actions() }
        } else if item.isConcealed, let expiresAt = item.concealedExpiresAt, expiresAt < .distantFuture {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                Text("clears in \(Self.countdown(until: expiresAt, now: context.date))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(Theme.warning)
            }
        } else {
            TimelineView(.periodic(from: Date(), by: 30)) { context in
                Text(ClipAge.short(from: item.date, now: context.date))
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .primary.opacity(0.7) : .secondary)
            }
        }
    }

    /// The arrow keys select a row, so the selected row shows the same actions as a hovered row.
    static func showsActions(isHovered: Bool, isSelected: Bool) -> Bool {
        isHovered || isSelected
    }

    private var showsActions: Bool {
        Self.showsActions(isHovered: isHovered, isSelected: isSelected)
    }

    static func countdown(until date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @ViewBuilder
    private var rowActions: some View {
        if let onPreview {
            RowActionButton(label: "Preview (space)", systemImage: "eye") { onPreview(item) }
        }
        if item.isConcealed {
            RowActionButton(label: "Show for 5 Seconds (\u{2318}U)", systemImage: "lock.open", action: reveal)
        }
        switch item.content {
        case .url(let url):
            RowActionButton(label: "Open Link (\u{2318}O)", systemImage: "arrow.up.right") { openLink(url) }
        case .file:
            RowActionButton(label: "Reveal in Finder (\u{2318}R)", systemImage: "folder") { onRevealInFinder?(item) }
        default:
            EmptyView()
        }
        if ClipEdit.canEdit(item.content), let onEdit {
            RowActionButton(label: "Edit (\u{2318}E)", systemImage: "pencil") { onEdit(item) }
        }
        RowActionButton(label: "Delete (\u{2318}\u{232B})", systemImage: "trash", action: onRemove)
    }

    /// Image actions float on the image, so the image keeps its full width.
    private var imageActions: some View {
        HStack(spacing: 0) {
            if let onPreview {
                RowActionButton(label: "Preview (space)", systemImage: "eye", tint: .primary) { onPreview(item) }
            }
            if item.isConcealed {
                RowActionButton(label: "Show for 5 Seconds (\u{2318}U)", systemImage: "lock.open", tint: .primary, action: reveal)
            }
            if let onExtractText {
                RowActionButton(label: "Extract Text (\u{2318}T)", systemImage: "text.viewfinder", tint: .primary) { onExtractText(item) }
            }
            if let onExtractBarcode {
                RowActionButton(label: "Extract Code (\u{2318}B)", systemImage: "qrcode.viewfinder", tint: .primary) { onExtractBarcode(item) }
            }
            if let onEditImage {
                RowActionButton(label: "Edit Image (\u{2318}E)", systemImage: "pencil", tint: .primary) { onEditImage(item) }
            }
            RowActionButton(label: "Delete (\u{2318}\u{232B})", systemImage: "trash", tint: .primary, action: onRemove)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        )
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
}

// MARK: - Image preview

/// A wide image fills the row width at 132 pt high, cut at the bottom. A square or tall
/// image keeps its shape at 112 pt high.
private struct ImagePreview: View {
    let imgContent: ImageContent
    let isConcealed: Bool
    var loadImageData: ((URL) -> Data?)?

    @State private var loadedImage: NSImage? = nil
    // ponytail: rows are keyed by index and keep @State across content changes,
    // so remember which file the cache came from. An edit (new .enc URL) or a
    // shifted row then reloads instead of showing the previous image.
    @State private var loadedURL: URL? = nil

    var body: some View {
        Group {
            if let image = effectiveImage {
                let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
                if aspect >= 1.2 {
                    // A clear box sets the size. The image fills it from the top, and the box
                    // clips it, so a very wide image cannot make the row wider.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.imageHeight)
                        .overlay(alignment: .top) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line, lineWidth: 1))
                        .overlay { concealedCover }
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 112 * aspect, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line, lineWidth: 1))
                        .overlay { concealedCover }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.tileFill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .overlay(ProgressView().controlSize(.small))
                    .task {
                        if case .file(let url) = imgContent.source,
                           let data = loadImageData?(url), let img = NSImage(data: data) {
                            loadedImage = img
                            loadedURL = url
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var concealedCover: some View {
        if isConcealed {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThickMaterial)
                .overlay(Image(systemName: "lock.fill").font(.system(size: 22, weight: .semibold)).foregroundColor(Theme.warning))
        }
    }

    // Use memory image if available, otherwise use loaded image
    private var effectiveImage: NSImage? {
        switch imgContent.source {
        case .memory(let img):
            return img
        case .file(let url):
            return loadedURL == url ? loadedImage : nil
        }
    }
}

private enum ColorParser {
    static func color(fromHex hex: String) -> Color? {
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
