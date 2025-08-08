MaClip (SwiftUI)
================

<p align="center">
  <!-- Inline SVG icon to match the Info window app icon -->
  <svg width="160" height="160" viewBox="0 0 160 160" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="MaClip icon">
    <defs>
      <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0%" stop-color="#3B82F6"/>
        <stop offset="100%" stop-color="#A855F7"/>
      </linearGradient>
    </defs>
    <!-- Outer rounded square with gradient and drop shadow hint -->
    <rect x="8" y="8" width="144" height="144" rx="28" fill="url(#g)"/>
    <!-- Inner subtle border -->
    <rect x="16" y="16" width="128" height="128" rx="24" fill="none" stroke="rgba(255,255,255,0.25)" stroke-width="2"/>
    <!-- Clipboard glyph (simplified) -->
    <g fill="#FFFFFF">
      <!-- Clip/top tab -->
      <rect x="64" y="36" width="32" height="16" rx="6"/>
      <!-- Paper/body -->
      <rect x="44" y="52" width="72" height="80" rx="10"/>
      <!-- Lines to hint content -->
      <rect x="56" y="72" width="48" height="6" rx="3" opacity="0.75"/>
      <rect x="56" y="88" width="48" height="6" rx="3" opacity="0.75"/>
      <rect x="56" y="104" width="36" height="6" rx="3" opacity="0.75"/>
    </g>
  </svg>
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

