import Cocoa

struct ImageContent {
    var image: NSImage
    var cachedText: String?
    var cachedId: String?
    var cachedBarcode: String?
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

    init(id: UUID = UUID(), date: Date, content: ClipboardItemContent) {
        self.id = id
        self.date = date
        self.content = content
    }
}

extension ClipboardItem: Equatable {
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        switch (lhs.content, rhs.content) {
        case let (.text(a), .text(b)):
            return a == b
        case let (.image(a), .image(b)):
            return a.image.pngData() == b.image.pngData()
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