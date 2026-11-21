#!/bin/bash
# Makes the app icon from the logo set's SVGs (app-icon-*.svg here): iconsets (PNG, 16–1024, @1x/@2x) and .icns for the light and the
# dark appearance, into ./build/. The launcher's build.sh does the light one itself for the app bundle; Track B's app takes these.
# An .icns holds one look. The dark appearance of a macOS 26 .icon needs Icon Composer (actool), which the Command Line Tools lack:
# AppIcon-dark.icns is the dark look for anything that can choose it, and the PNGs feed Icon Composer when it is at hand.
# Needs the Command Line Tools only (swift, iconutil).
set -euo pipefail
cd "$(dirname "$0")"
( cd ../../launcher && swift build --product LauncherChecks >/dev/null )
CHECKS="$(cd ../../launcher && swift build --show-bin-path)/LauncherChecks"
rm -rf build; mkdir -p build
"$CHECKS" --icon build/AppIcon.iconset
"$CHECKS" --icon-dark build/AppIcon-dark.iconset
iconutil -c icns -o build/AppIcon.icns build/AppIcon.iconset
iconutil -c icns -o build/AppIcon-dark.icns build/AppIcon-dark.iconset
echo "Made $PWD/build/AppIcon.icns and AppIcon-dark.icns"
