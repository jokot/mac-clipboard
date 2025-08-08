MaClip (SwiftUI)
================

<p align="center">
  <img src="assets/maclip-icon.svg" alt="MaClip icon" width="160" height="160" />
</p>

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

3. Select the "MacClipboard" scheme and run. (Display name appears as "MaClip".)

Notes
- The app uses Carbon's RegisterEventHotKey API, so no special permissions are required for the global hotkey.
- The app is not sandboxed and is intended for personal use/development. For Mac App Store distribution, additional work is required.

Local release (DMG + checksum)
--------------------------------
To package a DMG and generate a SHA256 checksum for sharing (e.g., on GitHub Releases):

```bash
# 1) Build Release into ./build
xcodebuild -scheme MacClipboard -project MacClipboard.xcodeproj -configuration Release BUILD_DIR=$(pwd)/build clean build

# 2) Package DMG + checksum
VERSION=$(defaults read "$(pwd)/build/Release/MaClip.app/Contents/Info" CFBundleShortVersionString)
mkdir -p dist/vol && rm -rf dist/MaClip*.dmg dist/MaClip*.sha256 dist/vol/*
cp -R build/Release/MaClip.app dist/vol/
hdiutil create -volname "MaClip" -srcfolder dist/vol -ov -format UDZO "dist/MaClip-${VERSION}.dmg"
shasum -a 256 "dist/MaClip-${VERSION}.dmg" > "dist/MaClip-${VERSION}.dmg.sha256"
```

Notes:
- Bump the app version before building so `VERSION` updates.
- Unsigned binaries may trigger Gatekeeper on other Macs. For wide distribution, sign and notarize.

Verify checksum
----------------
Once you have a DMG and its `.sha256` file:

```bash
# Verify the DMG against the stored checksum
shasum -a 256 -c dist/MaClip-*.dmg.sha256

# Recompute and print the hash
shasum -a 256 dist/MaClip-*.dmg

# Show the stored hash
cat dist/MaClip-*.dmg.sha256
```

