import SwiftUI
import AppKit

/// The size line in the preview header: "214 words · 18 lines", "github.com", "3 files", "1440 × 900 px".
enum ClipPreviewInfo {
    static func detail(for item: ClipboardItem) -> String {
        switch item.content {
        case .text(let text):
            let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let lines = text.trimmingCharacters(in: .newlines)
                .split(separator: "\n", omittingEmptySubsequences: false).count
            return "\(plural(words, "word")) \u{00B7} \(plural(lines, "line"))"
        case .url(let url):
            return url.host ?? url.absoluteString
        case .file(let urls):
            return plural(urls.count, "file")
        case .image:
            return ""
        }
    }

    /// The size in pixels, not points: a Retina screenshot is two times its point size.
    static func detail(for image: NSImage) -> String {
        let rep = image.representations.first
        let width = rep?.pixelsWide ?? Int(image.size.width)
        let height = rep?.pixelsHigh ?? Int(image.size.height)
        return "\(width) \u{00D7} \(height) px"
    }

    static func time(of date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    private static func plural(_ n: Int, _ word: String) -> String {
        "\(n) \(word)\(n == 1 ? "" : "s")"
    }
}

/// The text in the editor for a text, link or file clip, and the clip that the edited text makes.
enum ClipEdit {
    enum Outcome {
        case save(ClipboardItemContent)
        /// The text does not make a clip of the same kind. The message tells why.
        case invalid(String)
    }

    static func canEdit(_ content: ClipboardItemContent) -> Bool {
        if case .image = content { return false }
        return true
    }

    /// A link as its address, files as one path on each line.
    static func text(for content: ClipboardItemContent) -> String {
        switch content {
        case .text(let s):  return s
        case .url(let u):   return u.absoluteString
        case .file(let us): return us.map(\.path).joined(separator: "\n")
        case .image:        return ""
        }
    }

    /// Text is saved as typed. A link must have a scheme and a host. Files need one path or more.
    static func outcome(of text: String, editing original: ClipboardItemContent) -> Outcome {
        switch original {
        case .text:
            return .save(.text(text))
        case .url:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let u = URL(string: trimmed),
                  let scheme = u.scheme, !scheme.isEmpty,
                  let host = u.host, !host.isEmpty else {
                return .invalid("Not a valid URL")
            }
            return .save(.url(u))
        case .file:
            let urls = text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0) }
            guard !urls.isEmpty else { return .invalid("Need at least one path") }
            return .save(.file(urls))
        case .image:
            return .invalid("Edit an image in the image editor")
        }
    }
}

/// The panel beside the clip window that shows one clip in full. Space opens and closes it.
/// In edit mode, the panel shows the clip in a text editor with Cancel and Save.
struct ClipPreviewView: View {
    let item: ClipboardItem
    @ObservedObject var windowState: ClipWindowState
    var loadImageData: (URL) -> Data?
    let onPaste: () -> Void
    let onCopyOnly: () -> Void
    let onEdit: () -> Void
    let onClose: () -> Void
    var isEditing: Bool = false
    var onSave: (ClipboardItemContent) -> Void = { _ in }
    var onCancelEdit: () -> Void = {}

    @State private var image: NSImage?
    @State private var isRevealed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if isFocused && !isEditing {
                    HStack(spacing: 5) {
                        KeyLabel(key: "\u{2190}")
                        Text("List")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(Theme.accent)
                    .help("Press \u{2190} to go back to the list")
                }
                SourceAppBadge(bundleID: item.sourceBundleID)
                Text(headerText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close the preview (space)")
                .accessibilityLabel("Close preview")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if isEditing && ClipEdit.canEdit(item.content) {
                // A new id for each clip, so the editor starts from the text of this clip.
                ClipEditorView(item: item, onCancel: onCancelEdit, onSave: onSave)
                    .id(item.id)
            } else {
                body(for: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HStack(spacing: 8) {
                    Button(action: onEdit) { buttonLabel("Edit\u{2026}", key: "\u{2318}E") }
                    Button(action: onCopyOnly) { buttonLabel("Copy Only", key: "\u{2318}C") }
                    Spacer()
                    Button(action: onPaste) { buttonLabel("Paste", key: "\u{21A9}", onAccent: true) }
                        .buttonStyle(AccentButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 408)
        .ignoresSafeArea(.container, edges: .top)
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .padding(3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .simultaneousGesture(TapGesture().onEnded { windowState.pane = .preview })
        .shortcutsPanel(.preview, title: isEditing ? "Editing a clip" : "Preview",
                        note: isEditing ? "While you edit, \u{2190} \u{2192} move the cursor."
                                        : "Every clip key of the list works here too.") {
            isEditing ? ClipKeyMap.editingColumns() : ClipKeyMap.previewColumns()
        }
        .onChange(of: item.id) { _ in
            image = nil
            isRevealed = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .overlayRevealItem)) { note in
            guard (note.object as? UUID) == item.id, item.isConcealed else { return }
            isRevealed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { isRevealed = false }
        }
    }

    private var isFocused: Bool { windowState.previewOpen && windowState.pane == .preview }

    private func buttonLabel(_ title: String, key: String, onAccent: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Text(key)
                .font(.system(size: 11))
                .foregroundColor(onAccent ? .white.opacity(0.75) : .secondary)
        }
    }

    private var headerText: String {
        var parts = [ClipPreviewInfo.time(of: item.date)]
        let detail: String
        if case .image = item.content {
            detail = image.map(ClipPreviewInfo.detail(for:)) ?? ""
        } else {
            detail = ClipPreviewInfo.detail(for: item)
        }
        if !detail.isEmpty, !(item.isConcealed && !isRevealed) { parts.append(detail) }
        return parts.joined(separator: " \u{00B7} ")
    }

    @ViewBuilder
    private func body(for item: ClipboardItem) -> some View {
        if item.isConcealed && !isRevealed {
            VStack(spacing: 10) {
                Image(systemName: "lock.fill").font(.system(size: 24)).foregroundColor(Theme.warning)
                Text("This clip is concealed").font(.headline)
                Button("Show for 5 Seconds") {
                    isRevealed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { isRevealed = false }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch item.content {
            case .text(let text):
                let tag = ContentTagDetector.primaryTag(for: item)
                let isCode = tag == .code || tag == .json || tag == .diff
                ScrollView {
                    Text(text)
                        .font(isCode ? .system(size: 12, design: .monospaced) : .body)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                }
            case .url(let url):
                VStack(alignment: .leading, spacing: 10) {
                    Text(url.absoluteString)
                        .foregroundColor(Theme.accent)
                        .textSelection(.enabled)
                    Button("Open Link") {
                        NSWorkspace.shared.open(url)
                        NotificationCenter.default.post(name: .overlayCloseRequested, object: nil)
                    }
                }
                .padding(.horizontal, 18)
            case .file(let urls):
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(urls, id: \.self) { url in
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(url.path)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }
            case .image(let content):
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .task(id: item.id) { image = load(content) }
            }
        }
    }

    private func load(_ content: ImageContent) -> NSImage? {
        switch content.source {
        case .memory(let image): return image
        case .file(let url): return loadImageData(url).flatMap(NSImage.init(data:))
        }
    }
}

/// The edit mode of the preview panel. Esc cancels. Command-Return and Command-S save.
private struct ClipEditorView: View {
    let item: ClipboardItem
    let onCancel: () -> Void
    let onSave: (ClipboardItemContent) -> Void

    @State private var text: String
    @State private var error: String?

    init(item: ClipboardItem, onCancel: @escaping () -> Void, onSave: @escaping (ClipboardItemContent) -> Void) {
        self.item = item
        self.onCancel = onCancel
        self.onSave = onSave
        _text = State(initialValue: ClipEdit.text(for: item.content))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text)
                .font(isCode ? .system(size: 12, design: .monospaced) : .body)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.accent, lineWidth: 1))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            HStack(spacing: 8) {
                Text("esc cancels \u{00B7} \u{2318}\u{21A9} or \u{2318}S saves")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: save)
                    .buttonStyle(AccentButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        // The clip window key handler sends Esc, ⌘↩ and ⌘S here, so the shortcuts panel can take Esc first.
        .onAppear { prepareTextView() }
        .onReceive(NotificationCenter.default.publisher(for: .previewEditCommand)) { note in
            switch note.object as? PreviewEditAction {
            case .save: save()
            case .cancel: onCancel()
            case nil: break
            }
        }
    }

    private var isCode: Bool {
        let tag = ContentTagDetector.primaryTag(for: item)
        return tag == .code || tag == .json || tag == .diff
    }

    private func save() {
        switch ClipEdit.outcome(of: text, editing: item.content) {
        case .save(let content): onSave(content)
        case .invalid(let message): error = message
        }
    }

    // ponytail: TextEditor's NSTextView is not in the view tree at onAppear, so wait one
    // tick. Then put the cursor in it, and turn off smart quotes and dashes, so a JSON
    // edit keeps its quotes. The panel is the key window by then.
    private func prepareTextView() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow, let root = window.contentView,
                  let textView = Self.findTextView(in: root) else { return }
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.smartInsertDeleteEnabled = false
            window.makeFirstResponder(textView)
        }
    }

    private static func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView, textView.isEditable { return textView }
        for sub in view.subviews {
            if let found = findTextView(in: sub) { return found }
        }
        return nil
    }
}
