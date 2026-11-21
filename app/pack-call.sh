#!/bin/bash
# Puts the call server inside the app (build.sh): call/'s own files, less what only a
# developer runs (tests, recorded calls, tools). No packages: the one the server imports, the Agent SDK, is fetched from npm on the
# user's Mac at first run (VoiceCore's installSDK takes only its sdk.mjs). Checked here: that sdk.mjs loads nothing but Node's own
# modules, so a future SDK that needs more fails the build instead of a call.
#
#   ./pack-call.sh <the app's Contents/Resources/call>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CALL="$ROOT/call"
DEST="${1:?usage: pack-call.sh <destination call folder>}"
mkdir -p "$DEST"
rsync -a --delete --exclude node_modules --exclude '*.test.mjs' --exclude replay --exclude tools --exclude AGENTS.md --exclude ohkevin.mjs "$CALL/" "$DEST/"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cp "$CALL/package.json" "$CALL/package-lock.json" "$WORK/"
# the versions package-lock.json pins (the SDK is a devDependency: `npx ohkevin` fetches it itself); no optional packages (the SDK's own Claude Code binary)
( cd "$WORK" && npm ci --omit=optional --ignore-scripts --no-audit --no-fund --loglevel=error >/dev/null )
SDK=node_modules/@anthropic-ai/claude-agent-sdk

# The guard: every module sdk.mjs imports or requires by name is one of Node's own, and it loads with what server.mjs takes from it.
node --input-type=module - "$WORK/$SDK/sdk.mjs" <<'JS'
import { readFileSync } from 'node:fs'
import { builtinModules } from 'node:module'
const file = process.argv[2], text = readFileSync(file, 'utf8'), own = new Set(builtinModules)
// `import … from"x"`, `import"x"`, `import("x")`, `require("x")`; code kept as text (Ajv's generated snippets, in quotes or
// backticks) is not a load and is skipped
const spec = '"([@\\w.][\\w@./:-]*)"'
const named = [...text.matchAll(new RegExp(`(?:(?<=[}*\\s])from\\s*|(?<![\\w'"\`$.])import\\s*|(?<![\\w'"\`$.])(?:import|require)\\s*\\(\\s*)${spec}`, 'g'))].map(m => m[1])
const other = [...new Set(named)].filter(n => !n.startsWith('.') && !own.has(n.replace(/^node:/, '')))
if (other.length) { console.error(`pack-call: sdk.mjs now loads ${other.join(', ')}: installSDK (VoiceCore) must fetch those packages too`); process.exit(1) }
const relative = named.filter(n => n.startsWith('.'))
if (relative.length) { console.error(`pack-call: sdk.mjs now loads files beside it (${relative.join(', ')}): installSDK (VoiceCore) must take them too`); process.exit(1) }
const m = await import(file)
for (const name of ['query', 'renameSession']) if (typeof m[name] !== 'function') { console.error(`pack-call: sdk.mjs has no ${name}`); process.exit(1) }
JS
