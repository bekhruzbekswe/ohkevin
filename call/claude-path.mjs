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

// The call's own settings, which the apps set on the server. Claude Code, and every command it runs, gets the user's environment
// without them: otherwise a check or a call started inside a call acts as if the Mac app had started it (no env: the SDK passes all).
export const CALL_SETTINGS = ['CALL_KEY', 'CALL_LAUNCHER', 'FIRST_CALL_FILE', 'KOKORO_DIR', 'NO_OPEN', 'OPEN_IN_APP', 'PORT', 'PROJECTS_DIR',
  'SPEAK_FIRST', 'TALKER_MODEL', 'VOICE_APPROVE', 'WORKER_MODEL']
export const claudeEnv = (env = process.env) => Object.fromEntries(Object.entries(env).filter(([k]) => !CALL_SETTINGS.includes(k)))
