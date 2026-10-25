#!/usr/bin/env bash
# Usage: scripts/release/build-dmg.sh <version>
#
# Run from the repo root. Builds MaClip.app (Release, ad-hoc signature) into
# build/, then writes dist/MacClip-<version>.dmg and its .sha256 file.
# Fails before packaging when the built app version is not <version>.
set -euo pipefail

version="${1:?usage: build-dmg.sh <version>}"
app="build/Release/MaClip.app"
dmg="dist/MacClip-$version.dmg"

xcodebuild -scheme MacClipboard -project MacClipboard.xcodeproj -configuration Release \
    BUILD_DIR="$(pwd)/build" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    clean build

app_version="$(defaults read "$(pwd)/$app/Contents/Info" CFBundleShortVersionString)"
if [ "$app_version" != "$version" ]; then
    echo "error: app version $app_version does not match $version"
    exit 1
fi

command -v create-dmg >/dev/null || brew install create-dmg
mkdir -p dist
rm -f "$dmg" "$dmg.sha256"

# The background shows the install and "Open Anyway" steps. Its layout
# matches these positions. Make it again with:
#   swift scripts/release/make-dmg-background.swift <dir>
#   tiffutil -cathidpicheck <dir>/dmg-background.png <dir>/dmg-background@2x.png \
#     -out assets/dmg-background.tiff
# Finder shows .background and .VolumeIcon.icns when "show hidden files" is
# on (Command-Shift-Period). Without a position, Finder puts them on top of
# the steps. These positions are below the 440 pt background.
layout=(--volname "MaClip" --volicon "App/AppIcon.icns"
    --background "assets/dmg-background.tiff"
    --window-pos 200 120 --window-size 600 500 --icon-size 96 --text-size 12
    --icon "MaClip.app" 150 140 --app-drop-link 450 140
    --icon ".background" 150 620 --icon ".VolumeIcon.icns" 450 620 --format UDZO)

# The Finder layout step uses AppleScript, which can fail or time out on a
# CI runner. Try one more time. A DMG without the layout does not show the
# install steps, so there is no fallback without it.
if ! create-dmg "${layout[@]}" "$dmg" "$app"; then
    echo "warning: create-dmg failed, trying again"
    rm -f "$dmg" dist/rw.*.dmg
    create-dmg "${layout[@]}" "$dmg" "$app"
fi

# Make sure that Finder saved every position.
mnt="$(mktemp -d)"
hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$dmg" >/dev/null
if ! python3 scripts/release/check-dmg-layout.py "$mnt/.DS_Store" \
    "MaClip.app=150,140" "Applications=450,140" ".background=150,620" ".VolumeIcon.icns=450,620"; then
    hdiutil detach -quiet "$mnt"
    rm -f "$dmg"
    echo "error: the DMG window layout is not correct"
    exit 1
fi
hdiutil detach -quiet "$mnt"

# Base name only, so `shasum -a 256 -c` works in the download folder.
(cd dist && shasum -a 256 "MacClip-$version.dmg" > "MacClip-$version.dmg.sha256")
echo "built $dmg"
