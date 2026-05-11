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
}

struct ClipboardItem: Identifiable {
    let id: UUID
    let date: Date
    let content: ClipboardItemContent
    let sourceBundleID: String?
    let isConcealed: Bool
    let concealedExpiresAt: Date?

    init(id: UUID = UUID(),
         date: Date,
         content: ClipboardItemContent,
         sourceBundleID: String? = nil,
         isConcealed: Bool = false,
         concealedExpiresAt: Date? = nil) {
        self.id = id
        self.date = date
        self.content = content
        self.sourceBundleID = sourceBundleID
        self.isConcealed = isConcealed
        self.concealedExpiresAt = concealedExpiresAt
    }
}

extension ClipboardItem: Equatable {
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        if lhs.id == rhs.id { return true }
        
        switch (lhs.content, rhs.content) {
        case let (.text(a), .text(b)):
            return a == b
        case let (.image(a), .image(b)):
            switch (a.source, b.source) {
            case let (.file(urlA), .file(urlB)):
                return urlA == urlB
            case let (.memory(imgA), .memory(imgB)):
                // Fallback to object identity to avoid expensive data comparison
                return imgA === imgB
            default:
                return false
            }
        case let (.url(a), .url(b)):
            return a.absoluteString == b.absoluteString
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