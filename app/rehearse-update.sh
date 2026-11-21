#!/bin/bash
# The Mac app's update rehearsal, 0.1 → 0.2, on this Mac only (nothing leaves it), and the microphone question: does an app signed with
# the owner's own identity keep its microphone and speech recognition permissions when Sparkle replaces it? Builds both versions with a
# feed served from 127.0.0.1 and unpacks 0.1 for you; you run it with the owner (it asks for the microphone, and a call makes sound).
#
#   SIGN_ID="Oh Kevin" ./rehearse-update.sh [port]      (port: default 8766; SIGN_ID is required: ad-hoc builds lose permissions by design)
#
# The rehearsal app has its own bundle id (local.claude-voice.app.rehearsal), so it asks for permissions afresh and shares nothing
# with the installed app's permissions or settings. Your private update key is read from your Keychain (a prompt may ask once).
set -euo pipefail
cd "$(dirname "$0")"
: "${SIGN_ID:?SIGN_ID is required (e.g. SIGN_ID=\"Oh Kevin\"): the question is whether that identity keeps the permissions}"
PORT="${1:-8766}"
export FEED_URL="http://127.0.0.1:$PORT/appcast.xml" DOWNLOAD_URL_PREFIX="http://127.0.0.1:$PORT/" RELEASES=releases-rehearsal
export BUNDLE_ID="${BUNDLE_ID:-local.claude-voice.app.rehearsal}"
NOTES="$(mktemp)"; echo "- A rehearsal update." > "$NOTES" # the rehearsal has no tag: release.sh takes its notes from here
saved="$(cat VERSION)"; trap 'echo "$saved" > VERSION; rm -f "$NOTES"' EXIT # release.sh writes the version it builds; the rehearsal puts yours back
rm -rf releases-rehearsal rehearsal-install
RELEASE_NOTES="$NOTES" DMG=0 ./release.sh 0.1 1 # the rehearsal needs no disk image (and so opens no Finder window)
RELEASE_NOTES="$NOTES" DMG=0 ./release.sh 0.2 2
mkdir rehearsal-install
ditto -x -k releases-rehearsal/Oh-Kevin-App-0.1.zip rehearsal-install
APP="$PWD/rehearsal-install/Oh Kevin.app"
cat <<MSG

Rehearsal ready. With the owner at the Mac (the microphone prompt, and a call makes sound):
  1. Serve the releases:     python3 -m http.server --bind 127.0.0.1 $PORT --directory "$PWD/releases-rehearsal"
  2. Open 0.1:               open "$APP"
     Start a call once and allow the microphone and speech recognition; end the call.
  3. Before:                 "$APP/Contents/MacOS/Oh Kevin" --permissions     → 0.1 …: microphone allowed, speech recognition allowed
  4. In the app menu choose "Check for Updates…": it finds 0.2, downloads it, and relaunches when the app is quiet (no call, Settings
     closed, the window not in front: click another app). The window comes back as 0.2 (About Oh Kevin says so).
  5. After:                  "$APP/Contents/MacOS/Oh Kevin" --permissions     → 0.2 …: microphone allowed, speech recognition allowed
     Then start a call: no prompt appears, and the bar says Listening. If a prompt appears, the identity did not keep the permission.
Clean up afterwards: stop the server (Ctrl-C), quit the app, delete app/releases-rehearsal and app/rehearsal-install, and remove the
rehearsal app from System Settings › Privacy & Security › Microphone and › Speech Recognition (tccutil reset All $BUNDLE_ID).
MSG
