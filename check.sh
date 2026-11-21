#!/bin/bash
# Every check, from the repository root, before a merge: the call server and the Mac app.
#   ./check.sh
set -euo pipefail
cd "$(dirname "$0")"
[[ -d call/node_modules ]] || (cd call && npm ci --silent)
echo "== paths"; node .github/check-paths.mjs # every path a doc or comment cites exists
echo "== call"; (cd call && node --test --test-timeout=120000)
echo "== Mac app tests"; (cd app && swift test)
echo "== Mac app"; (cd app && ./build.sh) # builds the app, then its replays and the differential against the page
echo "All checks passed."
