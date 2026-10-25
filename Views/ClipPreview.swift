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

/// The panel beside the clip window that shows one clip in full. Space opens and closes it.
struct ClipPreviewView: View {
    let item: ClipboardItem
    var loadImageData: (URL) -> Data?
    let onPaste: () -> Void
    let onCopyOnly: () -> Void
    let onEdit: () -> Void
    let onClose: () -> Void

    @State private var image: NSImage?
    @State private var isRevealed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
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

            body(for: item)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 8) {
                Button("Edit\u{2026}", action: onEdit)
                Button("Copy Only", action: onCopyOnly)
                Spacer()
                Button("Paste", action: onPaste)
                    .buttonStyle(AccentButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 408)
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: item.id) { _ in
            image = nil
            isRevealed = false
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
