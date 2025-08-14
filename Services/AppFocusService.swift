import Cocoa
import Carbon.HIToolbox

@MainActor
final class AppFocusService {
    static let shared = AppFocusService()
    
    private var activationObserver: Any?
    
    private init() {}
    
    /// Switch focus to the specified app and paste clipboard content
    func switchToAppAndPaste(_ app: NSRunningApplication) {
        cleanup() // Remove any previous observer
        
        let center = NSWorkspace.shared.notificationCenter
        let targetPID = app.processIdentifier
        
        // Listen for when the target app becomes active, then paste immediately
        activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            
            let runningApp: NSRunningApplication? = 
                (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication) ??
                (note.userInfo?["NSWorkspaceApplicationKey"] as? NSRunningApplication)
            
            if let runningApp = runningApp, runningApp.processIdentifier == targetPID {
                center.removeObserver(self.activationObserver as Any)
                self.activationObserver = nil
                self.sendPasteKeystroke()
            }
        }
        
        // Activate the target app
        app.activate(options: [.activateIgnoringOtherApps])
        
        // Fallback: if activation notification doesn't arrive within 200ms, paste anyway
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            if self.activationObserver != nil {
                center.removeObserver(self.activationObserver as Any)
                self.activationObserver = nil
                self.sendPasteKeystroke()
            }
        }
    }
    
    /// Switch focus to the specified app without pasting
    func switchToAppOnly(_ app: NSRunningApplication) {
        cleanup() // Remove any observers since we're not waiting for activation
        app.activate(options: [.activateIgnoringOtherApps])
    }
    
    /// Clean up any active observers
    func cleanup() {
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }
    }
    
    // MARK: - Private Methods
    
    private func sendPasteKeystroke() {
        // Synthesize Command+V to paste content in the focused app
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