#!/bin/bash
# Puts the call server inside an app, for both apps (launcher/build.sh and app/build.sh): call/'s own files, less what only a
# developer runs (tests, recorded calls, tools), and its packages already installed, so the first run
# fetches only Node's program and never runs npm. Of the packages only the Agent SDK's sdk.mjs is kept: it is one bundled file
# that loads nothing but Node's own modules (checked below, so a future SDK that needs more fails the build instead of a call).
#
#   launcher/pack-call.sh <the app's Contents/Resources/call>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CALL="$ROOT/call"
DEST="${1:?usage: pack-call.sh <destination call folder>}"
mkdir -p "$DEST" && DEST="$(cd "$DEST" && pwd)" # absolute: the guard below imports the SDK by its path
rsync -a --delete --exclude node_modules --exclude '*.test.mjs' --exclude replay --exclude tools --exclude AGENTS.md "$CALL/" "$DEST/"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cp "$CALL/package.json" "$CALL/package-lock.json" "$WORK/"
# the versions package-lock.json pins; no optional packages (the SDK's own Claude Code binary: the user's own Claude Code is used)
( cd "$WORK" && npm ci --omit=dev --omit=optional --ignore-scripts --no-audit --no-fund --loglevel=error >/dev/null )
SDK=node_modules/@anthropic-ai/claude-agent-sdk
mkdir -p "$DEST/$SDK"
cp "$WORK/$SDK/package.json" "$WORK/$SDK/sdk.mjs" "$WORK/$SDK/LICENSE.md" "$DEST/$SDK/"

# The guard: every module sdk.mjs imports or requires by name is one of Node's own, and it loads with what server.mjs takes from it.
node --input-type=module - "$DEST/$SDK/sdk.mjs" <<'JS'
import { readFileSync } from 'node:fs'
import { builtinModules } from 'node:module'
const file = process.argv[2], text = readFileSync(file, 'utf8'), own = new Set(builtinModules)
// `import … from"x"`, `import"x"`, `import("x")`, `require("x")`; code kept as text (Ajv's generated snippets, in quotes or
// backticks) is not a load and is skipped
const spec = '"([@\\w.][\\w@./:-]*)"'
const named = [...text.matchAll(new RegExp(`(?:(?<=[}*\\s])from\\s*|(?<![\\w'"\`$.])import\\s*|(?<![\\w'"\`$.])(?:import|require)\\s*\\(\\s*)${spec}`, 'g'))].map(m => m[1])
const other = [...new Set(named)].filter(n => !n.startsWith('.') && !own.has(n.replace(/^node:/, '')))
if (other.length) { console.error(`pack-call: sdk.mjs now loads ${other.join(', ')}: ship those packages too`); process.exit(1) }
const relative = named.filter(n => n.startsWith('.'))
if (relative.length) { console.error(`pack-call: sdk.mjs now loads files beside it (${relative.join(', ')}): ship them too`); process.exit(1) }
const m = await import(file)
for (const name of ['query', 'renameSession']) if (typeof m[name] !== 'function') { console.error(`pack-call: sdk.mjs has no ${name}`); process.exit(1) }
JS
# the install mark installRuntime and the setup check read: these packages are the ones package-lock.json names
shasum -a 256 "$DEST/package-lock.json" | cut -d' ' -f1 | tr -d '\n' > "$DEST/.installed"
