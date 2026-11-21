#!/bin/bash
# Publishes one built release to GitHub: a release v<version> with the zip, the disk image (twice: Oh-Kevin-Launcher-<version>.dmg and the
# stable Oh-Kevin-Launcher.dmg), the feed (appcast.xml) and SHA256SUMS over them as its assets, made by release.sh in
# releases/v<version>/. Its notes are the tag's message that release.sh put beside the zip; the tag must be on GitHub already.
# It becomes "latest"; earlier releases stay. Apps read https://github.com/<repo>/releases/latest/download/appcast.xml, so the newest
# release always serves the newest feed. Nothing else: no git push, no change to the repository or its visibility.
#
#   ./publish.sh <version> [notes-file]        e.g. ./publish.sh 0.2        (REPO overrides bekhruzbekswe/ohkevin)
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(git branch --show-current)" == main && -z "$(git status --porcelain)" ]] || { echo "Release only from main with nothing uncommitted (AGENTS.md, Releases)." >&2; exit 4; }
VERSION="${1:?usage: ./publish.sh <version> [notes-file]}"
REPO="${REPO:-bekhruzbekswe/ohkevin}"
DIR="${RELEASES:-$HOME/Lab/ohkevin-releases/launcher}/v$VERSION"
ZIP="$DIR/$(sed -n 's/.*static let fileName = "\(.*\)".*/\1/p' Sources/VoiceCore/Product.swift | tr ' ' '-')-$VERSION.zip"
[[ -f "$ZIP" ]] || { echo "No $ZIP: run ./release.sh $VERSION first." >&2; exit 2; }
DMG="${ZIP%.zip}.dmg"
[[ -f "$DMG" ]] || { echo "No $DMG: run ./release.sh $VERSION first (it makes the disk image too)." >&2; exit 2; }
[[ -f "$DIR/appcast.xml" ]] || { echo "No $DIR/appcast.xml: run ./release.sh $VERSION first." >&2; exit 2; }
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$DIR/appcast.xml" \
  || { echo "$DIR/appcast.xml has no entry for $VERSION." >&2; exit 2; }
NEWEST=$(grep -oE '<sparkle:shortVersionString>[^<]+' "$DIR/appcast.xml" | head -1 | sed 's/.*>//')
[[ "$NEWEST" == "$VERSION" ]] || { echo "$DIR/appcast.xml's newest entry is $NEWEST, not $VERSION." >&2; exit 2; }
NOTES="${2:-${ZIP%.zip}.md}"
[[ -s "$NOTES" ]] || { echo "No release notes ($NOTES): release.sh writes them from the tag v$VERSION." >&2; exit 2; }
# The disk image goes up twice: under its version, and under a stable name, so .../releases/latest/download/<Name>.dmg always works.
STABLE_DIR=$(mktemp -d); trap 'rm -rf "$STABLE_DIR"' EXIT
STABLE="$STABLE_DIR/$(sed -n 's/.*static let fileName = "\(.*\)".*/\1/p' Sources/VoiceCore/Product.swift | tr ' ' '-').dmg"
cp "$DMG" "$STABLE"
# SHA256SUMS: one line per uploaded file, by its name on GitHub, so `shasum -a 256 -c SHA256SUMS` checks a download
( cd "$DIR" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" appcast.xml; cd "$STABLE_DIR" && shasum -a 256 "$(basename "$STABLE")" ) > "$STABLE_DIR/SHA256SUMS"
gh release create "v$VERSION" "$ZIP" "$DMG" "$STABLE" "$DIR/appcast.xml" "$STABLE_DIR/SHA256SUMS" --repo "$REPO" --title "Oh Kevin $VERSION" --notes-file "$NOTES" --verify-tag --latest # the launcher owns "latest": its apps read releases/latest/download/appcast.xml
