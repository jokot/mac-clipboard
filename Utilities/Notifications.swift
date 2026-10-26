import Foundation

// Centralized Notification.Name definitions used across the app
extension Notification.Name {
    // Overlay events
    static let overlayCloseRequested = Notification.Name("OverlayCloseRequested")
    static let overlayDidShow = Notification.Name("OverlayDidShow")
    static let overlayFocusSearch = Notification.Name("OverlayFocusSearch")
    /// A key in the clip window for the selected clip. The object is the `ClipCommand`.
    static let overlayCommand = Notification.Name("OverlayCommand")
    /// ⌘U: show the concealed clip with this id (the object) for 5 seconds.
    static let overlayRevealItem = Notification.Name("OverlayRevealItem")
    /// A key in the edit mode of the preview. The object is the `PreviewEditAction`.
    static let previewEditCommand = Notification.Name("PreviewEditCommand")
    /// ⌘1 to ⌘4 in Settings. The object is the `SettingsTab`.
    static let settingsSelectTab = Notification.Name("SettingsSelectTab")
    /// ⌫ in Settings: remove the selected app from the list of apps that MaClip does not save from.
    static let settingsRemoveSelectedApp = Notification.Name("SettingsRemoveSelectedApp")

    // Theme change
    static let themeChanged = Notification.Name("ThemeChanged")

    // Update service notifications
    static let updateServiceLastCheckedDidChange = Notification.Name("UpdateServiceLastCheckedDidChange")
}

enum PreviewEditAction {
    case save, cancel
}
