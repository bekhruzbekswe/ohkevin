#!/bin/bash
# Publishes one built release of the Mac app to GitHub, beside the old launcher's (whose newest release keeps "latest" for its users). Made by
# release.sh in releases/v<version>/:
#   1. a release app-v<version> with the zip, the disk image and SHA256SUMS over them, never marked latest; its notes are the tag's
#      message that release.sh put beside the zip, and the tag must be on GitHub already;
#   2. the app's fixed release app-feed (made once, never latest) gets this version's appcast-app.xml and the disk image as
#      Oh-Kevin-App.dmg, replacing the last ones (--clobber). The app reads …/releases/download/app-feed/appcast-app.xml, and the
#      stable download link is …/releases/download/app-feed/Oh-Kevin-App.dmg.
# Nothing else: no git push, no change to the repository or its visibility.
#
#   ./publish.sh <version> [notes-file]        e.g. ./publish.sh 0.2        (REPO overrides bekhruzbekswe/ohkevin)
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(git branch --show-current)" == main && -z "$(git status --porcelain)" ]] || { echo "Release only from main with nothing uncommitted (AGENTS.md, Releases)." >&2; exit 4; }
VERSION="${1:?usage: ./publish.sh <version> [notes-file]}"
REPO="${REPO:-bekhruzbekswe/ohkevin}"
DIR="${RELEASES:-$HOME/Lab/ohkevin-releases/app}/v$VERSION"
BASE="$(sed -n 's/.*static let name = "\(.*\)".*/\1/p' Sources/VoiceCore/Product.swift | tr ' ' '-')-App" # Oh-Kevin-App
ZIP="$DIR/$BASE-$VERSION.zip"; DMG="$DIR/$BASE-$VERSION.dmg"; FEED="$DIR/appcast-app.xml"
for f in "$ZIP" "$DMG" "$FEED"; do [[ -f "$f" ]] || { echo "No $f: run ./release.sh $VERSION first." >&2; exit 2; }; done
NEWEST=$(grep -oE '<sparkle:shortVersionString>[^<]+' "$FEED" | head -1 | sed 's/.*>//')
[[ "$NEWEST" == "$VERSION" ]] || { echo "$FEED's newest entry is $NEWEST, not $VERSION." >&2; exit 2; }
grep -q "releases/download/app-v$VERSION/$BASE-$VERSION.zip" "$FEED" || { echo "$FEED does not link to app-v$VERSION/$BASE-$VERSION.zip." >&2; exit 2; }

NOTES="${2:-${ZIP%.zip}.md}" # the tag's message, which release.sh put beside the zip; the tag must be on GitHub already
[[ -s "$NOTES" ]] || { echo "No release notes ($NOTES): release.sh writes them from the tag app-v$VERSION." >&2; exit 2; }
STABLE="$(mktemp -d)"; trap 'rm -rf "$STABLE"' EXIT
# SHA256SUMS: one line per uploaded file, by its name on GitHub, so `shasum -a 256 -c SHA256SUMS` checks a download
( cd "$DIR" && shasum -a 256 "$BASE-$VERSION.zip" "$BASE-$VERSION.dmg" ) > "$STABLE/SHA256SUMS"
gh release create "app-v$VERSION" "$ZIP" "$DMG" "$STABLE/SHA256SUMS" --repo "$REPO" --title "Oh Kevin for Mac $VERSION" --notes-file "$NOTES" --verify-tag --latest=false

# The fixed release: the feed and the stable disk image, this version's.
cp "$DMG" "$STABLE/$BASE.dmg"
gh release view app-feed --repo "$REPO" >/dev/null 2>&1 ||
  gh release create app-feed --repo "$REPO" --title "Oh Kevin for Mac: update feed" --notes "The Mac app's update feed and its newest disk image." --latest=false
gh release upload app-feed "$FEED" "$STABLE/$BASE.dmg" --repo "$REPO" --clobber
echo "Published app $VERSION: app-v$VERSION, and app-feed now serves it."
