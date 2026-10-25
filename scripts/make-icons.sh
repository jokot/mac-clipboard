#!/usr/bin/env bash
# Usage: scripts/make-icons.sh
#
# Run from the repo root on macOS. Makes the app icon and the menu bar icon
# from the SVG files in assets/icon/:
#   icon.svg        -> App/AppIcon.icns, sizes 64 px and larger
#   icon-small.svg  -> App/AppIcon.icns, 16 px and 32 px (fewer loops, thicker wire)
#   menubar.svg     -> App/MenuBarIcon.png (18 px) and App/MenuBarIcon@2x.png (36 px)
set -euo pipefail

render() { swift scripts/render-svg.swift "$1" "$2" "$3"; }

set_dir="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$set_dir"
render assets/icon/icon-small.svg "$set_dir/icon_16x16.png" 16
render assets/icon/icon-small.svg "$set_dir/icon_16x16@2x.png" 32
render assets/icon/icon-small.svg "$set_dir/icon_32x32.png" 32
render assets/icon/icon.svg "$set_dir/icon_32x32@2x.png" 64
for size in 128 256 512; do
    render assets/icon/icon.svg "$set_dir/icon_${size}x${size}.png" "$size"
    render assets/icon/icon.svg "$set_dir/icon_${size}x${size}@2x.png" "$((size * 2))"
done
iconutil -c icns "$set_dir" -o App/AppIcon.icns

render assets/icon/menubar.svg App/MenuBarIcon.png 18
render assets/icon/menubar.svg App/MenuBarIcon@2x.png 36
echo "wrote App/AppIcon.icns, App/MenuBarIcon.png and App/MenuBarIcon@2x.png"
