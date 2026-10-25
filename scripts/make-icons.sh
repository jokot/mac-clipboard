#!/usr/bin/env bash
# Usage: scripts/make-icons.sh
#
# Run from the repo root on macOS. Makes the app icon and the menu bar icon
# from the SVG files in assets/icon/:
#   icon.svg     -> App/AppIcon.icns, all sizes from 16 px to 1024 px
#   menubar.svg  -> App/MenuBarIcon.png (18 px) and App/MenuBarIcon@2x.png (36 px)
set -euo pipefail

render() { swift scripts/render-svg.swift "$1" "$2" "$3"; }

set_dir="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$set_dir"
for size in 16 32 128 256 512; do
    render assets/icon/icon.svg "$set_dir/icon_${size}x${size}.png" "$size"
    render assets/icon/icon.svg "$set_dir/icon_${size}x${size}@2x.png" "$((size * 2))"
done
iconutil -c icns "$set_dir" -o App/AppIcon.icns

render assets/icon/menubar.svg App/MenuBarIcon.png 18
render assets/icon/menubar.svg App/MenuBarIcon@2x.png 36
echo "wrote App/AppIcon.icns, App/MenuBarIcon.png and App/MenuBarIcon@2x.png"
