import Foundation

// Centralized Notification.Name definitions used across the app
extension Notification.Name {
    // Overlay events
    static let overlayCloseRequested = Notification.Name("OverlayCloseRequested")
    static let overlayMoveSelectionUp = Notification.Name("OverlayMoveSelectionUp")
    static let overlayMoveSelectionDown = Notification.Name("OverlayMoveSelectionDown")
    static let overlaySelectCurrentItem = Notification.Name("OverlaySelectCurrentItem")
    static let overlayDidShow = Notification.Name("OverlayDidShow")
    static let overlayOpenSettings = Notification.Name("OverlayOpenSettings")
    static let overlayFocusSearch = Notification.Name("OverlayFocusSearch")
    /// Space in the clip window: open or close the preview of the selected clip.
    static let overlayTogglePreview = Notification.Name("OverlayTogglePreview")
    /// Command-Delete in the clip window: delete the selected clip.
    static let overlayDeleteSelectedItem = Notification.Name("OverlayDeleteSelectedItem")

    // Theme change
    static let themeChanged = Notification.Name("ThemeChanged")

    // Update service notifications
    static let updateServiceLastCheckedDidChange = Notification.Name("UpdateServiceLastCheckedDidChange")
}