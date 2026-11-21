// Starts the real call server (no Claude is spoken to: nothing is ever sent) on a free port and checks what it says to a browser
// and to a person at a terminal, and, in a headless Chrome with a throwaway profile, what the real page does. One file, so the
// tests run one after another on the one port. Needs the SDK installed, as the server does.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { once } from 'node:events'
import { createServer } from 'node:net'
import { chmodSync } from 'node:fs'
import { findClaude } from './claude-path.mjs'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const SERVER = path.join(HERE, 'server.mjs')
// A port free on this Mac now, so two checkouts' checks never collide
const PORT = await new Promise(done => { const s = createServer().listen(0, '127.0.0.1', () => { const { port } = s.address(); s.close(() => done(port)) }) })
const KEY = 'testkey'
// Every server here is past its first call, unless a test says otherwise: none reads or writes the real first-call file.
const DONE = path.join(mkdtempSync(path.join(tmpdir(), 'call-first-')), 'first-call.json')
writeFileSync(DONE, JSON.stringify({ greeted: true, hinted: true }))
process.env.FIRST_CALL_FILE = DONE

test('Claude Code: CLAUDE_PATH wins, else the first executable claude on PATH as an absolute path, else the SDK\'s own', () => {
  const root = mkdtempSync(path.join(tmpdir(), 'call-claude-')), bin = path.join(root, 'bin'), other = path.join(root, 'other')
  mkdirSync(bin); mkdirSync(other)
  writeFileSync(path.join(other, 'claude'), '#!/bin/sh\n'); chmodSync(path.join(other, 'claude'), 0o644) // not executable: passed over
  writeFileSync(path.join(bin, 'claude'), '#!/bin/sh\n'); chmodSync(path.join(bin, 'claude'), 0o755)
  assert.equal(findClaude({ CLAUDE_PATH: '/u/claude', PATH: bin }), '/u/claude')
  assert.equal(findClaude({ PATH: `${other}${path.delimiter}${bin}` }), path.join(bin, 'claude'))
  assert.equal(findClaude({ PATH: path.relative(process.cwd(), bin) }), path.join(bin, 'claude')) // a relative PATH entry is made absolute
  assert.equal(findClaude({ PATH: other }), undefined)
  assert.equal(findClaude({}), undefined)
  rmSync(root, { recursive: true, force: true })
})

test('it refuses to start without a real project folder of its own, with exit code 2', () => {
  for (const [args, said] of [[[], /No project folder/], [['/nonexistent-folder'], /is not a folder/], [[HERE], /own folder/]]) {
    const r = spawnSync('node', [SERVER, ...args], { encoding: 'utf8', cwd: HERE, env: { ...process.env, NO_OPEN: '1', PORT: String(PORT) } })
    assert.equal(r.status, 2, args.join())
    assert.match(r.stderr, said)
    assert.match(r.stderr, /node server\.mjs <project-folder>/)
  }
})

test('a running server: the old-link page, the short word for scripts, and defaults that are no one\'s machine', async t => {
  const root = mkdtempSync(path.join(tmpdir(), 'call-server-test-'))
  const project = path.join(root, 'app'); mkdirSync(project)
  const env = { ...process.env, NO_OPEN: '1', PORT: String(PORT), CALL_KEY: KEY, WORKER_MODEL: 'haiku', OPEN_IN_APP: '0' }
  delete env.PROJECTS_DIR; delete env.KOKORO_DIR; delete env.KOKORO_PYTHON; delete env.VOICE_APPROVE
  const kid = spawn('node', [SERVER, project], { env, stdio: ['ignore', 'pipe', 'pipe'] })
  let out = ''
  kid.stdout.on('data', d => { out += d })
  t.after(async () => { kid.kill('SIGTERM'); await once(kid, 'exit'); rmSync(root, { recursive: true, force: true }) })
  for (let i = 0; i < 100 && !out.includes('Call page:'); i++) await new Promise(r => setTimeout(r, 100))
  assert.match(out, /Call page:/)

  const base = `http://127.0.0.1:${PORT}`
  const page = await fetch(base + '/', { headers: { accept: 'text/html,application/xhtml+xml' } })
  assert.equal(page.status, 403)
  assert.match(page.headers.get('content-type'), /text\/html/)
  assert.match(await page.text(), /This link belongs to an earlier call\. Use the link the call server printed\./) // a terminal; under the launcher it points at the menu bar
  const api = await fetch(base + '/events?k=wrong')
  assert.equal(api.status, 403)
  assert.equal(await api.text(), 'forbidden')

  const post = (route, body, k = KEY) => fetch(`${base}${route}?k=${k}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) })
  assert.equal((await post('/open', { name: 'api' }, 'wrong')).status, 403) // Open in Claude: only the page that holds the key
  for (const body of [{}, { name: 'nobody' }, { name: 'api; rm -rf /' }]) assert.equal((await post('/open', body)).status, 204, JSON.stringify(body)) // no such worker: nothing happens

  const sound = await fetch(`${base}/problem.mp3?k=${KEY}`) // the problem sound the page plays
  assert.equal(sound.status, 200)
  assert.equal(sound.headers.get('content-type'), 'audio/mpeg')
  assert.ok((await sound.arrayBuffer()).byteLength > 10000)

  const ev = await fetch(`${base}/events?k=${KEY}`)
  let seen = ''
  for await (const chunk of ev.body) { seen += Buffer.from(chunk); if (seen.includes('"hello"')) break }
  const hello = JSON.parse(seen.split('\n').find(l => l.includes('"hello"')).slice(6))
  assert.equal(hello.projects, root) // the project's parent folder, not a folder of anyone's machine
  assert.equal(hello.spokenYes, 'safe') // the page's help says what a spoken yes approves, as set
  assert.match(out, /Claude Code: +haiku, auto mode/)
  assert.match(out, new RegExp(`Projects: +${root.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} `))
  for (let i = 0; i < 100 && !out.includes('Voice:'); i++) await new Promise(r => setTimeout(r, 100)) // a voice that is installed says so once it is ready
  assert.match(out, /Voice: .*(Library\/Application Support\/Claude Voice\/Kokoro|Kokoro, on this Mac)/) // checked while no Kokoro is at the default place, or it is running
})

test('a kokoro-runner in the voice folder is started in place of Python, with the folder as its one argument', async t => {
  const root = mkdtempSync(path.join(tmpdir(), 'call-server-test-'))
  const project = path.join(root, 'app'); mkdirSync(project)
  const kokoro = path.join(root, 'kokoro'); mkdirSync(kokoro)
  writeFileSync(path.join(kokoro, 'kokoro-runner'), `#!/bin/sh\necho "$1" > "${root}/arg"\necho '{"ready":true,"voices":["af_heart","bm_fable"],"threads":3}'\ncat >/dev/null\n`, { mode: 0o755 })
  const env = { ...process.env, NO_OPEN: '1', PORT: String(PORT), CALL_KEY: KEY, WORKER_MODEL: 'haiku', OPEN_IN_APP: '0', KOKORO_DIR: kokoro }
  const kid = spawn('node', [SERVER, project], { env, stdio: ['ignore', 'pipe', 'pipe'] })
  let out = ''
  kid.stdout.on('data', d => { out += d })
  t.after(async () => { kid.kill('SIGTERM'); await once(kid, 'exit'); rmSync(root, { recursive: true, force: true }) })
  for (let i = 0; i < 100 && !out.includes('Kokoro, on this Mac'); i++) await new Promise(r => setTimeout(r, 100))
  assert.match(out, /Voice: +Kokoro, on this Mac, 3 cores/)
  assert.equal(readFileSync(path.join(root, 'arg'), 'utf8').trim(), kokoro)
})

test('under the launcher, the old-link page points at the menu bar', async t => {
  const root = mkdtempSync(path.join(tmpdir(), 'call-server-test-'))
  const project = path.join(root, 'app'); mkdirSync(project)
  const env = { ...process.env, NO_OPEN: '1', PORT: String(PORT), CALL_KEY: KEY, WORKER_MODEL: 'haiku', OPEN_IN_APP: '0', CALL_LAUNCHER: '1' }
  const kid = spawn('node', [SERVER, project], { env, stdio: ['pipe', 'pipe', 'pipe'] }) // the launcher's pipe stays open
  let out = ''
  kid.stdout.on('data', d => { out += d })
  t.after(async () => { kid.kill('SIGTERM'); await once(kid, 'exit'); rmSync(root, { recursive: true, force: true }) })
  for (let i = 0; i < 100 && !out.includes('Call page:'); i++) await new Promise(r => setTimeout(r, 100))
  const page = await fetch(`http://127.0.0.1:${PORT}/`, { headers: { accept: 'text/html' } })
  assert.match(await page.text(), /earlier call\. Start a new call from the menu bar\./)
})

test('the first call: hello says first, a short hello gets the fixed line without the talker, and both are remembered', async t => {
  const root = mkdtempSync(path.join(tmpdir(), 'call-server-test-'))
  const project = path.join(root, 'app'); mkdirSync(project)
  const file = path.join(root, 'first-call.json')
  const env = { ...process.env, NO_OPEN: '1', PORT: String(PORT), CALL_KEY: KEY, WORKER_MODEL: 'haiku', OPEN_IN_APP: '0', CALL_LAUNCHER: '1', FIRST_CALL_FILE: file }
  const kid = spawn('node', [SERVER, project], { env, stdio: ['pipe', 'pipe', 'ignore'] })
  let out = ''
  kid.stdout.on('data', d => { out += d })
  const streams = new AbortController()
  t.after(async () => { streams.abort(); kid.kill('SIGTERM'); await once(kid, 'exit'); rmSync(root, { recursive: true, force: true }) })
  for (let i = 0; i < 100 && !out.includes('Call page:'); i++) await new Promise(r => setTimeout(r, 100))
  const base = `http://127.0.0.1:${PORT}`
  const said = []
  fetch(`${base}/events?k=${KEY}`, { signal: streams.signal }).then(async r => {
    for await (const chunk of r.body) for (const l of Buffer.from(chunk).toString().split('\n')) if (l.startsWith('data: ')) said.push(JSON.parse(l.slice(6)))
  }).catch(() => {})
  const until = async f => { for (let i = 0; i < 50 && !f(); i++) await new Promise(r => setTimeout(r, 100)); return f() }
  const post = (where, data) => fetch(`${base}${where}`, { method: 'POST', headers: { 'x-key': KEY }, body: JSON.stringify(data) }).then(r => r.status)

  const hello = await until(() => said.find(e => e.type === 'hello'))
  assert.equal(hello.first, true); assert.equal(hello.hint, true)
  assert.equal(await post('/say', { text: 'Hello Kevin.' }), 204)
  assert.ok(await until(() => said.some(e => e.type === 'say')))
  assert.deepEqual(said.filter(e => e.type === 'say').map(e => e.text), ['Hello. I hear you clearly. What shall we do first?'])
  assert.ok(said.some(e => e.type === 'turn_end'), 'the bubble is closed')
  assert.deepEqual(JSON.parse(readFileSync(file, 'utf8')), { greeted: true, hinted: false })
  assert.equal(await post('/hinted', {}), 204)
  assert.deepEqual(JSON.parse(readFileSync(file, 'utf8')), { greeted: true, hinted: true })
})

test('a page says its microphone is blocked: the launcher\'s feed hears why, again on reconnect, until it hears or closes', async t => {
  const root = mkdtempSync(path.join(tmpdir(), 'call-server-test-'))
  const project = path.join(root, 'app'); mkdirSync(project)
  const env = { ...process.env, NO_OPEN: '1', PORT: String(PORT), CALL_KEY: KEY, WORKER_MODEL: 'haiku', OPEN_IN_APP: '0', CALL_LAUNCHER: '1' }
  const kid = spawn('node', [SERVER, project], { env, stdio: ['pipe', 'pipe', 'ignore'] }) // the launcher's pipe stays open
  let out = ''
  kid.stdout.on('data', d => { out += d })
  const streams = new AbortController()
  t.after(async () => { streams.abort(); kid.kill('SIGTERM'); await once(kid, 'exit'); rmSync(root, { recursive: true, force: true }) })
  for (let i = 0; i < 100 && !out.includes('Call page:'); i++) await new Promise(r => setTimeout(r, 100))
  const base = `http://127.0.0.1:${PORT}`
  const read = (url, into) => fetch(url, { signal: streams.signal }).then(async r => {
    for await (const chunk of r.body) for (const l of Buffer.from(chunk).toString().split('\n')) if (l.startsWith('data: ')) into.push(JSON.parse(l.slice(6)))
  }).catch(() => {})
  const said = [], page = new AbortController()
  fetch(`${base}/events?k=${KEY}`, { signal: page.signal }).catch(() => {}) // a call page
  read(`${base}/events?k=${KEY}&watch=1`, said) // the launcher
  const mic = async (list, want) => { for (let i = 0; i < 30 && list.filter(e => e.type === 'mic').at(-1)?.blocked !== want; i++) await new Promise(r => setTimeout(r, 100)); return list.filter(e => e.type === 'mic').at(-1)?.blocked }
  const post = blocked => fetch(`${base}/mic`, { method: 'POST', headers: { 'x-key': KEY }, body: JSON.stringify({ blocked }) }).then(r => r.status)

  assert.equal(await post('mac'), 204)
  assert.equal(await mic(said, 'mac'), 'mac')
  const again = []
  read(`${base}/events?k=${KEY}&watch=1`, again)
  assert.equal(await mic(again, 'mac'), 'mac', 'a feed that reconnects is told again')
  await post('nonsense')
  await post('chrome')
  assert.equal(await mic(said, 'chrome'), 'chrome')
  assert.deepEqual(said.filter(e => e.type === 'mic').map(e => e.blocked), ['mac', 'chrome'], 'nonsense is ignored')
  await post('')
  assert.equal(await mic(said, ''), '', 'it hears again')
  await post('mac')
  page.abort()
  assert.equal(await mic(said, ''), '', 'no call page, nothing blocked')
})

test('the voice\'s state reaches the launcher: who has the floor, whether it is muted, and that /mute is relayed to the page', async t => {
  const root = mkdtempSync(path.join(tmpdir(), 'call-server-test-'))
  const project = path.join(root, 'app'); mkdirSync(project)
  const env = { ...process.env, NO_OPEN: '1', PORT: String(PORT), CALL_KEY: KEY, WORKER_MODEL: 'haiku', OPEN_IN_APP: '0', CALL_LAUNCHER: '1' }
  const kid = spawn('node', [SERVER, project], { env, stdio: ['pipe', 'pipe', 'ignore'] })
  let out = ''
  kid.stdout.on('data', d => { out += d })
  const streams = new AbortController()
  t.after(async () => { streams.abort(); kid.kill('SIGTERM'); await once(kid, 'exit'); rmSync(root, { recursive: true, force: true }) })
  for (let i = 0; i < 100 && !out.includes('Call page:'); i++) await new Promise(r => setTimeout(r, 100))
  const base = `http://127.0.0.1:${PORT}`
  const read = (url, into) => fetch(url, { signal: streams.signal }).then(async r => {
    for await (const chunk of r.body) for (const l of Buffer.from(chunk).toString().split('\n')) if (l.startsWith('data: ')) into.push(JSON.parse(l.slice(6)))
  }).catch(() => {})
  const page = [], pageStream = new AbortController(), feed = []
  fetch(`${base}/events?k=${KEY}`, { signal: pageStream.signal }).then(async r => {
    for await (const chunk of r.body) for (const l of Buffer.from(chunk).toString().split('\n')) if (l.startsWith('data: ')) page.push(JSON.parse(l.slice(6)))
  }).catch(() => {})
  read(`${base}/events?k=${KEY}&watch=1`, feed)
  const post = (route, body) => fetch(`${base}${route}`, { method: 'POST', headers: { 'x-key': KEY }, body: JSON.stringify(body) }).then(r => r.status)
  const last = async (list, type, want) => { for (let i = 0; i < 30 && JSON.stringify(list.filter(e => e.type === type).at(-1)) !== JSON.stringify({ type, ...want }); i++) await new Promise(r => setTimeout(r, 100)); return list.filter(e => e.type === type).at(-1) }

  assert.deepEqual(await last(feed, 'voice', { state: 'listening', canMute: false }), { type: 'voice', state: 'listening', canMute: false }, 'told on connect; no page has reported a mute state yet')
  assert.match(feed.find(e => e.type === 'hello')?.boot ?? '', /^[0-9a-f]{8}$/, 'hello carries this process\'s own mark, so a page can tell a restarted server from the one it lost')
  await post('/live', { voice: true })
  assert.equal((await last(feed, 'voice', { state: 'speaking', canMute: false })).state, 'speaking')
  await post('/live', { voice: false, muted: false })
  assert.deepEqual(await last(feed, 'voice', { state: 'listening', canMute: true }), { type: 'voice', state: 'listening', canMute: true }, 'a page that reports muted can be asked to mute')
  await post('/live', { muted: true })
  assert.equal((await last(feed, 'voice', { state: 'muted', canMute: true })).state, 'muted')
  assert.equal(await post('/mute', { on: false }), 204)
  assert.deepEqual(await last(page, 'mute', { on: false }), { type: 'mute', on: false }, 'the page is asked')
  await post('/mute', { on: 'nonsense' })
  assert.deepEqual(page.filter(e => e.type === 'mute').map(e => e.on), [false], 'nonsense is ignored')
  pageStream.abort()
  assert.deepEqual(await last(feed, 'voice', { state: 'listening', canMute: false }), { type: 'voice', state: 'listening', canMute: false }, 'no page, no mute state')
})

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const sleep = ms => new Promise(r => setTimeout(r, ms))

// A real server started as the launcher starts it, and its page opened with go=1 in a headless Chrome (throwaway profile,
// fake microphone): returns `run`, which evaluates an expression in the page.
async function launcherPage(t) {
  const root = mkdtempSync(path.join(tmpdir(), 'call-page-test-')), project = path.join(root, 'app'); mkdirSync(project)
  const env = { ...process.env, NO_OPEN: '1', PORT: String(PORT), CALL_KEY: KEY, WORKER_MODEL: 'haiku', OPEN_IN_APP: '0', CALL_LAUNCHER: '1' }
  const server = spawn('node', [SERVER, project], { env, stdio: ['pipe', 'pipe', 'ignore'] }) // CALL_LAUNCHER: the stdin pipe must stay open
  let out = ''
  server.stdout.on('data', d => { out += d })
  const chrome = spawn(CHROME, ['--headless=new', `--user-data-dir=${path.join(root, 'profile')}`, '--remote-debugging-port=0', '--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream', '--mute-audio', '--no-first-run', 'about:blank'], { stdio: 'ignore' })
  t.after(async () => {
    chrome.kill('SIGKILL'); server.kill('SIGTERM'); await Promise.all([chrome, server].map(p => p.exitCode === null && p.signalCode === null ? once(p, 'exit') : 0)) // the server may be gone already
    rmSync(root, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 })
  })
  for (let i = 0; i < 100 && !out.includes('Call page:'); i++) await sleep(100)
  let ws
  for (let i = 0; i < 100 && !ws; i++) {
    await sleep(100)
    try {
      const [port] = readFileSync(path.join(root, 'profile', 'DevToolsActivePort'), 'utf8').split('\n')
      ws = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(x => x.type === 'page')?.webSocketDebuggerUrl
    } catch {}
  }
  assert.ok(ws, 'Chrome opened its debugging port')
  const sock = new WebSocket(ws); await once(sock, 'open')
  let id = 0; const waiting = new Map()
  sock.onmessage = m => { const d = JSON.parse(m.data); waiting.get(d.id)?.(d); waiting.delete(d.id) }
  const send = (method, params = {}) => new Promise(r => { waiting.set(++id, r); sock.send(JSON.stringify({ id, method, params })) })
  const run = async expression => { const r = (await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })).result; if (r.exceptionDetails) throw new Error(r.result.description); return r.result.value }
  await send('Page.enable')
  await send('Page.addScriptToEvaluateOnNewDocument', { source: '(() => { window.__streams = []; const Real = EventSource; EventSource = class extends Real { constructor(...a) { super(...a); __streams.push(this) } } })()' }) // to reach the page's stream
  await send('Page.addScriptToEvaluateOnNewDocument', { source: '(() => { window.__recs = []; const R = webkitSpeechRecognition; window.SpeechRecognition = window.webkitSpeechRecognition = class extends R { constructor() { super(); __recs.push(this) } } })()' }) // and its recogniser (voice.mjs keeps its own)
  await send('Page.navigate', { url: `http://127.0.0.1:${PORT}/?k=${KEY}&go=1` })
  let button
  for (let i = 0; i < 100 && button !== 'End call'; i++) { await sleep(100); button = await run("document.getElementById('callview')?.hidden === false ? 'End call' : 'Start call'") } // go=1 starts the call by itself: the call screen shows
  assert.equal(button, 'End call')
  return { run, navigate: url => send('Page.navigate', { url }) }
}

test('a dropped event stream ends the call on a launcher page, but never hangs up the server', { skip: !existsSync(CHROME) && 'Chrome is not installed' }, async t => {
  const { run } = await launcherPage(t)
  await run("window.sent = []; const f = fetch; fetch = (u, o) => (window.sent.push(String(u)), f(u, o)); __streams[0].dispatchEvent(new Event('error'))") // the stream drops
  await sleep(500)
  assert.deepEqual(await run('window.sent.filter(u => u.includes("hangup"))'), [], 'no /hangup was sent')
  assert.equal(await run("document.getElementById('state').textContent"), 'Reconnecting', 'the call stays up, saying so') // the stream object is still open here, so the browser is "trying again"
  assert.equal(await run("document.getElementById('mute').disabled"), true)
  assert.equal(await run("document.getElementById('call').disabled"), true)
  const alive = await fetch(`http://127.0.0.1:${PORT}/events?k=${KEY}`, { signal: AbortSignal.timeout(1000) }).then(r => r.status, () => 0)
  assert.equal(alive, 200, 'the server is still there')
  // The stream comes back: the call that was on comes back on, and it still never hung up the server.
  await run('__streams[0].onopen()')
  let word
  for (let i = 0; i < 50 && word !== 'Listening'; i++) { await sleep(100); word = await run("document.getElementById('state').textContent") }
  assert.equal(word, 'Listening')
  assert.deepEqual(await run('window.sent.filter(u => u.includes("hangup"))'), [], 'still no /hangup')
  // A different server process answers on the same address: one quiet bubble says so; the same one again says nothing.
  const hello = boot => run(`__streams[0].onmessage({ data: JSON.stringify({ type: 'hello', project: '/x/app', voices: [], boot: '${boot}' }) })`)
  const bubbles = () => run("[...document.querySelectorAll('#talk .cv-bubble')].map(b => b.textContent + (b.classList.contains('cv-bubble--wrong') ? ' (red)' : ''))")
  await hello('a'); await hello('a')
  const before = (await bubbles()).length
  await hello('b'); await hello('b')
  const after = await bubbles()
  assert.equal(after.length, before + 1)
  assert.match(after.at(-1), /^The call restarted\./)
  assert.doesNotMatch(after.at(-1), /\(red\)/)
})

test('End pressed while the stream is down ends the call that comes back', { skip: !existsSync(CHROME) && 'Chrome is not installed' }, async t => {
  const { run } = await launcherPage(t)
  await run("window.sent = []; const f = fetch; fetch = (u, o) => (window.sent.push(String(u)), f(u, o)); __streams[0].dispatchEvent(new Event('error'))")
  await sleep(300)
  await run("document.getElementById('end').click()") // a person's press, after the call has ended on its own
  await sleep(300)
  assert.deepEqual(await run('window.sent.filter(u => u.includes("hangup"))'), [], 'nothing is sent while it is down')
  await run('__streams[0].onopen()') // it is back
  await sleep(500)
  assert.equal((await run('window.sent.filter(u => u.includes("hangup"))')).length, 1, 'the server that came back is told to end')
  assert.equal(await run("document.getElementById('idleH').textContent"), 'Call ended.')
})

test('a blocked microphone on a launcher page: the words for a window with no address bar, and what it tells the launcher', { skip: !existsSync(CHROME) && 'Chrome is not installed' }, async t => {
  const { run } = await launcherPage(t)
  const rec = '__recs.at(-1)'
  for (let i = 0; i < 50 && (await run('blockedBy')) !== ''; i++) await sleep(100) // the recogniser has heard the fake microphone once, so nothing is still on its way
  await run("window.mics = []; const f = fetch; fetch = (u, o) => (String(u) === '/mic' && mics.push(JSON.parse(o.body).blocked), f(u, o))")
  const mics = () => run('mics')
  const note = () => run("document.getElementById('note').textContent")
  const button = () => run("document.getElementById('callview').hidden ? 'Start call' : document.getElementById('mute').textContent === 'Allow' ? 'Allow' : 'End call'") // the call screen: Allow while the microphone is blocked

  // The first time it hears, it clears whatever an earlier page (a reload) told the launcher; then it says nothing more.
  assert.equal(await run('blockedBy'), '', 'the fake microphone was heard: an empty mic was already posted')
  await run(`blockedBy = null; ${rec}.onaudiostart(); ${rec}.onaudiostart()`) // as a fresh page
  assert.deepEqual(await mics(), [''])

  // No microphone to open (a Mac with none): not a permission, so the plain note and nothing for the launcher.
  await run(`${rec}.onerror({ error: 'audio-capture' })`)
  await sleep(200)
  assert.match(await note(), /Speech recognition stopped \(audio-capture\)/)
  assert.deepEqual(await mics(), [''])
  // Chrome's speech service refused: not the microphone either.
  await run(`${rec}.onerror({ error: 'service-not-allowed' })`)
  await sleep(200)
  assert.match(await note(), /Speech recognition stopped \(service-not-allowed\)/)
  assert.deepEqual(await mics(), [''])

  // Refused while the page's own permission is granted (as here): macOS keeps the microphone from Chrome.
  await run(`${rec}.onerror({ error: 'not-allowed' })`)
  await sleep(200)
  assert.match(await note(), /System Settings › Privacy & Security, then press Allow/)
  assert.deepEqual(await mics(), ['', 'mac'])
  await run(`${rec}.onaudiostart()`) // it hears again
  assert.deepEqual(await mics(), ['', 'mac', ''])

  // Chrome's permission for the page refused: no address bar to point at, so the panel's Open Settings.
  await run(`window.perm = { state: 'denied', onchange: null }; navigator.permissions.query = async () => perm; ${rec}.onerror({ error: 'not-allowed' })`)
  await sleep(200)
  assert.match(await note(), /Allow microphone in the Oh Kevin panel/)
  assert.doesNotMatch(await note(), /address bar/)
  assert.deepEqual(await mics(), ['', 'mac', '', 'chrome'])
  assert.equal(await button(), 'Allow')
  assert.equal(await run("document.getElementById('state').textContent"), 'Mic blocked')
  // The stream reconnecting tells the server again: it forgot when the stream dropped.
  await run('__streams[0].onopen()')
  assert.deepEqual(await mics(), ['', 'mac', '', 'chrome', 'chrome'])

  // Allowed in Chrome's settings: the call listens again by itself.
  await run("perm.state = 'granted'; perm.onchange()")
  let now
  for (let i = 0; i < 50 && now !== 'End call'; i++) { await sleep(100); now = await button() }
  assert.equal(now, 'End call')
})
