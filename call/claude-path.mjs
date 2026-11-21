// The user's own Claude Code: CLAUDE_PATH (the apps always set it), else the first executable `claude` on PATH, as an absolute path.
// Unset and not found, the SDK looks for its own binary, which the apps leave out.
import path from 'node:path'
import { statSync } from 'node:fs'

export function findClaude(env = process.env) {
  if (env.CLAUDE_PATH) return env.CLAUDE_PATH
  for (const dir of (env.PATH ?? '').split(path.delimiter)) {
    if (!dir) continue
    const file = path.resolve(dir, 'claude')
    try { if (statSync(file).isFile() && (statSync(file).mode & 0o111) !== 0) return file } catch {}
  }
  return undefined
}
