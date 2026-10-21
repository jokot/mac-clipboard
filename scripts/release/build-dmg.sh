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

layout=(--volname "MaClip" --volicon "App/AppIcon.icns"
    --window-pos 200 120 --window-size 540 360 --icon-size 96 --text-size 12
    --icon "MaClip.app" 140 150 --app-drop-link 400 150 --format UDZO)

# The Finder layout step uses AppleScript. On a CI runner it can fail or time
# out, so try once more without it (--skip-jenkins) before giving up.
if ! create-dmg "${layout[@]}" "$dmg" "$app"; then
    echo "warning: create-dmg failed, retrying without the Finder layout step"
    rm -f "$dmg" dist/rw.*.dmg
    create-dmg "${layout[@]}" --skip-jenkins "$dmg" "$app"
fi

# Base name only, so `shasum -a 256 -c` works in the download folder.
(cd dist && shasum -a 256 "MacClip-$version.dmg" > "MacClip-$version.dmg.sha256")
echo "built $dmg"
