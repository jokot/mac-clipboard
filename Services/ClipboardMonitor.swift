import Cocoa
import Combine

protocol ClipboardMonitorProtocol: AnyObject {
    var itemPublisher: AnyPublisher<ClipboardItem, Never> { get }
    func start()
    func stop()
}

final class ClipboardMonitor: ClipboardMonitorProtocol {
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var isSettingPasteboard = false
    private let subject = PassthroughSubject<ClipboardItem, Never>()

    var itemPublisher: AnyPublisher<ClipboardItem, Never> {
        subject.eraseToAnyPublisher()
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        if isSettingPasteboard {
            isSettingPasteboard = false
            lastChangeCount = currentChangeCount
            return
        }

        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        if let item = readCurrentPasteboardItem(from: pasteboard) {
            subject.send(item)
        }
    }

    private func readCurrentPasteboardItem(from pasteboard: NSPasteboard) -> ClipboardItem? {
        if let image = readImage(from: pasteboard) {
            return ClipboardItem(date: Date(), content: .image(image))
        }
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return ClipboardItem(date: Date(), content: .text(string))
        }
        return nil
    }

    private func readImage(from pasteboard: NSPasteboard) -> NSImage? {
        if let data = pasteboard.data(forType: .png), let image = NSImage(data: data) { return image }
        if let data = pasteboard.data(forType: .tiff), let image = NSImage(data: data) { return image }
        if let data = pasteboard.data(forType: .pdf), let image = NSImage(data: data) { return image }
        return nil
    }

    // Expose a method to mark self-triggered pasteboard writes if needed
    func markSettingPasteboard() {
        isSettingPasteboard = true
    }
}