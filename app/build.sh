#!/bin/bash
# Builds app/build/<name>.app ("Oh Kevin.app"). Needs only the Command Line Tools (no Xcode) and macOS 26.
#   ./build.sh                 build, sign ad-hoc, then run the equality checks
#   OUT=<folder> ./build.sh    build into that folder instead (the checks run only on build/)
#   Version: app/VERSION (e.g. 0.1) is the number people see; BUILD (default: the commit count) is the number Sparkle compares and
#     must rise with every release. Either can be given (VERSION=0.2 BUILD=7 ./build.sh).
#   Updates: FEED_URL=<appcast URL> ./build.sh gives the app the launcher's Sparkle updater (a daily check, "Check for Updates…",
#     "Update automatically" in Settings), trusting the owner's public key in launcher/SPARKLE_PUBLIC_KEY (SPARKLE_PUBLIC_KEY overrides
#     it). Without a feed, no updater. The app's own feed: …/releases/latest/download/appcast-app.xml (release.sh), never the launcher's.
#   Signing: ad-hoc by default. SIGN_ID="Oh Kevin" ./build.sh signs with that identity from your keychain, Sparkle's parts inside-out,
#     with no hardened runtime and no timestamp, as the launcher does. A stable identity is what lets macOS keep the microphone and
#     speech recognition permissions across an update; an ad-hoc build loses them at every rebuild.
#   BUNDLE_ID overrides the app's id (the rehearsal uses its own).
#   MOVE_TO_APPLICATIONS=1 turns on the move-to-Applications offer (the update line's "Move to Applications?"), as the launcher; off by default.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --product OhKevin
NAME=$(sed -n 's/.*static let name = "\(.*\)".*/\1/p' Sources/VoiceCore/Product.swift) # the one place the name lives (VoiceCore)
[ -n "$NAME" ] || { echo "No Product.name in Sources/VoiceCore/Product.swift"; exit 1; }
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ID="${BUNDLE_ID:-local.claude-voice.app}" # kept from the first name: his permissions and settings live under it
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY-$(tr -d '[:space:]' < ../launcher/SPARKLE_PUBLIC_KEY)}"
OUT="${OUT:-build}"
APP="$OUT/$NAME.app"
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$(swift build -c release --show-bin-path)/OhKevin" "$APP/Contents/MacOS/$NAME" # the process is called by the name too (Activity Monitor, Force Quit)
# Sparkle: the framework inside the app, found there by the binary
ditto ".build/artifacts/app/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$NAME"
cp ../call/problem.mp3 "$APP/Contents/Resources/" # the problem sound, inside the app
# The call server with its packages already installed, as the launcher carries it (launcher/pack-call.sh, shared). At first run and
# after each update the app copies it to Application Support/Oh Kevin/Call-App.
../launcher/pack-call.sh "$APP/Contents/Resources/call"
# The local voice without Python: the launcher's kokoro-runner, one binary for both apps, run from Contents/Helpers.
( cd ../launcher && swift build -c release --product kokoro-runner >/dev/null )
mkdir -p "$APP/Contents/Helpers"
cp "$(cd ../launcher && swift build -c release --show-bin-path)/kokoro-runner" "$APP/Contents/Helpers/kokoro-runner"
# The app icon, drawn by the launcher's own LauncherChecks from the owner's logo set: the same AppIcon.icns as the launcher's
( cd ../launcher && swift build --product LauncherChecks >/dev/null )
rm -rf "$OUT/AppIcon.iconset"
"$(cd ../launcher && swift build --show-bin-path)/LauncherChecks" --icon "$OUT/AppIcon.iconset"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$OUT/AppIcon.iconset" && rm -rf "$OUT/AppIcon.iconset"
UPDATES=""
if [[ -n "${FEED_URL:-}" && -n "$SPARKLE_PUBLIC_KEY" ]]; then
  UPDATES="<key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUAutomaticallyUpdate</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>"
fi
MOVE=""; [[ "${MOVE_TO_APPLICATIONS:-}" == "1" ]] && MOVE="<key>OKMoveToApplications</key><true/>"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHumanReadableCopyright</key><string>Licensed under the Apache License 2.0.</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>The call listens to you through the microphone. Speech is recognised on this Mac.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Your words are recognised on this Mac by Apple's speech recogniser, to talk with Claude Code.</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
  $UPDATES
  $MOVE
</dict>
</plist>
PLIST
# Signs inside-out: Sparkle's helpers (keeping their own entitlements), its framework, then the app (the launcher's sign_app).
sign_app() {
  local id=$1; shift
  local fw="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  for part in "$fw"/XPCServices/*.xpc "$fw/Autoupdate" "$fw/Updater.app"; do
    [[ -e "$part" ]] && codesign --force --sign "$id" --preserve-metadata=entitlements "$@" "$part"
  done
  codesign --force --sign "$id" --entitlements ../launcher/kokoro-runner.entitlements "$@" "$APP/Contents/Helpers/kokoro-runner" # opens downloaded libraries
  codesign --force --sign "$id" "$@" "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --sign "$id" "$@" "$APP"
  codesign --verify --deep --strict "$APP"
}
if [[ -n "${SIGN_ID:-}" ]]; then sign_app "$SIGN_ID" --timestamp=none; else sign_app -; fi
echo "Built $(cd "$OUT" && pwd)/$NAME.app  (version $VERSION, build $BUILD${UPDATES:+, updates from $FEED_URL})"
# The equality checks: the Swift turn-taking against ears.mjs and every recorded call. A build that drifts fails here.
if [[ "$OUT" == "build" ]]; then swift build --product AppChecks >/dev/null && node Tests/measure/check.mjs; fi # AppChecks replays them; never shipped
