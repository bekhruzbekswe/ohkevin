// Talks to a test call page without a microphone: Kokoro says the line, headless Chrome hears that WAV as its
// microphone (it loops, so the line comes again about 17 s later, over the reply), and the page's console is printed.
// Start a test server first (see tools/drive.mjs), then, from call/:  node tools/hear.mjs "What is a closure in JavaScript?" [seconds]
// A "|" in the line is a pause: PAUSE seconds of quiet (default 2), or "|6|" for 6 s. AEC=0 turns off Chrome-wide echo
// cancellation, which in headless Chrome swallows words said while the voice plays. The server's say, wait and task
// events are printed too. For example:
//   node tools/hear.mjs "Check | the files in this project." 18
//   AEC=0 node tools/hear.mjs "Tell me three facts about octopuses, one sentence each. |6| And | which one is the smartest of them?" 28
import { spawn } from 'node:child_process'
import { writeFileSync, mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { findBrowser } from '../platform.mjs'
import path from 'node:path'
const base = `http://127.0.0.1:${process.env.PORT ?? 4799}`, k = process.env.CALL_KEY ?? 'testkey'
const [line = 'What is a closure in JavaScript?', secs = '20'] = process.argv.slice(2)
const t0 = Date.now(), log = (...a) => console.log(((Date.now() - t0) / 1000).toFixed(2).padStart(7), ...a)

// The line as a mono 16-bit WAV, with 1 s of faint noise before and 14 s after (a real room is never digitally silent).
let rate = 24000
async function pcmOf(text) {
  const src = Buffer.from(await (await fetch(`${base}/tts?k=${k}&voice=am_michael&text=${encodeURIComponent(text)}`)).arrayBuffer())
  let p = 12, pcm
  while (p < src.length) { const id = src.toString('ascii', p, p + 4), n = src.readUInt32LE(p + 4); if (id === 'fmt ') rate = src.readUInt32LE(p + 12); if (id === 'data') pcm = src.subarray(p + 8, p + 8 + n); p += 8 + n }
  return pcm
}
const noise = s => { const n = Math.round(rate * s), b = Buffer.alloc(n * 2); for (let i = 0; i < n; i++) b.writeInt16LE(Math.round((Math.random() * 2 - 1) * 60), i * 2); return b }
const bits = line.split(/\|(?:([\d.]+)\|)?/) // words, pause, words, pause, ...
const parts = []
for (let i = 0; i < bits.length; i += 2) parts.push(await pcmOf(bits[i].trim()), bits[i + 1] ?? process.env.PAUSE ?? 2)
parts.pop() // no pause after the last words
const body = Buffer.concat([noise(1), ...parts.map(x => (Buffer.isBuffer(x) ? x : noise(Number(x)))), noise(14)]), head = Buffer.alloc(44)
head.write('RIFF', 0); head.writeUInt32LE(36 + body.length, 4); head.write('WAVEfmt ', 8); head.writeUInt32LE(16, 16); head.writeUInt16LE(1, 20); head.writeUInt16LE(1, 22)
head.writeUInt32LE(rate, 24); head.writeUInt32LE(rate * 2, 28); head.writeUInt16LE(2, 32); head.writeUInt16LE(16, 34); head.write('data', 36); head.writeUInt32LE(body.length, 40)
const dir = mkdtempSync(path.join(tmpdir(), 'hear-')), wav = path.join(dir, 'mic.wav') // shortcut: each run leaves this temp folder behind
writeFileSync(wav, Buffer.concat([head, body]))

// The audio service must run in-process and unsandboxed, or the fake microphone stays silent.
const chrome = spawn(findBrowser()?.file ?? 'chrome', ['--headless=new', '--remote-debugging-port=9335', `--user-data-dir=${dir}`, '--no-first-run',
  '--autoplay-policy=no-user-gesture-required', '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-audio-capture=${wav}`,
  `--disable-features=AudioServiceOutOfProcess,AudioServiceSandbox${process.env.AEC === '0' ? ',ChromeWideEchoCancellation' : ''}`, 'about:blank'], { stdio: 'ignore' })
process.on('exit', () => chrome.kill())
let pages
for (let i = 0; i < 50 && !pages; i++) { await new Promise(r => setTimeout(r, 200)); try { pages = await (await fetch('http://127.0.0.1:9335/json/list')).json() } catch {} }
const ws = new WebSocket(pages.find(t => t.type === 'page').webSocketDebuggerUrl)
await new Promise(r => (ws.onopen = r))
let id = 0; const waiting = new Map()
ws.onmessage = m => {
  const d = JSON.parse(m.data)
  if (d.method === 'Runtime.consoleAPICalled') log('console', d.params.args.map(a => a.value ?? a.description).join(' '))
  if (d.method === 'Runtime.exceptionThrown') log('ERROR  ', d.params.exceptionDetails.exception?.description ?? d.params.exceptionDetails.text)
  waiting.get(d.id)?.(d); waiting.delete(d.id)
}
const cdp = (method, params = {}) => new Promise(r => { const i = ++id; waiting.set(i, r); ws.send(JSON.stringify({ id: i, method, params })) })
const js = async e => (await cdp('Runtime.evaluate', { expression: e, returnByValue: true })).result?.result?.value
await cdp('Runtime.enable')
fetch(`${base}/events?k=${k}`).then(async res => { // the server's side: what is said, waits, and what the worker is given
  let buf = ''
  for await (const chunk of res.body) {
    buf += Buffer.from(chunk).toString()
    for (let i; (i = buf.indexOf('\n\n')) >= 0; buf = buf.slice(i + 2)) {
      const e = buf.startsWith('data: ') ? JSON.parse(buf.slice(6, i)) : {}
      if (e.type === 'say' || e.type === 'wait' || e.type === 'task' || e.type === 'ask' || e.type === 'asked' || e.ask) log('server ', e.type, e.text ?? e.said ?? e.detail ?? JSON.stringify(e))
    }
  }
})
await cdp('Page.navigate', { url: `${base}/?k=${k}` }); await new Promise(r => setTimeout(r, 2500))
await js(`document.getElementById('call').click()`); log('call started; the line plays 1 s in')
await new Promise(r => setTimeout(r, Number(secs) * 1000))
log('conversation:\n' + await js(`[...document.querySelectorAll('.bubble')].map(b => '  ' + b.closest('.msg').className.replace('msg ', '') + ': ' + b.textContent).join('\\n')`))
log('cards: ' + await js(`[...document.querySelectorAll('.askcard b')].map(b => b.textContent).join(' | ')`))
process.exit(0)
