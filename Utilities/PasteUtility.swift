import Cocoa
import Carbon.HIToolbox

/// Utility for synthesizing paste keystrokes
@MainActor
struct PasteUtility {
    /// Synthesizes Command+V to paste content in the focused app
    static func sendPasteKeystroke() {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyV = CGKeyCode(kVK_ANSI_V)
        
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: true)
        keyDown?.flags = .maskCommand
        
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: false)
        keyUp?.flags = .maskCommand
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}