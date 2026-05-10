import Cocoa
import Carbon.HIToolbox

/// Utility for synthesizing paste keystrokes
@MainActor
struct PasteUtility {
    /// Synthesizes Command+V to paste content in the focused app
    static func sendPasteKeystroke() {
        // .combinedSessionState + .cgAnnotatedSessionEventTap matches what shipping
        // clipboard managers (Maccy, Paste) use; survives apps that drop HID-level
        // synthetic events.
        let src = CGEventSource(stateID: .combinedSessionState)
        let keyV = CGKeyCode(kVK_ANSI_V)

        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        // Brief gap so the OS processes keyDown before keyUp.
        Thread.sleep(forTimeInterval: 0.05)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}