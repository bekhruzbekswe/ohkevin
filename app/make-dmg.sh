#!/bin/bash
# Makes the disk image people download: volume "Oh Kevin", the approved 640 × 400 picture behind the app and a link to Applications.
#
#   ./make-dmg.sh <app> <out.dmg>          (the image is left unsigned; DMG_SIGN_ID signs it, for a notarized Developer ID only;
#                                           DMG_VENV overrides where dmgbuild is installed)
# Unsigned on purpose: a quarantined image signed with a self-made identity is refused on open (System Settings › Open Anyway),
# then the app inside asks again: two blocks. An unsigned image mounts at once and only the app is assessed. The app inside is
# signed with SIGN_ID, and updates are checked by Sparkle's EdDSA signature.
#   Finder itself writes the layout (the default; DMG_LAYOUT=dmgbuild uses dmgbuild alone, which shows no background here)
#
# DMG_LAYOUT=finder: dmgbuild's .DS_Store does not show the background on this macOS, so Finder is asked to lay the image out: a
# read-write image is mounted, `osascript` tells Finder to open the volume, set the window, icon view and places and the background,
# and close the window; then the image is detached and converted to compressed. A Finder window opens for a moment, and macOS asks
# once "... wants to control Finder": that click is the person's (this script never touches the privacy settings).
#
# The Finder layout (window size, icon places and size, hidden toolbar, sidebar and status bar, the background) is written straight into
# the image by dmgbuild, a pinned Python tool in a throwaway virtualenv: no Finder is scripted and no window opens. The background is
# design/dmg/background.png and @2x joined into one .background/background.tiff with tiffutil (the 1x and 2x pictures together).
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:?usage: ./make-dmg.sh <app> <out.dmg>}"; OUT="${2:?usage: ./make-dmg.sh <app> <out.dmg>}"
VENV="${DMG_VENV:-.dmg-venv}"
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q "dmgbuild==1.6.5"
fi
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
tiffutil -cathidpicheck ../design/dmg/background.png ../design/dmg/background@2x.png -out "$WORK/background.tiff"
ICON="$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$(dirname "$OUT")"; rm -f "$OUT"
if [[ "${DMG_LAYOUT:-finder}" == "finder" ]]; then
  VOL="Oh Kevin"; MNT="/Volumes/$VOL"; NAME="$(basename "$APP")"
  [[ ! -e "$MNT" ]] || { echo "$MNT is already mounted: eject it first" >&2; exit 1; }
  RW="$WORK/rw.dmg"
  KB=$(( $(du -sk "$APP" | cut -f1) + 20480 ))
  hdiutil create -quiet -size "${KB}k" -fs HFS+ -volname "$VOL" "$RW"
  hdiutil attach -quiet -noverify -noautoopen "$RW"
  detach() { hdiutil detach -quiet "$MNT" 2>/dev/null || hdiutil detach -quiet -force "$MNT" 2>/dev/null || true; }
  trap 'detach; rm -rf "$WORK"' EXIT
  ditto "$APP" "$MNT/$NAME"
  ln -s /Applications "$MNT/Applications"
  mkdir "$MNT/.background"; cp "$WORK/background.tiff" "$MNT/.background/background.tiff"; chflags hidden "$MNT/.background"
  [[ -f "$ICON" ]] && { cp "$ICON" "$MNT/.VolumeIcon.icns"; SetFile -a C "$MNT" 2>/dev/null || true; }
  # The window's frame is 640 x 428: its 28-point title bar plus the 640 x 400 the picture is drawn for.
  osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    set w to container window
    set current view of w to icon view
    set toolbar visible of w to false
    set statusbar visible of w to false
    set bounds of w to {200, 120, 840, 548}
    set opts to icon view options of w
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 12
    set background picture of opts to (POSIX file "$MNT/.background/background.tiff" as alias)
    set position of item "$NAME" of w to {176, 232}
    set position of item "Applications" of w to {464, 232}
    update without registering applications
    close
  end tell
end tell
OSA
  for _ in $(seq 50); do [[ -f "$MNT/.DS_Store" ]] && break; sleep 0.1; done # Finder writes it as the window closes
  sync; detach; trap 'rm -rf "$WORK"' EXIT
  hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT"
else
"$VENV/bin/dmgbuild" -s dmg-settings.py -D app="$APP" -D tiff="$WORK/background.tiff" -D icon="$ICON" "Oh Kevin" "$OUT"
fi
[[ -z "${DMG_SIGN_ID:-}" ]] || codesign --force --sign "$DMG_SIGN_ID" "$OUT"
echo "Made $OUT"
