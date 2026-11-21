// Replays recorded and hand-written calls through the real call page in a headless Chrome (throwaway profile, no
// microphone, no sound) and checks that the page does exactly what it did before: the same posts, the same words heard,
// the same clips played, the same pauses and cut-offs, at the same moments on a handed clock (replay/stubs.js). The
// listening and speaking code is frozen, so any difference here is a change in how a call feels.
//   REPLAY_WRITE=1 node --test voice.replay.test.mjs      records replay/expected/ from the page as it is now
//   REPLAY_CASES=<dir> REPLAY_OUT=<dir>                   also replays the cases in <dir>, and writes every log to <dir>
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { once } from 'node:events'

const HERE = path.dirname(fileURLToPath(import.meta.url)), DIR = path.join(HERE, 'replay')
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const PORT = 4810 // server.test.mjs runs beside this one on 4811
const sleep = ms => new Promise(r => setTimeout(r, ms))
const cases = dir => readdirSync(dir).filter(f => f.endsWith('.json')).sort().map(f => JSON.parse(readFileSync(path.join(dir, f), 'utf8')))
const all = [...cases(path.join(DIR, 'cases')), ...(process.env.REPLAY_CASES ? cases(process.env.REPLAY_CASES) : [])]

test('recorded and hand-written calls replay through the page exactly as before', { skip: !existsSync(CHROME) && 'Chrome is not installed' }, async t => {
  // The page and its modules, nothing else: every request the page makes is answered by the stubs.
  const files = { '/': 'index.html', '/ears.mjs': 'ears.mjs', '/stats.mjs': 'stats.mjs', '/voice.mjs': 'voice.mjs' }
  const server = createServer((req, res) => {
    const f = files[new URL(req.url, 'http://x').pathname], p = f && path.join(HERE, f)
    if (!p || !existsSync(p)) return void res.writeHead(404).end()
    res.writeHead(200, { 'content-type': f.endsWith('.html') ? 'text/html; charset=utf-8' : 'text/javascript; charset=utf-8', 'cache-control': 'no-store' }).end(readFileSync(p))
  })
  server.listen(PORT, '127.0.0.1'); await once(server, 'listening')
  const root = mkdtempSync(path.join(tmpdir(), 'call-replay-'))
  const chrome = spawn(CHROME, ['--headless=new', `--user-data-dir=${path.join(root, 'profile')}`, '--remote-debugging-port=0', '--mute-audio', '--no-first-run', 'about:blank'], { stdio: 'ignore' })
  t.after(async () => {
    chrome.kill('SIGKILL'); server.close()
    if (chrome.exitCode === null && chrome.signalCode === null) await once(chrome, 'exit')
    rmSync(root, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 })
  })
  let ws
  for (let i = 0; i < 150 && !ws; i++) {
    await sleep(100)
    try {
      const [port] = readFileSync(path.join(root, 'profile', 'DevToolsActivePort'), 'utf8').split('\n')
      ws = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(x => x.type === 'page')?.webSocketDebuggerUrl
    } catch {}
  }
  assert.ok(ws, 'Chrome opened its debugging port')
  const sock = new WebSocket(ws); await once(sock, 'open')
  let id = 0; const waiting = new Map(), loaded = []
  sock.onmessage = m => { const d = JSON.parse(m.data); if (d.method === 'Page.loadEventFired') loaded.push(1); waiting.get(d.id)?.(d); waiting.delete(d.id) }
  const send = (method, params = {}) => new Promise(r => { waiting.set(++id, r); sock.send(JSON.stringify({ id, method, params })) })
  const run = async expression => { const r = (await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })).result; if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text); return r.result.value }
  await send('Page.enable')
  const stubs = readFileSync(path.join(DIR, 'stubs.js'), 'utf8')

  const diffs = []
  for (const c of all) {
    const { identifier } = (await send('Page.addScriptToEvaluateOnNewDocument', { source: `window.__case = ${JSON.stringify(c.opts ?? {})};\n${stubs}` })).result
    loaded.length = 0
    await send('Page.navigate', { url: `http://127.0.0.1:${PORT}/?k=t${c.query ?? ''}` })
    for (let i = 0; i < 300 && !loaded.length; i++) await sleep(50)
    // Ready once the page's modules have loaded and been handed over (the page imports them the same way) and the stream is open.
    let ready = false
    for (let i = 0; i < 200 && !ready; i++) {
      ready = await run(`Promise.all(['ears', 'stats', 'voice'].map(n => import('/' + n + '.mjs?k=t').catch(() => 0))).then(() => new Promise(r => { const c = new MessageChannel(); c.port1.onmessage = r; c.port2.postMessage(0) })).then(() => !!window.__es)`)
      if (!ready) await sleep(50)
    }
    assert.ok(ready, `${c.name}: the page started`)
    const got = await run(`__replay(${JSON.stringify(c.steps)}, ${c.tail ?? 15000})`)
    await send('Page.removeScriptToEvaluateOnNewDocument', { identifier })
    if (process.env.REPLAY_OUT) { mkdirSync(process.env.REPLAY_OUT, { recursive: true }); writeFileSync(path.join(process.env.REPLAY_OUT, `${c.name}.json`), JSON.stringify(got, null, 1) + '\n') }
    const file = path.join(DIR, 'expected', `${c.name}.json`)
    if (!c.private && process.env.REPLAY_WRITE) { mkdirSync(path.dirname(file), { recursive: true }); writeFileSync(file, JSON.stringify(got, null, 1) + '\n') }
    else if (!c.private) {
      const want = JSON.parse(readFileSync(file, 'utf8'))
      try { assert.deepEqual(got, want) } catch { const i = Math.max(got.length, want.length) - 1; let at = 0; while (at < i && JSON.stringify(got[at]) === JSON.stringify(want[at])) at++; diffs.push(`${c.name}: first difference at entry ${at}: ${JSON.stringify(got[at])} where it was ${JSON.stringify(want[at])}`) }
    }
  }
  assert.deepEqual(diffs, [])
})
