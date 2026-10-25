import SwiftUI
import AppKit

/// The app icon from AppIcon.icns, so the About window matches the Dock and Finder.
struct AppIconView: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("MaClip icon")
    }
}
