// The user's own Claude Code: CLAUDE_PATH (the apps always set it), else the first executable `claude` on PATH, as an absolute path.
// Unset and not found, the SDK looks for its own binary, which the apps leave out.
import path from 'node:path'
import { statSync } from 'node:fs'

// On Windows a program on PATH carries one of PATHEXT's endings (claude.exe, claude.cmd) and has no executable bit.
export function findClaude(env = process.env, platform = process.platform) {
  if (env.CLAUDE_PATH) return env.CLAUDE_PATH
  const win = platform === 'win32', p = win ? path.win32 : path.posix
  const names = win ? (env.PATHEXT ?? '.EXE;.CMD;.BAT').split(';').filter(Boolean).map(e => 'claude' + e.toLowerCase()) : ['claude']
  for (const dir of (env.PATH ?? env.Path ?? '').split(win ? ';' : ':')) {
    if (!dir) continue
    for (const name of names) {
      const file = p.resolve(dir, name)
      try { if (statSync(file).isFile() && (win || (statSync(file).mode & 0o111) !== 0)) return file } catch {}
    }
  }
  return undefined
}
