// What run.mjs (recorded calls) and live.mjs (the owner's trial) share: a fresh call server, and Chrome with hook.js
// injected into the call page, every [m2] event handed to a callback.
import { execFileSync, spawn } from 'node:child_process'
import { mkdirSync, readdirSync, readFileSync, rmdirSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url)), CALL = path.join(HERE, '../../call')
export const PORT = 4820, DEBUG_PORT = 4821, KEY = 'm2key', base = `http://127.0.0.1:${PORT}`
// The local voice, found as the launcher finds it when the server's own default has none: KOKORO_DIR, else Spotlight.
const KOKORO = process.env.KOKORO_DIR ?? execFileSync('/usr/bin/mdfind', ['-name', 'kokoro-v1.0.onnx'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })
  .split('\n').find(f => f.endsWith('/kokoro-v1.0.onnx'))?.slice(0, -'/kokoro-v1.0.onnx'.length)
export const sleep = ms => new Promise(r => setTimeout(r, ms))
const exited = p => new Promise(r => (p.exitCode != null || p.signalCode ? r() : p.on('exit', r)))

// ── a call server with an empty project folder and projects folder under `scratch`; stop(logFile) ends it ──
export async function startServer(scratch, env = {}) {
  const since = Date.now() - 1000
  const project = path.join(scratch, 'project'), projects = path.join(scratch, 'projects')
  mkdirSync(project, { recursive: true }); mkdirSync(projects, { recursive: true })
  const out = []
  const p = spawn('node', ['server.mjs', project], { cwd: CALL, stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env, NO_OPEN: '1', CALL_KEY: KEY, PORT: String(PORT), WORKER_MODEL: 'haiku', OPEN_IN_APP: '0', PROJECTS_DIR: projects, ...(KOKORO && { KOKORO_DIR: KOKORO }), ...env } })
  let ready
  const up = new Promise(r => (ready = r))
  p.on('exit', ready)
  for (const s of [p.stdout, p.stderr]) s.on('data', d => { out.push(String(d)); if (/Voice:\s+Kokoro/.test(String(d))) ready() })
  await Promise.race([up, sleep(180000)]) // Kokoro warms up slowly on a busy Mac: slow is not a failure
  if (!out.join('').includes('Kokoro')) { p.kill(); throw new Error('server did not start with Kokoro:\n' + out.join('')) }
  // call/tts.py makes an output folder per start and leaves it behind, emptied: remove the ones this server made
  const tidy = () => { for (const d of readdirSync(tmpdir())) if (d.startsWith('claude-voice-')) try { if (statSync(path.join(tmpdir(), d)).birthtimeMs >= since) rmdirSync(path.join(tmpdir(), d)) } catch {} }
  return { stop: async file => { p.kill('SIGTERM'); await exited(p); tidy(); mkdirSync(path.dirname(file), { recursive: true }); writeFileSync(file, out.join('').replaceAll(scratch, '<scratch>')) } }
}

// ── Chrome with `args`, the call page opened with hook.js before its own script; onLine(event) gets every event ──
// Returns { send(method, params), closed (the page's window is gone), kill() }; the caller removes `profile`.
export async function openCall(profile, args, onLine) {
  const proc = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [`--remote-debugging-port=${DEBUG_PORT}`,
    `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check', ...args, 'about:blank'], { stdio: 'ignore' })
  const kill = async () => { proc.kill(); await exited(proc) }
  try {
    let pages
    for (let i = 0; i < 150 && !pages; i++) { await sleep(200); try { pages = await (await fetch(`http://127.0.0.1:${DEBUG_PORT}/json/list`)).json() } catch {} }
    const ws = new WebSocket(pages.find(t => t.type === 'page').webSocketDebuggerUrl)
    await new Promise(r => (ws.onopen = r))
    const closed = new Promise(r => (ws.onclose = r)) // Chrome stays running on a Mac after its last window closes, so watch the page
    let id = 0
    const waiting = new Map()
    ws.onmessage = m => {
      const d = JSON.parse(m.data)
      if (d.method === 'Runtime.consoleAPICalled') {
        const text = d.params.args.map(a => a.value ?? a.description).join(' ')
        onLine(text.startsWith('[m2] ') ? JSON.parse(text.slice(5)) : { k: 'log', t: d.params.timestamp, text })
      }
      if (d.method === 'Runtime.exceptionThrown') onLine({ k: 'log', t: Date.now(), text: 'ERROR ' + (d.params.exceptionDetails.exception?.description ?? d.params.exceptionDetails.text) })
      waiting.get(d.id)?.(d); waiting.delete(d.id)
    }
    const send = (method, params = {}) => new Promise(r => { const i = ++id; waiting.set(i, r); ws.send(JSON.stringify({ id: i, method, params })) })
    await send('Runtime.enable'); await send('Page.enable')
    await send('Page.addScriptToEvaluateOnNewDocument', { source: readFileSync(path.join(HERE, 'hook.js'), 'utf8') })
    await send('Page.navigate', { url: `${base}/?k=${KEY}` })
    return { send, closed, kill }
  } catch (e) { await kill(); throw e }
}
