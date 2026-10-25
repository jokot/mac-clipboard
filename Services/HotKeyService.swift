import Cocoa
import Carbon.HIToolbox

protocol HotKeyServiceProtocol: AnyObject {
    var onPressed: (() -> Void)? { get set }
    func register(keyCode: UInt32, modifiers: UInt32)
    func unregister()
}

final class HotKeyService: HotKeyServiceProtocol {
    static let shared = HotKeyService()

    /// Shortcut IDs. 1 opens the clip window.
    enum ID: UInt32 {
        case overlay = 1
        case extractText = 2
        case extractCode = 3
    }

    var onPressed: (() -> Void)?

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    func register(keyCode: UInt32, modifiers: UInt32) {
        register(.overlay, keyCode: keyCode, modifiers: modifiers) { [weak self] in self?.onPressed?() }
    }

    func unregister() {
        unregister(.overlay)
    }

    /// Returns false when macOS does not register the shortcut, for example
    /// because another app uses it.
    @discardableResult
    func register(_ id: ID, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        unregister(id)
        guard installEventHandlerIfNeeded() else { return false }

        let signature = OSType(UInt32(truncatingIfNeeded: "MCLP".utf8.reduce(0) { ($0 << 8) | UInt32($1) }))
        let hotKeyID = EventHotKeyID(signature: signature, id: id.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Failed to register hotkey \(id): \(status)")
            return false
        }
        hotKeyRefs[id.rawValue] = ref
        handlers[id.rawValue] = handler
        return true
    }

    func unregister(_ id: ID) {
        if let ref = hotKeyRefs.removeValue(forKey: id.rawValue) {
            UnregisterEventHotKey(ref)
        }
        handlers[id.rawValue] = nil
    }

    private func installEventHandlerIfNeeded() -> Bool {
        if eventHandlerRef != nil { return true }
        let eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetEventDispatcherTarget(), { (_, eventRef, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if status == noErr {
                HotKeyService.shared.handlers[hotKeyID.id]?()
            }
            return noErr
        }, 1, [eventSpec], nil, &eventHandlerRef)

        guard status == noErr else {
            NSLog("Failed to install hotkey event handler: \(status)")
            return false
        }
        return true
    }
}
