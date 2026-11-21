#!/bin/bash
# Builds the menu-bar app: launcher/build/Oh Kevin Launcher.app (or $OUT/…; Product.fileName), ad-hoc signed. Needs only the Command Line Tools (no Xcode).
#   ./build.sh            build the app
#   ./build.sh --open     build it, then open it
#   OUT=<folder> ./build.sh   build into that folder instead of build/ (the folder is made; nothing else changes)
#   Version: VERSION (launcher/VERSION, e.g. 0.1) is the number people see; BUILD (default: the commit count) is the number Sparkle
#     compares, and must rise with every release. Either can be given in the environment (VERSION=0.2 BUILD=7 ./build.sh).
#   Updates: FEED_URL=<appcast URL> ./build.sh gives the app a Sparkle updater (a daily check and "Check for Updates…" in the
#     corner menu), trusting the public key in launcher/SPARKLE_PUBLIC_KEY (SPARKLE_PUBLIC_KEY overrides it). Without a feed, no updater.
#   MOVE_TO_APPLICATIONS=0 switches off the offer to move the app to /Applications (on by default).
#   Signing: ad-hoc by default. SIGN_ID="Oh Kevin" ./build.sh signs with that identity from your keychain (a self-made one keeps the
#     app's identity, so macOS keeps its permissions across updates); Sparkle's parts inside the app are signed with it, inside-out.
#   ./build.sh --release  build, sign with Developer ID, notarize, staple, and zip it for others. Needs, once:
#     SIGN_ID="Developer ID Application: <Name> (<TEAMID>)"   the certificate in the login keychain
#     NOTARY_PROFILE=<name>   from: xcrun notarytool store-credentials <name> --apple-id … --team-id … --password …
#     BUNDLE_ID=<reverse-DNS you own>   the app's id; without it the local one below
set -euo pipefail
cd "$(dirname "$0")"

NAME=$(sed -n 's/.*static let name = "\(.*\)".*/\1/p' Sources/VoiceCore/Product.swift) # the one place the name lives
FILE=$(sed -n 's/.*static let fileName = "\(.*\)".*/\1/p' Sources/VoiceCore/Product.swift) # and the file name: "Oh Kevin Launcher.app", the name inside stays $NAME
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}" # the one place: launcher/VERSION
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY-$(tr -d '[:space:]' < SPARKLE_PUBLIC_KEY)}" # the owner's update key, public half: launcher/SPARKLE_PUBLIC_KEY
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}" # rises with every commit; a release that must rise otherwise passes BUILD
ID="${BUNDLE_ID:-local.claude-voice.launcher}" # kept from the first name: settings and Open at login live under it
RELEASE=$([[ "${1:-}" == "--release" ]] && echo 1 || true)
[[ -n "$RELEASE" && ( -z "${SIGN_ID:-}" || -z "${NOTARY_PROFILE:-}" || -z "${BUNDLE_ID:-}" ) ]] &&
  { echo "--release needs SIGN_ID, NOTARY_PROFILE and BUNDLE_ID (see the top of this file)." >&2; exit 2; }
OUT="${OUT:-build}"
APP="$OUT/$FILE.app"

swift build -c release --product ClaudeVoice
swift build -c release --product kokoro-runner # the local voice without Python: one binary for both apps, run from Contents/Helpers
swift build --product LauncherChecks # never shipped: it draws the icon here, and runs the checks (README)
BIN="$(swift build -c release --show-bin-path)/ClaudeVoice"

rm -rf "$APP" "$OUT/AppIcon.iconset"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeVoice"
mkdir -p "$APP/Contents/Helpers"
cp "$(swift build -c release --show-bin-path)/kokoro-runner" "$APP/Contents/Helpers/kokoro-runner" # the installer copies it next to the voice's libraries
# Sparkle: the framework goes inside the app, and the binary finds it there.
SPARKLE_FRAMEWORK=".build/artifacts/launcher/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/ClaudeVoice"
# The call server with its packages already installed (pack-call.sh): the app fetches only Node's program on first run.
./pack-call.sh "$APP/Contents/Resources/call"
"$(swift build --show-bin-path)/LauncherChecks" --privacy "$APP/Contents/Resources/privacy.html" # shipped beside the call files, from the same words as Settings
"$(swift build --show-bin-path)/LauncherChecks" --icon "$OUT/AppIcon.iconset"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$OUT/AppIcon.iconset"
rm -rf "$OUT/AppIcon.iconset"

UPDATES=""
if [[ -n "${FEED_URL:-}" && -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
  UPDATES="<key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUAutomaticallyUpdate</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>"
fi

MOVE=""; [[ "${MOVE_TO_APPLICATIONS:-}" == "0" ]] && MOVE="<key>OKMoveToApplications</key><false/>" # the move-to-Applications offer is on unless switched off here

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleExecutable</key><string>ClaudeVoice</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
  $UPDATES
  $MOVE
</dict>
</plist>
PLIST

# Signs the app, inside-out: Sparkle's helpers first (keeping their own entitlements), then its framework, then the app. `$1` is the
# identity ("-" is ad-hoc), the rest are codesign's own options.
sign_app() {
  local id=$1; shift
  local fw="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  for part in "$fw"/XPCServices/*.xpc "$fw/Autoupdate" "$fw/Updater.app"; do
    [[ -e "$part" ]] && codesign --force --sign "$id" --preserve-metadata=entitlements "$@" "$part"
  done
  # the runner opens onnxruntime and espeak-ng libraries that are downloaded (signed by others): a hardened runtime must allow that
  codesign --force --sign "$id" --entitlements kokoro-runner.entitlements "$@" "$APP/Contents/Helpers/kokoro-runner"
  codesign --force --sign "$id" "$@" "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --sign "$id" "$@" "$APP"
  codesign --verify --deep --strict "$APP"
}

if [[ -z "$RELEASE" ]]; then
  # Ad-hoc, or an identity of your own (SIGN_ID). No hardened runtime and no timestamp: those are for notarization, and a self-made
  # identity has no team for the runtime's library validation to accept Sparkle's framework against (tested: dyld refuses the
  # framework in a hardened-runtime host, "different Team IDs", even with both signed by the same self-made identity).
  if [[ -n "${SIGN_ID:-}" ]]; then sign_app "$SIGN_ID" --timestamp=none; else sign_app -; fi
  echo "Built $(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")  (version $VERSION, build $BUILD)"
else
  # No entitlements: the app ships neither Node nor Claude Code, and each process it starts carries its own signature.
  sign_app "$SIGN_ID" --options runtime --timestamp
  codesign --verify --strict --verbose=2 "$APP"
  ZIP="$OUT/$FILE $VERSION.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait # on failure: xcrun notarytool log <id> …
  xcrun stapler staple "$APP"
  spctl -a -vv -t exec "$APP" # expect: accepted, source=Notarized Developer ID
  rm "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP" # the stapled app is what people download
  echo "Released $PWD/$ZIP"
fi
[[ "${1:-}" == "--open" ]] && open "$APP"
exit 0
