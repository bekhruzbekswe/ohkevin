// What differs between macOS, Windows and Linux, in one place: where Oh Kevin keeps its files, which browser opens the
// call, the child processes of a process, a terminal for the Claude Code CLI, and the line that reopens a session.
// Every function takes the platform (and env), so tests run each case on any machine. Tested by platform.test.mjs.
import { execFile, spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const NAME = 'Oh Kevin' // the apps' folder name (VoiceCore's Product.folder)

/// Oh Kevin's own folder: the Mac app's, where it keeps the local voice and first-call.json; the platform's usual place elsewhere.
export function dataDir(platform = process.platform, env = process.env, home = os.homedir()) {
  if (platform === 'darwin') return path.posix.join(home, 'Library/Application Support', NAME)
  if (platform === 'win32') return path.win32.join(env.APPDATA ?? path.win32.join(home, 'AppData/Roaming'), NAME)
  return path.posix.join(env.XDG_DATA_HOME || path.posix.join(home, '.local/share'), 'oh-kevin')
}

/// Chrome: the browser with the speech recognition the page uses (Chromium too, on Linux). Where it is installed; names on PATH on Linux.
export function browsers(platform = process.platform, env = process.env, home = os.homedir()) {
  if (platform === 'darwin') return [
    { name: 'Google Chrome', file: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' },
    { name: 'Google Chrome', file: path.posix.join(home, 'Applications/Google Chrome.app/Contents/MacOS/Google Chrome') },
  ]
  if (platform === 'win32') {
    const roots = [env.ProgramFiles, env['ProgramFiles(x86)'], env.LOCALAPPDATA].filter(Boolean)
    return roots.map(r => ({ name: 'Google Chrome', file: path.win32.join(r, 'Google/Chrome/Application/chrome.exe') }))
  }
  const dirs = (env.PATH ?? '').split(':').filter(Boolean)
  return ['google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser']
    .flatMap(n => dirs.map(d => ({ name: n.startsWith('chromium') ? 'Chromium' : 'Google Chrome', file: path.posix.join(d, n) })))
}

/// The first browser of `browsers` that is there, or undefined.
export const findBrowser = (platform = process.platform, env = process.env, home = os.homedir(), exists = existsSync) =>
  browsers(platform, env, home).find(b => exists(b.file))

/// Opens link in Chrome, else in the default browser. Never waits for the browser.
export function openBrowser(link, platform = process.platform, env = process.env) {
  const found = findBrowser(platform, env)
  const run = (cmd, args) => spawn(cmd, args, { detached: true, stdio: 'ignore' }).once('error', () => {}).unref()
  if (platform === 'darwin') run('open', found ? ['-a', found.name, link] : [link])
  else if (found) run(found.file, [link])
  else if (platform === 'win32') run('cmd', ['/c', 'start', '', link]) // start's first argument is the window title
  else run('xdg-open', [link])
}

/// The child processes of pid, as a list of pids. On Windows through PowerShell (less itself: it is a child too); elsewhere pgrep,
/// which exits 1 when there are none and never lists itself.
export const children = (pid, platform = process.platform) => new Promise(r => platform === 'win32'
  ? execFile('powershell', ['-NoProfile', '-Command', `(Get-CimInstance Win32_Process -Filter "ParentProcessId=${Number(pid)}" | Where-Object ProcessId -ne $PID).ProcessId`],
    (err, out) => r(err ? [] : out.split(/\r?\n/).map(s => s.trim()).filter(Boolean)))
  : execFile('pgrep', ['-P', String(pid)], (err, out) => r(err ? [] : out.split('\n').filter(Boolean))))

/// How to run the Claude Code CLI with a terminal of its own when the server has none: macOS's and Linux's `script` lend one
/// (stdin /dev/null: script refuses a socket there). Windows has no `script`: the CLI runs as it is.
const sh = s => `'${String(s).replaceAll("'", `'\\''`)}'`
export function withTerminal(cli, args, platform = process.platform) {
  if (platform === 'darwin') return ['/usr/bin/script', ['-q', '/dev/null', cli, ...args]]
  if (platform === 'win32') return [cli, args]
  return ['script', ['-q', '-e', '-c', [cli, ...args].map(sh).join(' '), '/dev/null']] // -e: the CLI's own exit code
}

/// The line a person types to reopen a session in the Claude app, from its own folder.
export function resumeLine(id, cwd, platform = process.platform) {
  if (platform === 'win32') return `${cwd ? `cd /d "${cwd}" && ` : ''}claude --desktop --resume ${id}`
  return `${cwd ? `cd ${sh(cwd)} && ` : ''}claude --desktop --resume ${id}`
}
