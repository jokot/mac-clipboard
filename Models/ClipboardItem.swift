import Cocoa
import Foundation

enum ImageSource {
    case memory(NSImage)
    case file(URL)
}

struct ImageContent {
    var source: ImageSource
    var cachedText: String?
    var cachedId: String?
    var cachedBarcode: String?

    var image: NSImage? {
        switch source {
        case .memory(let img): return img
        case .file: return nil // explicit nil to force async loading logic in views
        }
    }
}

enum ClipboardItemContent {
    case text(String)
    case image(ImageContent)
    case url(URL)
    case file([URL])
}

struct ClipboardItem: Identifiable {
    let id: UUID
    let date: Date
    let content: ClipboardItemContent
    let sourceBundleID: String?
    let isConcealed: Bool
    let concealedExpiresAt: Date?
    let isOCRResult: Bool
    /// The kind of secret that MaClip found in the text. Nil for a normal clip.
    let secretKind: SecretKind?
    /// True after "Not a Secret". MaClip then does not hide the clip again.
    let secretDismissed: Bool

    init(id: UUID = UUID(),
         date: Date,
         content: ClipboardItemContent,
         sourceBundleID: String? = nil,
         isConcealed: Bool = false,
         concealedExpiresAt: Date? = nil,
         isOCRResult: Bool = false,
         secretKind: SecretKind? = nil,
         secretDismissed: Bool = false) {
        self.id = id
        self.date = date
        self.content = content
        self.sourceBundleID = sourceBundleID
        self.isConcealed = isConcealed
        self.concealedExpiresAt = concealedExpiresAt
        self.isOCRResult = isOCRResult
        self.secretKind = secretKind
        self.secretDismissed = secretDismissed
    }

    /// The same clip (id, date, source and all flags) with new content.
    func replacing(content newContent: ClipboardItemContent) -> ClipboardItem {
        ClipboardItem(id: id, date: date, content: newContent, sourceBundleID: sourceBundleID,
                      isConcealed: isConcealed, concealedExpiresAt: concealedExpiresAt,
                      isOCRResult: isOCRResult, secretKind: secretKind, secretDismissed: secretDismissed)
    }

    /// The same clip (id, date, content and source) with new concealed and secret flags.
    func marked(concealed: Bool, expiresAt: Date?, secretKind: SecretKind?, secretDismissed: Bool) -> ClipboardItem {
        ClipboardItem(id: id, date: date, content: content, sourceBundleID: sourceBundleID,
                      isConcealed: concealed, concealedExpiresAt: expiresAt,
                      isOCRResult: isOCRResult, secretKind: secretKind, secretDismissed: secretDismissed)
    }
}

extension ClipboardItem: Equatable {
    // ponytail: strict equality (id, content and the hide flags) so SwiftUI view diffing sees
    // edits and "Not a Secret". Content-only dedup (new capture matches existing clip) uses matchesContent(_:).
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        return lhs.id == rhs.id && lhs.matchesContent(rhs)
            && lhs.isConcealed == rhs.isConcealed && lhs.concealedExpiresAt == rhs.concealedExpiresAt
            && lhs.secretKind == rhs.secretKind && lhs.secretDismissed == rhs.secretDismissed
    }

    func matchesContent(_ other: ClipboardItem) -> Bool {
        switch (self.content, other.content) {
        case let (.text(a), .text(b)):
            return a == b
        case let (.image(a), .image(b)):
            switch (a.source, b.source) {
            case let (.file(urlA), .file(urlB)):
                return urlA == urlB
            case let (.memory(imgA), .memory(imgB)):
                return imgA === imgB
            default:
                return false
            }
        case let (.url(a), .url(b)):
            return a.absoluteString == b.absoluteString
        case let (.file(a), .file(b)):
            return a == b
        default:
            return false
        }
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}