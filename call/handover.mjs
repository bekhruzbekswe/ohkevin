// Opening a call in the Claude desktop app when the call server stops. The worker's session is handed over through
// the CLI's own command, `claude --desktop --resume <id>`, which opens it in the app with its history, folder and title.
// The CLI, the waits and the process lookups are passed in, so tests never start the CLI or the app. Tested by handover.test.mjs.
import { spawn } from 'node:child_process'
import { findClaude } from './claude-path.mjs'
import { children, resumeLine, withTerminal } from './platform.mjs'

// The session lives with its folder: run from anywhere else the CLI finds no conversation, so the line goes there first.
export const command = (id, cwd, platform) => resumeLine(id, cwd, platform)

const sleep = ms => new Promise(r => setTimeout(r, ms))

// Waits until this server has no child processes left (worker, talker, voice). The app must never take a session a live
// worker still writes to. A closed worker is gone within 7 s: the SDK waits 2 s, sends SIGTERM, then SIGKILL 5 s later.
export async function childrenGone({ pid = process.pid, list = children, wait = sleep, tries = 60, every = 150 } = {}) {
  for (let i = 0; i < tries; i++) { if (!(await list(pid)).length) return true; await wait(every) }
  return false
}

// The CLI's hand-over needs a terminal for its input and output; it prints "Opening session <id> in Claude Desktop" there.
const CLAUDE = findClaude() ?? 'claude' // the app gives the user's own (CLAUDE_PATH); a terminal run finds it on PATH
// Windows runs a claude.cmd only through the shell; the arguments are fixed flags and a session id, nothing to quote.
const shell = file => /\.(cmd|bat)$/i.test(file)
const runCli = (args, cwd) => new Promise(r => spawn(CLAUDE, args, { cwd, stdio: 'inherit', shell: shell(CLAUDE) }).once('error', () => r(-1)).once('exit', code => r(code)))
// Started by an app there is no terminal, so one is lent to the CLI (platform.mjs, withTerminal); cli is only swapped in tests.
export const lendTerminal = (args, cwd, cli = CLAUDE) => new Promise(r =>
  spawn(...withTerminal(cli, args), { cwd, stdio: ['ignore', 'inherit', 'inherit'], shell: shell(cli) }).once('error', () => r(-1)).once('exit', code => r(code)))

// At hang-up. id: the worker's session, absent when no work was handed over; open: the app may be opened (Ctrl-C, not a kill);
// tty: the server runs in a terminal; rename(): writes the call's title into the session again.
// Returns 'none', 'opened', or 'printed' when it prints the command that opens the call later instead.
export async function handOver({ id, cwd, open, tty, rename, run = runCli, gone = childrenGone, log = console.log }) {
  if (!id) return 'none'
  const free = await gone()
  try { await rename() } catch {} // the app reads the title from the end of the transcript
  if (open && tty && free && (await run(['--desktop', '--resume', id], cwd)) === 0) return 'opened'
  log(`To open this call in the Claude app:  ${command(id, cwd)}`)
  return 'printed'
}

// With several workers: each session is handed over in turn, from its own folder; a worker that never did any work has none.
// sessions: [{ id, cwd, rename }]; o: the rest of what handOver takes (open, tty, and in tests run, gone, log). Returns each result.
export async function handOverAll(sessions, o) {
  const results = []
  for (const s of sessions) results.push(await handOver({ ...o, ...s }))
  return results
}

// Open in Claude on a worker's card, during the call. The worker has already been closed (server.mjs), but its Claude
// Code process may still be going away, and the CLI refuses a session another process holds ("… is open in another
// terminal"): so it is tried again, every half second, until that process is gone. Any other refusal is final.
// Returns { ok } or { ok: false, why }: the CLI's own last line.
const lastLine = out => String(out).replace(/\x1b\[[0-9;?]*[A-Za-z]/g, '').split(/\r?\n/).map(l => l.trim()).filter(Boolean).at(-1) ?? ''
const HELD = /open in another terminal/i
export const capture = (args, cwd, cli = CLAUDE) => new Promise(r => { // as lendTerminal, but keeps what the CLI said
  let out = ''
  const p = spawn(...withTerminal(cli, args), { cwd, stdio: ['ignore', 'pipe', 'pipe'], shell: shell(cli) })
  p.stdout.on('data', d => { out += d }); p.stderr.on('data', d => { out += d })
  p.once('error', e => r({ code: -1, out: e.message })).once('exit', code => r({ code, out }))
})
export async function openOne({ id, cwd, rename, run = capture, wait = sleep, tries = 24, every = 500 }) {
  try { await rename() } catch {}
  for (let i = 1; ; i++) {
    const { code, out } = await run(['--desktop', '--resume', id], cwd)
    if (code === 0) return { ok: true }
    const why = lastLine(out)
    if (!HELD.test(why) || i >= tries) return { ok: false, why }
    await wait(every)
  }
}
