import SwiftUI
import AppKit

struct ESCKeyCatcher: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        view.onEscape = {
            // On Escape, close overlay immediately and refocus previous app (no paste)
            NotificationCenter.default.post(name: .overlayCloseRequested, object: nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class KeyCatcherView: NSView {
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
            case 53: // Escape
                // Close overlay immediately and refocus previous app (no paste)
                NotificationCenter.default.post(name: .overlayCloseRequested, object: nil)
            case 126: // Arrow Up
                NotificationCenter.default.post(name: .overlayMoveSelectionUp, object: nil)
            case 125: // Arrow Down
                NotificationCenter.default.post(name: .overlayMoveSelectionDown, object: nil)
            case 36, 76: // Return or Keypad Enter
                NotificationCenter.default.post(name: .overlaySelectCurrentItem, object: nil)
            default:
                if event.modifierFlags.contains(.command), let chars = event.charactersIgnoringModifiers, chars == "," {
                    NotificationCenter.default.post(name: .overlayOpenSettings, object: nil)
                    return
                }
                super.keyDown(with: event)
        }
    }
}