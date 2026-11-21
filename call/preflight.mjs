// Before `npx ohkevin` starts a call: what this computer still needs, each with its fix in plain words. A call needs Node,
// the user's own Claude Code (recent enough, signed in) and Chrome, whose speech recognition the page uses.
// look() asks the computer; problems() decides, so tests give it any computer. Tested by preflight.test.mjs.
import { spawnSync } from 'node:child_process'
import { findClaude } from './claude-path.mjs'
import { findBrowser } from './platform.mjs'

export const NODE = '18.14.0'
export const CLAUDE = '2.1.323' // the oldest Claude Code the pinned Agent SDK is known to work with (VoiceCore's Runtime.minimumClaudeCode)

/// a ≥ b, for dotted version numbers ("v24.1.0", "2.1.323 (Claude Code)").
export function atLeast(a, b) {
  const n = v => String(v).match(/\d+(\.\d+)*/)?.[0].split('.').map(Number) ?? []
  const [x, y] = [n(a), n(b)]
  for (let i = 0; i < Math.max(x.length, y.length); i++) if ((x[i] ?? 0) !== (y[i] ?? 0)) return (x[i] ?? 0) > (y[i] ?? 0)
  return true
}

/// What this computer has: Node's version, Claude Code (its path, version, whether it is signed in), Chrome.
export function look(env = process.env) {
  const claude = findClaude(env)
  const ask = args => { // a .cmd on Windows runs only through the shell
    const r = spawnSync(claude, args, { encoding: 'utf8', timeout: 15000, shell: /\.(cmd|bat)$/i.test(claude ?? '') })
    return r.status === 0 ? r.stdout : null
  }
  let signedIn = null
  try { signedIn = claude ? JSON.parse(ask(['auth', 'status']) ?? 'null')?.loggedIn ?? null : null } catch {}
  return { node: process.version, claude, version: claude ? ask(['--version'])?.trim() ?? null : null, signedIn, chrome: findBrowser(undefined, env)?.file ?? null }
}

/// What stands between this computer and a call, in the order to fix them: [{ what, fix }]. Empty when all is there.
export function problems({ node, claude, version, signedIn, chrome }) {
  const out = []
  if (!atLeast(node, NODE)) out.push({ what: `Node ${node} is too old: a call needs ${NODE} or later.`, fix: 'Install the current Node from https://nodejs.org, then run npx ohkevin again.' })
  if (!claude) out.push({ what: 'Claude Code is not installed.', fix: 'Install it from https://code.claude.com/docs/en/overview, sign in, then run npx ohkevin again.' })
  else if (version && !atLeast(version, CLAUDE)) out.push({ what: `Claude Code ${version.split(' ')[0]} is too old: a call needs ${CLAUDE} or later.`, fix: 'Run: claude update' })
  if (claude && signedIn === false) out.push({ what: 'Claude Code is not signed in.', fix: 'Run: claude auth login' })
  if (!chrome) out.push({ what: 'Google Chrome is not installed: the call listens through its speech recognition.', fix: 'Install it from https://www.google.com/chrome/' })
  return out
}
