MacClipboard (SwiftUI)
======================

A simple macOS clipboard history app built with SwiftUI.

Features
- Captures copied text and images
- Global hotkey Command+Control+V to toggle a floating window
- Click any entry to copy it back to the pasteboard

Build & Run
1. Ensure you have Xcode and Homebrew installed.
2. Install XcodeGen if needed and generate the Xcode project:

   ```bash
   brew list xcodegen >/dev/null 2>&1 || brew install xcodegen
   xcodegen generate
   open MacClipboard.xcodeproj
   ```

3. Select the "MacClipboard" scheme and run.

Notes
- The app uses Carbon's RegisterEventHotKey API, so no special permissions are required for the global hotkey.
- The app is not sandboxed and is intended for personal use/development. For Mac App Store distribution, additional work is required.

