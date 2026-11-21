#!/bin/bash
# Every check, from the repository root, before a merge: the call server, the launcher and the Mac app.
#   ./check.sh
set -euo pipefail
cd "$(dirname "$0")"
[[ -d call/node_modules ]] || (cd call && npm ci --silent)
echo "== paths"; node check-paths.mjs # every path a doc or comment cites exists
echo "== call"; (cd call && node --test --test-timeout=120000)
echo "== launcher"; (cd launcher && swift test)
echo "== launcher snapshots"; (cd launcher && SNAPS="$(mktemp -d)" && swift run LauncherChecks --snapshots "$SNAPS" && rm -rf "$SNAPS") # every panel state drawn offscreen, nothing opens
echo "== Mac app"; (cd app && ./build.sh) # builds the app, then its replays and the differential against the page
echo "All checks passed."
