#!/bin/bash
# Makes one update release of the Mac app: builds it with its feed, signs it, zips it into app/releases/ and (re)writes the app's feed with
# Sparkle's generate_appcast. It publishes NOTHING: publish.sh uploads what it makes in releases/v<version>/ as the release
# app-v<version>, GitHub's latest; the app reads …/releases/latest/download/appcast-app.xml.
#
#   ./release.sh <version> [build]
#
#   <version>   the number people see (also written to app/VERSION): 0.2
#   [build]     the number Sparkle compares: must be higher than the last release's. Default: the feed's last build + 1.
#
# Environment (all optional):
#   FEED_URL            the feed built into the app (default: https://github.com/bekhruzbekswe/ohkevin/releases/latest/download/appcast-app.xml)
#   DOWNLOAD_URL_PREFIX where the zips will be (default: https://github.com/bekhruzbekswe/ohkevin/releases/download/app-v<version>/)
#   SPARKLE_PUBLIC_KEY  overrides SPARKLE_PUBLIC_KEY beside this script (the app only accepts updates signed by its private half)
#   SIGN_ID             the code-signing identity, e.g. "Oh Kevin": needed for a real release, so macOS keeps the microphone and
#                       speech recognition permissions across updates (ad-hoc is only fit for a rehearsal, and loses them)
#   SPARKLE_KEY_FILE    the private key as a file; default: read from your Keychain, where generate_keys put it
#   RELEASES            the folder holding the zips and the feed (default: ~/Lab/ohkevin-releases/app)
#   BUNDLE_ID           the app's id (the rehearsal uses its own)
#   DMG=0               skip the disk image. Otherwise make-dmg.sh makes Oh-Kevin-App-<version>.dmg beside the zip (volume
#                       "Oh Kevin", the same background); Finder opens a window for a moment and macOS may ask once to let it control Finder
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(git branch --show-current)" == main && -z "$(git status --porcelain)" ]] || { echo "Release only from main with nothing uncommitted (AGENTS.md, Releases)." >&2; exit 4; }

VERSION="${1:?usage: ./release.sh <version> [build]}"
BUILD="${2:-}"
REPO_URL="https://github.com/bekhruzbekswe/ohkevin"
export FEED_URL="${FEED_URL:-$REPO_URL/releases/latest/download/appcast-app.xml}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-$REPO_URL/releases/download/app-v$VERSION/}"
# The release notes: the annotated tag's message (the version's CHANGELOG.md section), shown in the update prompt and on GitHub.
# RELEASE_NOTES=<file> gives them instead (the rehearsal, which has no tag).
if [[ -n "${RELEASE_NOTES:-}" ]]; then NOTES_TEXT="$(cat "$RELEASE_NOTES")"
else
  [[ "$(git cat-file -t "app-v$VERSION" 2>/dev/null)" == tag && "$(git rev-parse "app-v$VERSION^{commit}")" == "$(git rev-parse HEAD)" ]] \
    || { echo "Tag this commit first: git tag -a app-v$VERSION, its message the version's CHANGELOG.md section (AGENTS.md, Releases)." >&2; exit 3; }
  NOTES_TEXT="$(git tag -l --format='%(contents)' "app-v$VERSION" | sed '/^-----BEGIN PGP/,$d')"
fi
RELEASES="${RELEASES:-$HOME/Lab/ohkevin-releases/app}" # outside git, shared by every checkout
FEED="$(basename "$FEED_URL")" # generate_appcast names the feed after the app's own SUFeedURL: appcast-app.xml (the rehearsal's: appcast.xml)
TOOLS=".build/artifacts/app/Sparkle/bin"
[[ -x "$TOOLS/generate_appcast" ]] || swift build >/dev/null # fetches Sparkle and its tools

mkdir -p "$RELEASES"
# A build number that does not rise is an update Sparkle will never offer: say so now.
last=$([[ -f "$RELEASES/$FEED" ]] && sed -n 's/.*<sparkle:version>\([0-9]*\)<.*/\1/p' "$RELEASES/$FEED" | sort -n | tail -1 || true)
BUILD="${BUILD:-$(( ${last:-0} + 1 ))}"
[[ -z "$last" || "$BUILD" -gt "$last" ]] || { echo "Build $BUILD is not higher than the last release's ($last): pass a higher build." >&2; exit 1; }

OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
echo "$VERSION" > VERSION
OUT="$OUT" VERSION="$VERSION" BUILD="$BUILD" ./build.sh
NAME=$(sed -n 's/.*static let name = "\(.*\)".*/\1/p' Sources/VoiceCore/Product.swift)
ZIP="$RELEASES/${NAME// /-}-App-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$OUT/$NAME.app" "$ZIP"
printf '%s\n' "$NOTES_TEXT" > "${ZIP%.zip}.md" # generate_appcast embeds it as this version's description

KEY=(); [[ -n "${SPARKLE_KEY_FILE:-}" ]] && KEY=(--ed-key-file "$SPARKLE_KEY_FILE")
"$TOOLS/generate_appcast" ${KEY[@]+"${KEY[@]}"} --maximum-deltas 0 --embed-release-notes --download-url-prefix "$DOWNLOAD_URL_PREFIX" "$RELEASES"
# Per-version folders (releases/download/app-v<version>/): each entry's link goes back to its own version (not part of the signature).
sed -E -i '' 's#/app-v[^/"]+/([^/"]+-App-)([0-9][0-9A-Za-z.]*)\.zip"#/app-v\2/\1\2.zip"#g' "$RELEASES/$FEED"
# What gets uploaded for this version: its zip, and the feed as it stood right after it, under the app's own feed name.
mkdir -p "$RELEASES/v$VERSION"; cp "$ZIP" "${ZIP%.zip}.md" "$RELEASES/v$VERSION/"; cp "$RELEASES/$FEED" "$RELEASES/v$VERSION/$FEED"
# The disk image people download the first time (updates come by the zip).
if [[ "${DMG:-1}" != "0" ]]; then
  # left unsigned on purpose: a self-signed image is blocked on open, so only the app is assessed (one Open Anyway, not two)
  env -u DMG_SIGN_ID ./make-dmg.sh "$OUT/$NAME.app" "$(cd "$RELEASES/v$VERSION" && pwd)/${NAME// /-}-App-$VERSION.dmg" # absolute: make-dmg.sh runs from its own folder
fi
echo
echo "Release $VERSION (build $BUILD): $RELEASES/v$VERSION/ holds $(basename "$ZIP"), $FEED and the disk image. Nothing was published."
