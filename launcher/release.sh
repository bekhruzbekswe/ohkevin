#!/bin/bash
# Makes one update release: builds the app, signs it, zips it into releases/ and (re)writes releases/appcast.xml with Sparkle's
# generate_appcast, and the disk image (Oh-Kevin-Launcher-<version>.dmg) beside the zip in releases/v<version>/. It publishes NOTHING: you upload releases/ (the zip and appcast.xml) wherever FEED_URL points.
#
#   ./release.sh <version> [build]
#
#   <version>   the number people see (also written to launcher/VERSION): 0.2
#   [build]     the number Sparkle compares: must be higher than the last release's. Default: the commit count.
#
# Environment (all but the first two are optional):
#   FEED_URL            where the app looks for appcast.xml, built into the app (https://example.org/oh-kevin/appcast.xml)
#   SPARKLE_PUBLIC_KEY  overrides launcher/SPARKLE_PUBLIC_KEY, the owner's public key built into the app (it only accepts updates signed by it)
#   DOWNLOAD_URL_PREFIX where the zip will be (https://example.org/oh-kevin/): the appcast's download links are this + the file name
#   SIGN_ID             your code-signing identity, e.g. "Oh Kevin" (default: ad-hoc, which is only fit for the local rehearsal)
#   SPARKLE_KEY_FILE    the private key as a file (generate_keys -x file); default: read from your Keychain, where generate_keys put it
#   RELEASE_NOTES       a file with the release notes, instead of the tag v<version>'s message (the rehearsal)
#   RELEASES            the folder holding the zips and appcast.xml (default: ~/Lab/ohkevin-releases/launcher)
#   DMG_LAYOUT          Finder lays the disk image out through AppleScript by default (a window opens briefly; macOS asks once to control
#                       Finder); "dmgbuild" skips Finder but the background then does not show
#   DMG_VENV            where make-dmg.sh keeps its pinned dmgbuild (default: launcher/.dmg-venv, made on first use)
#
# Example:
#   FEED_URL=https://example.org/oh-kevin/appcast.xml DOWNLOAD_URL_PREFIX=https://example.org/oh-kevin/ \
#   SIGN_ID="Oh Kevin" ./release.sh 0.2
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(git branch --show-current)" == main && -z "$(git status --porcelain)" ]] || { echo "Release only from main with nothing uncommitted (AGENTS.md, Releases)." >&2; exit 4; }

VERSION="${1:?usage: ./release.sh <version> [build]}"
BUILD="${2:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
: "${FEED_URL:?FEED_URL is needed: it is built into the app}"
: "${DOWNLOAD_URL_PREFIX:?DOWNLOAD_URL_PREFIX is needed: the download links in the appcast}"
# The release notes: the annotated tag's message (the version's CHANGELOG.md section), shown in the update prompt and on GitHub.
# RELEASE_NOTES=<file> gives them instead (the rehearsal, which has no tag).
if [[ -n "${RELEASE_NOTES:-}" ]]; then NOTES_TEXT="$(cat "$RELEASE_NOTES")"
else
  [[ "$(git cat-file -t "v$VERSION" 2>/dev/null)" == tag && "$(git rev-parse "v$VERSION^{commit}")" == "$(git rev-parse HEAD)" ]] \
    || { echo "Tag this commit first: git tag -a v$VERSION, its message the version's CHANGELOG.md section (AGENTS.md, Releases)." >&2; exit 3; }
  NOTES_TEXT="$(git tag -l --format='%(contents)' "v$VERSION" | sed '/^-----BEGIN PGP/,$d')"
fi
RELEASES="${RELEASES:-$HOME/Lab/ohkevin-releases/launcher}" # outside git, shared by every checkout
TOOLS=".build/artifacts/launcher/Sparkle/bin"
[[ -x "$TOOLS/generate_appcast" ]] || swift build >/dev/null # fetches Sparkle and its tools

mkdir -p "$RELEASES"
# A build number that does not rise is an update Sparkle will never offer: say so now, not after people wait for it.
if [[ -f "$RELEASES/appcast.xml" ]]; then
  last=$(sed -n 's/.*<sparkle:version>\([0-9]*\)<.*/\1/p' "$RELEASES/appcast.xml" | sort -n | tail -1)
  [[ -z "$last" || "$BUILD" -gt "$last" ]] || { echo "Build $BUILD is not higher than the last release's ($last): pass a higher build." >&2; exit 1; }
fi

OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
echo "$VERSION" > VERSION
OUT="$OUT" VERSION="$VERSION" BUILD="$BUILD" ./build.sh
NAME=$(sed -n 's/.*static let fileName = "\(.*\)".*/\1/p' Sources/VoiceCore/Product.swift) # the file name: Oh-Kevin-Launcher-<version>.zip
ZIP="$RELEASES/${NAME// /-}-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$OUT/$NAME.app" "$ZIP"
printf '%s\n' "$NOTES_TEXT" > "${ZIP%.zip}.md" # generate_appcast embeds it as this version's description

KEY=(); [[ -n "${SPARKLE_KEY_FILE:-}" ]] && KEY=(--ed-key-file "$SPARKLE_KEY_FILE")
"$TOOLS/generate_appcast" ${KEY[@]+"${KEY[@]}"} --maximum-deltas 0 --embed-release-notes --download-url-prefix "$DOWNLOAD_URL_PREFIX" "$RELEASES"
# Per-version folders (GitHub's releases/download/v<version>/): generate_appcast gives every entry this run's prefix, so each entry's link
# goes back to its own version's folder. The links are not part of the EdDSA signature, which covers the zip itself.
sed -E -i '' 's#/v[^/"]+/([^/"]+-)([0-9][0-9A-Za-z.]*)\.zip"#/v\2/\1\2.zip"#g' "$RELEASES/appcast.xml"
# What publish.sh uploads for this version: its zip, and the feed as it stood right after it (newest entry: this version).
mkdir -p "$RELEASES/v$VERSION"; cp "$ZIP" "${ZIP%.zip}.md" "$RELEASES/appcast.xml" "$RELEASES/v$VERSION/"
# The disk image people download (the update zip is for the app's own updater): in the version's folder only, so generate_appcast, which
# reads archives in $RELEASES itself, never takes it for another update. Left unsigned (see make-dmg.sh).
DMG="$RELEASES/v$VERSION/${NAME// /-}-$VERSION.dmg"
./make-dmg.sh "$OUT/$NAME.app" "$DMG"
echo
echo "Release $VERSION (build $BUILD): $ZIP, $DMG and $RELEASES/appcast.xml. Upload both to $DOWNLOAD_URL_PREFIX; the app reads $FEED_URL."
