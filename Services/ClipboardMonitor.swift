import Foundation
import Cocoa
import Combine

protocol ClipboardMonitorProtocol {
    var itemPublisher: AnyPublisher<ClipboardItem, Never> { get }
    func start()
    func stop()
}

final class ClipboardMonitor: ClipboardMonitorProtocol {
    private let subject = PassthroughSubject<ClipboardItem, Never>()
    var itemPublisher: AnyPublisher<ClipboardItem, Never> { subject.eraseToAnyPublisher() }

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pollPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Prefer image, then URL, then text
        if let image = readImage(from: pb) {
            let imgContent = ImageContent(image: image, cachedText: nil, cachedId: nil, cachedBarcode: nil)
            subject.send(ClipboardItem(date: Date(), content: .image(imgContent)))
            return
        }

        if let url = readURL(from: pb) {
            subject.send(ClipboardItem(date: Date(), content: .url(url)))
            return
        }

        if let text = readText(from: pb) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let detected = URLUtils.linkURL(from: trimmed) {
                subject.send(ClipboardItem(date: Date(), content: .url(detected)))
            } else {
                subject.send(ClipboardItem(date: Date(), content: .text(text)))
            }
        }
    }

    private func readText(from pasteboard: NSPasteboard) -> String? {
        if let items = pasteboard.pasteboardItems, !items.isEmpty {
            let item = items[0]
            if let str = item.string(forType: .string) { return str }
        }
        return nil
    }

    private func readURL(from pasteboard: NSPasteboard) -> URL? {
        if let objs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let url = objs.first {
            return url
        }
        if let items = pasteboard.pasteboardItems, let item = items.first {
            if let s = item.string(forType: .URL), let url = URL(string: s) { return url }
            // Some apps use public.url
            if let s = item.string(forType: NSPasteboard.PasteboardType("public.url")), let url = URL(string: s) { return url }
        }
        return nil
    }

    private func readImage(from pasteboard: NSPasteboard) -> NSImage? {
        // Try robust Cocoa reading first
        if let objs = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img = objs.first {
            return img
        }
        // Fallback: inspect first pasteboard item data for common image types
        if let items = pasteboard.pasteboardItems, let item = items.first {
            if let data = item.data(forType: .tiff), let image = NSImage(data: data) {
                return image
            }
            if let data = item.data(forType: .png), let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }
}