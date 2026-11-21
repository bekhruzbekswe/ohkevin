// Plays the same test utterances to today's call (the Chrome page, headless, the WAV as its microphone) and to the
// native prototype (the WAV fed in real time in place of its microphone), against a fresh call server each time, and
// keeps every raw log in app/results. Nothing is played aloud: Chrome runs with --mute-audio, the app with its
// output muted. Cost: the talker (Haiku) answers each utterance; the worker (Haiku) sits in an empty folder.
//   node measure/run.mjs [name ...] [--side chrome|native|native-own|native-speech]     (build the app first: ./build.sh)
// Each pass also records how busy the Mac was (results/load-<time>.txt): Apple's recogniser shares this machine, Google's does not.
import { spawn, execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { base, KEY, openCall, sleep, startServer } from './rig.mjs'
import { built } from './app.mjs'

const HERE = path.dirname(fileURLToPath(import.meta.url)), ROOT = path.join(HERE, '..')
const RESULTS = path.join(ROOT, 'results'), WAVS = path.join(ROOT, 'build/wavs'), APP = built()
const SCRATCH = process.env.SCRATCH ?? mkdtempSync(path.join(tmpdir(), 'm2-'))

// The test utterances. "|n|" is n seconds of quiet. Each file: 1 s of faint noise, the words, 12 s of faint noise.
export const SCRIPTS = [
  { name: 'short', line: 'Tell me a joke.', what: 'a short command' },
  { name: 'long', line: 'Explain the difference between a process and a thread, and tell me when a web server should use one or the other.', what: 'a long sentence' },
  { name: 'pause', line: 'Tell me about closures and |2.5| how they use memory.', what: 'a pause mid-thought' },
  { name: 'fragment', line: 'So the', what: 'a lone fragment' },
  { name: 'names', line: 'What does useEffect do in React, and is SQLite enough for a small Node.js app?', what: 'names and code words' },
  { name: 'stop', line: 'Tell me three facts about octopuses. |5.5| Stop.', what: 'a stop word over the voice' },
  { name: 'over', line: 'Tell me a joke about programmers. |5| Actually, tell me about octopuses instead.', what: 'talking over the voice' },
]
const VOICE = 'am_michael', LEAD = 1, TAIL = 12

const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a)

// ── the call server, fresh for every run: the talker starts each utterance with no history ──
const server = async tag => { const srv = await startServer(SCRATCH, { SPEAK_FIRST: '0' }); return { stop: () => srv.stop(path.join(RESULTS, 'server', `${tag}.log`)) } }

// ── the WAVs: Kokoro says each part (the server's /tts, nothing played), with seeded faint noise between ──
let seed = 1
const noise = (rate, s) => { const n = Math.round(rate * s), b = Buffer.alloc(n * 2)
  for (let i = 0; i < n; i++) { seed = (seed * 1103515245 + 12345) % 2147483648; b.writeInt16LE(Math.round((seed / 1073741824 - 1) * 60), i * 2) } return b }
async function makeWavs() {
  mkdirSync(WAVS, { recursive: true })
  const manifest = []
  for (const s of SCRIPTS) {
    seed = 1; let rate = 24000
    const bits = s.line.split(/\|(?:([\d.]+)\|)?/), parts = []
    for (let i = 0; i < bits.length; i += 2) {
      const src = Buffer.from(await (await fetch(`${base}/tts?k=${KEY}&voice=${VOICE}&text=${encodeURIComponent(bits[i].trim())}`)).arrayBuffer())
      let p = 12, pcm
      while (p < src.length) { const id = src.toString('ascii', p, p + 4), n = src.readUInt32LE(p + 4); if (id === 'fmt ') rate = src.readUInt32LE(p + 12); if (id === 'data') pcm = src.subarray(p + 8, p + 8 + n); p += 8 + n }
      parts.push({ words: bits[i].trim(), pcm }, Number(bits[i + 1] ?? 0))
    }
    parts.pop()
    const body = Buffer.concat([noise(rate, LEAD), ...parts.map(x => (typeof x === 'number' ? noise(rate, x) : x.pcm)), noise(rate, TAIL)]), head = Buffer.alloc(44)
    head.write('RIFF', 0); head.writeUInt32LE(36 + body.length, 4); head.write('WAVEfmt ', 8); head.writeUInt32LE(16, 16); head.writeUInt16LE(1, 20); head.writeUInt16LE(1, 22)
    head.writeUInt32LE(rate, 24); head.writeUInt32LE(rate * 2, 28); head.writeUInt16LE(2, 32); head.writeUInt16LE(16, 34); head.write('data', 36); head.writeUInt32LE(body.length, 40)
    const wav = Buffer.concat([head, body])
    writeFileSync(path.join(WAVS, `${s.name}.wav`), wav)
    manifest.push({ ...s, script: s.line.replace(/\|(?:[\d.]+\|)?/g, ' ').replace(/\s+/g, ' ').trim(), voice: VOICE,
      parts: parts.filter(x => typeof x !== 'number').map(x => x.words), seconds: body.length / 2 / rate, sha256: createHash('sha256').update(wav).digest('hex') })
  }
  writeFileSync(path.join(RESULTS, 'wavs.json'), JSON.stringify(manifest, null, 1) + '\n')
  return manifest
}

// ── today's call: headless Chrome, the WAV as its microphone (once, no loop), the page watched by hook.js ──
async function chrome(s, secs) {
  const profile = mkdtempSync(path.join(SCRATCH, 'chrome-')), lines = []
  let micAt = 0
  const wav = path.join(WAVS, `${s.name}.wav`)
  try {
    const page = await openCall(profile, ['--headless=new', '--mute-audio', '--autoplay-policy=no-user-gesture-required', '--use-fake-ui-for-media-stream',
      '--use-fake-device-for-media-stream', `--use-file-for-fake-audio-capture=${wav}%noloop`,
      // As hear.mjs AEC=0: headless Chrome's process-wide canceller swallows words said while the voice plays. The native
      // side gets the file without its canceller either, so both recognisers hear the identical audio.
      '--disable-features=AudioServiceOutOfProcess,AudioServiceSandbox,ChromeWideEchoCancellation'], o => { lines.push(o); if (o.k === 'mic') micAt = Date.now() })
    try {
      await sleep(2500)
      await page.send('Runtime.evaluate', { expression: `document.getElementById('call').click()` })
      for (let i = 0; i < 100 && !micAt; i++) await sleep(100)
      if (!micAt) throw new Error('the page never opened its microphone')
      await sleep(secs * 1000 - 300) // the file plays once from the moment the microphone opens
      await page.send('Browser.close').catch(() => {})
    } finally { await page.kill() }
  } finally { rmSync(profile, { recursive: true, force: true }) }
  return lines
}

// ── the native prototype: the app's own binary, the WAV in place of its microphone, its output muted ──
// side 'native': as the owner gets it, the app ends an utterance after 700 ms with no new words (Recognizer.swift);
// side 'native-own': ENDPOINT_MS=0, Apple's recogniser decides alone when an utterance is final.
// side 'native-speech': EARS=speech, Apple's newer SpeechTranscriber model; skipped (returns false) while that model is not installed.
async function native(s, secs, side) {
  const out = path.join(RESULTS, `${side}-${s.name}.jsonl`)
  const p = spawn(APP, ['--file', path.join(WAVS, `${s.name}.wav`), '--call', `${base}/?k=${KEY}`, '--log', out],
    { stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, ...(side === 'native-own' && { ENDPOINT_MS: '0' }), ...(side === 'native-speech' && { EARS: 'speech' }) } })
  const said = []; p.stdout.on('data', d => said.push(String(d))); p.stderr.on('data', d => said.push(String(d)))
  const timer = setTimeout(() => p.kill('SIGKILL'), (secs + 180) * 1000) // it waits for the voice before it listens
  const code = await new Promise(r => p.on('exit', r)); clearTimeout(timer)
  if (code !== 0 && side === 'native-speech' && /No English speech model/.test(said.join(''))) { rmSync(out, { force: true }); return false }
  if (code !== 0) throw new Error(`the app exited with ${code}:\n${said.join('')}`)
  writeFileSync(out, readFileSync(out, 'utf8').replaceAll(SCRATCH, '<scratch>'))
  return true
}

// ── main ──
mkdirSync(RESULTS, { recursive: true })
const argv = process.argv.slice(2), sideAt = argv.indexOf('--side'), only = sideAt >= 0 ? argv[sideAt + 1] : null
const names = argv.filter((a, i) => !a.startsWith('--') && (sideAt < 0 || i !== sideAt + 1))
if (!existsSync(APP) && only !== 'chrome') throw new Error('Build the app first: ./build.sh')
// How busy the Mac is: the prototype's recogniser competes for it, Chrome's runs on Google's machines.
function load(tag) {
  const run = (cmd, a) => { try { return execFileSync(cmd, a, { encoding: 'utf8', maxBuffer: 1 << 24 }) } catch (e) { return String(e) } }
  const top = run('top', ['-l', '2', '-s', '3', '-o', 'cpu', '-n', '10', '-stats', 'pid,command,cpu,mem']).split(/^(?=Processes:)/m).at(-1)
  const busy = run('ps', ['-Ao', 'pid,lstart,pcpu,rss,command']).split('\n').filter(l => /train|mlx|llama|torch|finetun|lora|ollama/i.test(l) && !/\bps\b/.test(l))
  const text = `${tag} ${new Date().toISOString()}\n${run('uptime', [])}\n${top}\ntraining or model processes:\n${busy.join('\n') || '(none seen)'}\n`
  writeFileSync(path.join(RESULTS, `load-${new Date().toISOString().slice(0, 19).replace(/:/g, '')}-${tag}.txt`), text.replaceAll(process.env.HOME, '~'))
}
let manifest
const skipped = new Set()
load('before')
{ const srv = await server('wavs'); try { manifest = await makeWavs() } finally { await srv.stop() } }
for (const s of manifest.filter(x => !names.length || names.includes(x.name))) {
  for (const side of ['chrome', 'native', 'native-own', 'native-speech'].filter(x => (!only || x === only) && !skipped.has(x))) {
    log(side, s.name, `${s.seconds.toFixed(1)} s`)
    let srv = await server(`${side}-${s.name}`)
    try {
      if (side === 'chrome') {
        const save = (lines, file) => writeFileSync(path.join(RESULTS, file), lines.map(o => JSON.stringify(o)).join('\n').replaceAll(SCRATCH, '<scratch>') + '\n')
        let lines = await chrome(s, s.seconds)
        if (!lines.some(o => o.k === 'result')) { // heard the speech, said nothing, no error: kept as evidence, tried once more
          save(lines, `chrome-${s.name}.silent.jsonl`); log('chrome heard nothing; once more')
          await srv.stop(); srv = await server(`${side}-${s.name}-again`); lines = await chrome(s, s.seconds)
        }
        save(lines, `chrome-${s.name}.jsonl`)
      }
      else if (!await native(s, s.seconds, side)) { skipped.add(side); log(`${side} skipped: Apple's SpeechTranscriber English model is not installed (VoiceApp --install-model downloads it)`) }
    } finally { await srv.stop() }
    await sleep(1000)
  }
}
load('after')
if (!process.env.SCRATCH) rmSync(SCRATCH, { recursive: true, force: true })
log('done')
