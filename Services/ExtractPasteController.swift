import Cocoa
import Combine
import Carbon.HIToolbox

enum ExtractKind {
    case text
    case code
}

enum ExtractOutcome: Equatable {
    case pasted
    /// No Accessibility access: the result is on the clipboard, and the user pastes it.
    case copiedOnly
    case noImage
    case notFound
    case failed
}

/// A short message near the bottom of the screen. It never takes focus.
struct ExtractToast {
    let message: String
    let image: NSImage?
    let isProgress: Bool
}

@MainActor
protocol ExtractToastPresenting: AnyObject {
    func show(_ toast: ExtractToast)
    func hide()
}

@MainActor
protocol AccessibilityChecking: AnyObject {
    func isGrantedNow() -> Bool
    func shouldAskBeforePaste() -> Bool
    func showPrompt()
}

struct PasteboardSnapshot {
    /// One entry for each pasteboard item: the data for each type.
    let items: [[NSPasteboard.PasteboardType: Data]]
    let changeCount: Int
}

@MainActor
protocol PasteboardSwapping: AnyObject {
    func snapshot() -> PasteboardSnapshot
    /// Puts the clip on the pasteboard. Returns the pasteboard change count after the write.
    func write(_ item: ClipboardItem) -> Int
    /// Puts the snapshot back, but only when nothing else changed the pasteboard
    /// after `changeCount`.
    func restore(_ snapshot: PasteboardSnapshot, ifChangeCountIs changeCount: Int)
}

/// Pastes the text or the QR code from the newest image clip into the frontmost app.
/// The shortcuts in Settings > General start it. MaClip does not open.
@MainActor
final class ExtractPasteController {
    private let viewModel: ClipboardListViewModel
    private let ocr: OCRServiceProtocol
    private let toast: ExtractToastPresenting
    private let accessibility: AccessibilityChecking
    private let pasteboard: PasteboardSwapping
    private let sendPaste: () async -> Void
    private let restoreDelay: TimeInterval
    private let progressDelay: TimeInterval
    private var isRunning = false

    init(viewModel: ClipboardListViewModel,
         ocr: OCRServiceProtocol,
         toast: ExtractToastPresenting,
         accessibility: AccessibilityChecking,
         pasteboard: PasteboardSwapping,
         sendPaste: @escaping () async -> Void,
         restoreDelay: TimeInterval = 0.5,
         progressDelay: TimeInterval = 0.3) {
        self.viewModel = viewModel
        self.ocr = ocr
        self.toast = toast
        self.accessibility = accessibility
        self.pasteboard = pasteboard
        self.sendPaste = sendPaste
        self.restoreDelay = restoreDelay
        self.progressDelay = progressDelay
    }

    @discardableResult
    func run(_ kind: ExtractKind) async -> ExtractOutcome {
        // A second press while a scan runs does nothing.
        guard !isRunning else { return .failed }
        isRunning = true
        defer { isRunning = false }

        guard let item = viewModel.latestImageItem,
              case .image(let content) = item.content else {
            NSSound.beep()
            toast.show(ExtractToast(message: "No image to read. Take a screenshot first (\u{2303}\u{21E7}\u{2318}4).",
                                    image: nil, isProgress: false))
            return .noImage
        }
        let image = loadImage(content)

        let result: String
        switch cached(kind, in: content) {
        case .some(let value) where value.isEmpty:
            return notFound(kind, image: image)
        case .some(let value):
            result = value
        case .none:
            guard let image else { return failed(image: nil) }
            switch await scan(kind, image: image) {
            case .found(let value):
                remember(value, kind: kind, on: item)
                result = value
            case .notFound:
                remember("", kind: kind, on: item)
                return notFound(kind, image: image)
            case .failed:
                return failed(image: image)
            }
        }

        let resultItem = viewModel.promoteOrInsertResult(text: result, sourceBundleID: item.sourceBundleID,
                                                         isOCRResult: true)
        let before = pasteboard.snapshot()
        let changeCount = pasteboard.write(resultItem)

        guard accessibility.isGrantedNow() else {
            toast.show(ExtractToast(message: "Text copied. Press \u{2318}V.", image: image, isProgress: false))
            if accessibility.shouldAskBeforePaste() { accessibility.showPrompt() }
            return .copiedOnly
        }

        await sendPaste()
        // Give the frontmost app time to read the clipboard, then put the image back,
        // so Command-V pastes the screenshot again.
        if restoreDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(restoreDelay * 1_000_000_000))
        }
        pasteboard.restore(before, ifChangeCountIs: changeCount)
        return .pasted
    }

    // MARK: - Steps

    private enum ScanResult {
        case found(String)
        case notFound
        case failed
    }

    private func cached(_ kind: ExtractKind, in content: ImageContent) -> String? {
        let value = kind == .text ? content.cachedText : content.cachedBarcode
        return value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scan(_ kind: ExtractKind, image: NSImage) async -> ScanResult {
        let progress = Task { @MainActor [toast, progressDelay] in
            try await Task.sleep(nanoseconds: UInt64(progressDelay * 1_000_000_000))
            toast.show(ExtractToast(message: kind == .text ? "Reading text\u{2026}" : "Reading code\u{2026}",
                                    image: image, isProgress: true))
            return true
        }
        defer { progress.cancel() }

        let outcome: ScanResult
        do {
            let value = kind == .text ? try await ocr.extractText(from: image)
                                      : try await ocr.extractBarcode(from: image)
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            outcome = trimmed.isEmpty ? .notFound : .found(trimmed)
        } catch OCRService.OCRError.noTextFound, OCRService.OCRError.noBarcodeFound {
            outcome = .notFound
        } catch {
            NSLog("[MaClip] extract failed: \(error)")
            outcome = .failed
        }
        progress.cancel()
        if (try? await progress.value) == true { toast.hide() }
        return outcome
    }

    private func remember(_ value: String, kind: ExtractKind, on item: ClipboardItem) {
        if kind == .text {
            viewModel.updateImageItemCache(item, cachedText: value, cachedId: value.isEmpty ? nil : value, cachedBarcode: nil)
        } else {
            viewModel.updateImageItemCache(item, cachedText: nil, cachedId: value.isEmpty ? nil : value, cachedBarcode: value)
        }
    }

    private func notFound(_ kind: ExtractKind, image: NSImage?) -> ExtractOutcome {
        NSSound.beep()
        toast.show(ExtractToast(message: kind == .text ? "No text found in the last image"
                                                       : "No QR code or barcode found in the last image",
                                image: image, isProgress: false))
        return .notFound
    }

    private func failed(image: NSImage?) -> ExtractOutcome {
        NSSound.beep()
        toast.show(ExtractToast(message: "MaClip could not read the last image", image: image, isProgress: false))
        return .failed
    }

    private func loadImage(_ content: ImageContent) -> NSImage? {
        switch content.source {
        case .memory(let image): return image
        case .file(let url): return viewModel.imageData(at: url).flatMap(NSImage.init(data:))
        }
    }
}

// MARK: - System implementations

extension AccessibilityAccess: AccessibilityChecking {
    func showPrompt() {
        AccessibilityPromptWindowController.shared.show(afterCopy: true)
    }
}

@MainActor
final class SystemPasteboardSwapper: PasteboardSwapping {
    private let viewModel: ClipboardListViewModel

    init(viewModel: ClipboardListViewModel) {
        self.viewModel = viewModel
    }

    func snapshot() -> PasteboardSnapshot {
        let pb = NSPasteboard.general
        let items = (pb.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let value = item.data(forType: type) { data[type] = value }
            }
            return data
        }
        return PasteboardSnapshot(items: items, changeCount: pb.changeCount)
    }

    func write(_ item: ClipboardItem) -> Int {
        viewModel.setPasteboard(to: item)
        return NSPasteboard.general.changeCount
    }

    func restore(_ snapshot: PasteboardSnapshot, ifChangeCountIs changeCount: Int) {
        let pb = NSPasteboard.general
        // The user copied something else in the meantime. Keep it.
        guard pb.changeCount == changeCount, !snapshot.items.isEmpty else { return }
        pb.clearContents()
        let items: [NSPasteboardItem] = snapshot.items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(items)
        viewModel.ignorePasteboardChange()
    }
}

/// Registers the two extract shortcuts and registers them again when Settings change.
@MainActor
final class ExtractHotkeys {
    private let controller: ExtractPasteController
    private var cancellable: AnyCancellable?

    init(controller: ExtractPasteController, settings: AppSettings = .shared) {
        self.controller = controller
        register(settings)
        // objectWillChange fires before the value changes, so read it on the next pass.
        cancellable = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.register(settings) }
    }

    private func register(_ s: AppSettings) {
        let service = HotKeyService.shared
        if s.extractTextHotkeyEnabled {
            service.register(.extractText, keyCode: s.extractTextKeyCode, modifiers: s.extractTextModifiers) { [weak self] in
                Task { @MainActor in await self?.controller.run(.text) }
            }
        } else {
            service.unregister(.extractText)
        }
        if s.extractCodeHotkeyEnabled {
            service.register(.extractCode, keyCode: s.extractCodeKeyCode, modifiers: s.extractCodeModifiers) { [weak self] in
                Task { @MainActor in await self?.controller.run(.code) }
            }
        } else {
            service.unregister(.extractCode)
        }
    }
}

@MainActor
enum ExtractPaste {
    /// Waits until the user releases the shortcut keys, then sends Command-V.
    /// With Control or Option still down, some apps do not paste.
    static func sendPasteAfterKeysUp() async {
        let held: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        for _ in 0..<40 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(held).isEmpty { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        PasteUtility.sendPasteKeystroke()
    }
}
