import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeyCapturingView: NSViewRepresentable {
    @Binding var isCapturing: Bool
    let onCaptured: (UInt32, UInt32) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = HotkeyView()
        view.onHotkeyCaptured = onCaptured
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let hotkeyView = nsView as? HotkeyView {
            hotkeyView.isCapturing = isCapturing
        }
    }
}

class HotkeyView: NSView {
    var isCapturing = false {
        didSet {
            if isCapturing {
                window?.makeFirstResponder(self)
            }
        }
    }
    
    var onHotkeyCaptured: ((UInt32, UInt32) -> Void)?
    
    override var acceptsFirstResponder: Bool { isCapturing }
    
    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }
        
        // Don't capture single modifier keys or escape
        if event.keyCode == 53 { // Escape
            isCapturing = false
            return
        }
        
        let modifiers = event.modifierFlags
        var carbonModifiers: UInt32 = 0
        
        if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        
        // Require at least one modifier
        guard carbonModifiers != 0 else {
            NSSound.beep()
            return
        }
        
        onHotkeyCaptured?(UInt32(event.keyCode), carbonModifiers)
    }
}