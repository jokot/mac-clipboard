import Cocoa
import Carbon.HIToolbox

final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    func registerCommandControlV() {
        register(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | cmdKey))
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        var hotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: "MCLP".utf8.reduce(0) { ($0 << 8) | UInt32($1) })), id: UInt32(1))

        let eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(GetEventDispatcherTarget(), { (_, eventRef, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if status == noErr {
                if hotKeyID.id == 1 {
                    GlobalHotKeyManager.shared.onPressed?()
                }
            }
            return noErr
        }, 1, [eventSpec], nil, &eventHandlerRef)

        guard status == noErr else {
            NSLog("Failed to install hotkey event handler: \(status)")
            return
        }

        let regStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if regStatus != noErr {
            NSLog("Failed to register hotkey: \(regStatus)")
        }
    }
}

