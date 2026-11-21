#!/bin/bash
# A rehearsal of an update, on this Mac only (nothing leaves it): builds 0.1 and 0.2 of the app whose update feed is a folder served
# from 127.0.0.1, and unpacks 0.1 for you to install. You serve the folder, open 0.1 and watch it offer, download and install 0.2.
#
#   [SIGN_ID="Oh Kevin"] ./rehearse-update.sh [port]      (port: default 8765; the app trusts launcher/SPARKLE_PUBLIC_KEY)
#
# Your private key is read from your Keychain by Sparkle's generate_appcast (a macOS prompt may ask once). The rehearsal app has a
# bundle id of its own, so it does not share its preferences with your installed app; it does share ~/Library/Application Support/
# Claude Voice (Node, packages, voice, Chrome profile) with it, so quit the installed app first.
set -euo pipefail
cd "$(dirname "$0")"
PORT="${1:-8765}"
export FEED_URL="http://127.0.0.1:$PORT/appcast.xml" DOWNLOAD_URL_PREFIX="http://127.0.0.1:$PORT/" RELEASES=releases-rehearsal
export BUNDLE_ID="${BUNDLE_ID:-local.claude-voice.launcher.rehearsal}"
saved="$(cat VERSION)"; trap 'echo "$saved" > VERSION' EXIT # release.sh writes the version it builds; the rehearsal puts yours back
rm -rf releases-rehearsal rehearsal-install
./release.sh 0.1 1
./release.sh 0.2 2
mkdir rehearsal-install
ditto -x -k releases-rehearsal/Oh-Kevin-Launcher-0.1.zip rehearsal-install
cat <<MSG

Rehearsal ready. In three steps:
  1. In another terminal, serve the releases:   python3 -m http.server --bind 127.0.0.1 $PORT --directory "$PWD/releases-rehearsal"
  2. Quit your installed app, then open version 0.1:   open "$PWD/rehearsal-install/Oh Kevin Launcher.app"
  3. In its three-dot menu choose "Check for Updates…": it offers 0.2; Install and Relaunch. The app comes back as 0.2.
Clean up afterwards: stop the server (Ctrl-C) and delete launcher/releases-rehearsal and launcher/rehearsal-install.
MSG
