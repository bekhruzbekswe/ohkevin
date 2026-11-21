// The differential check: the same events go to call/voice.mjs (in Node, on the fake host below) and to its Swift port
// (AppChecks --replay -, which is Replay and Turns), on one handed clock, and everything both produce must be the same:
// every /say, /hush and /live post with its body and time, every clip played, stopped, paused and resumed, every log line.
// Inputs: every log in Tests/recordings/, the hand-written cases in call/replay/cases, and SEEDS generated calls.
//   node Tests/measure/differ.mjs [seeds]        (after ./build.sh; check.mjs runs it; exits 1 on any difference)
//
// What is not compared, each for its reason (the one list):
// 1. Ears without echo cancellation (rec.onresult's speakers and headphones branch, F1 included) and the browser voice
//    (speechSynthesis) are not ported. So voice.mjs runs with an echo-cancelled track and a local voice, and its browser
//    voice is silent: where it would fall back to it (a clip that failed), Swift says nothing too. Swift's own "[mouth]"
//    log lines, which say so, are dropped.
// 2. The recogniser's life (start, abort, errors, a stale recogniser's late end: F2) is the page's and the app's own, not
//    the shared rules: here an 'end' event always ends the current recogniser, and hand-written cases with errors are skipped.
// 3. Display: the rows, the faint unsaid words, the limit line, the ghost text, tone(), and voice.mjs's 'heard', 'spoken',
//    'interim', 'state' and 'tally' events. Only posts, the voice's audio and log lines are compared.
// 4. The level: voice.mjs reads an analyser every 20 ms; both sides get the logged dB readings, one call per reading.
// 5. /live is posted by the page's mark() from voice.mjs's 'floor' events: that one line is mirrored here.
// 6. Keyboard shortcuts are the page's and the window's: in hand-written cases M is the mute click, Space is dropped.
import { readFileSync, readdirSync } from 'node:fs'
import { built } from './app.mjs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import * as ears from '../../../call/ears.mjs'
import { createCall } from '../../../call/voice.mjs'
import { events, swift } from './measure.mjs'

const HERE = path.dirname(fileURLToPath(import.meta.url)), ROOT = path.join(HERE, '../..'), CALL = path.join(ROOT, '../call')

// voice.mjs on one call, on a host that keeps time and plays clips exactly as Replay.swift does.
export async function js(list) {
  let clock = 0, seq = 0, level = -100, timers = []
  const out = { posts: [], logs: [], media: [] }, note = (k, x = {}) => out.media.push({ t: clock, k, ...x })
  const at = (t, fn) => { const x = { t, n: ++seq, fn }; timers.push(x); return x } // after every event of the same time, as in Replay
  const cancel = x => { if (x) x.fn = null }
  const flush = () => new Promise(r => setImmediate(r))
  // The voice, as Replay plays it: a clip ends after its duration, not counting time paused.
  let src = null, before = 0, startedAt = 0, paused = false, end = null
  const played = () => (src ? before + (paused ? 0 : (clock - startedAt) / 1000) : before)
  const schedule = () => { end = at(clock + (src.buffer.duration - before) * 1000, () => { const s = src; src = null; s.onended() }) }
  const audio = {
    destination: {},
    get currentTime() { return played() }, // the clip's own played time: voice.mjs reads it from 0 at began(), so it cuts the same word
    resume() { if (paused) { paused = false; note('resume'); if (src) { startedAt = clock; schedule() } } },
    suspend() { if (!paused) { if (src) { before = played(); cancel(end) } paused = true; note('suspend') } },
    decodeAudioData: b => Promise.resolve(b),
    createBufferSource() {
      before = 0
      const s = { connect() {}, start() { note('play', { text: s.buffer.text, dur: s.buffer.duration }); src = s; startedAt = clock; if (!paused) schedule() },
        stop() { if (src !== s) return; note('stop'); before = played(); cancel(end); src = null; at(clock, () => s.onended()) } }
      return s
    },
    createMediaStreamSource: () => ({ connect() {}, disconnect() {} }),
    createAnalyser: () => ({ connect() {}, getFloatTimeDomainData() {} }),
  }
  const clips = list.filter(e => e.k === 'tts').map(e => ({ ...e }))
  const recs = [], intervals = new Map(), track = { kind: 'audio', readyState: 'live', getSettings: () => ({ echoCancellation: true }), stop() {} }
  class Recognition { constructor() { recs.push(this) } start(x) { if (x?.kind !== 'audio') throw new TypeError(); this.on = true } abort() { this.on = false } stop() { this.on = false } }
  const host = {
    ears: { ...ears, levelDb: () => level }, lang: 'en-US', voice: 'af_heart', headphones: false, now: () => clock,
    setTimeout: (fn, ms) => at(clock + Math.max(0, +ms || 0), fn), clearTimeout: cancel,
    setInterval: fn => { const id = ++seq; intervals.set(id, fn); return id }, clearInterval: id => intervals.delete(id),
    post: (p, body) => { if (p !== '/live') out.posts.push({ t: clock, path: p, body }); return Promise.resolve() },
    tts: (voice, text) => new Promise(done => { // the first clip of the call for these words, once it came; none: it failed
      const c = clips.find(c => !c.used && c.text === text)
      if (c) c.used = true
      at(c ? Math.max(clock, c.t) : clock, () => done({ ok: c?.dur != null, arrayBuffer: () => Promise.resolve({ text, duration: c?.dur }) }))
    }),
    audioContext: () => audio, Recognition, getUserMedia: () => Promise.resolve({ getAudioTracks: () => [track] }),
    speech: { speaking: false, pending: false, speak() {}, cancel() {} }, Utterance: class {},
  }
  const call = createCall(host), told = { you: false, voice: false }
  call.on('floor', (lane, on) => { if (told[lane] !== on) { told[lane] = on; out.posts.push({ t: clock, path: '/live', body: { [lane]: on } }) } }) // index.html mark()
  const rec = () => recs.findLast(r => r.on)
  const act = {
    mic: () => call.start(true),
    result: e => rec()?.onresult({ resultIndex: e.i, results: e.r.map(([transcript, isFinal]) => ({ 0: { transcript }, isFinal })) }),
    end: () => { const r = rec(); if (r) { r.on = false; r.onend() } },
    hangup: () => call.state.live && call.start(false),
    mute: e => call.state.live && e.on !== call.state.muted && call.mute(e.on),
    voice: e => call.set({ voice: e.name ?? call.state.voice }),
    type: e => call.typed(e.text.trim()),
    sse: e => call.server(e.e),
    level: e => { level = e.db; [...intervals.values()].at(-1)?.() },
  }
  const info = console.info
  console.info = (...a) => out.logs.push({ t: clock, text: a.join(' ') })
  try {
    const stop = Math.max(...list.map(e => e.t).filter(t => t != null))
    const evs = list.filter(e => act[e.k]).map((e, i) => ({ e, i })).sort((a, b) => a.e.t - b.e.t || a.i - b.i)
    for (let p = 0; ;) { // the next event, or the next timer if it is due first (an event of the same time goes first, as in Replay)
      timers = timers.filter(x => x.fn)
      const x = timers.reduce((m, x) => (!m || x.t < m.t || (x.t === m.t && x.n < m.n) ? x : m), null)
      const ev = evs[p], next = ev && (!x || ev.e.t <= x.t) ? ev.e.t : x?.t
      if (next == null || next > stop) break
      clock = Math.max(clock, next)
      try { if (ev && ev.e.t === next) { p++; act[ev.e.k](ev.e) } else { timers.splice(timers.indexOf(x), 1); x.fn() } }
      catch (err) { out.logs.push({ t: clock, text: `throw ${err}` }) }
      await flush()
    }
  } finally { console.info = info }
  return out
}

// What both sides produce, in a form to compare: times to the microsecond, body keys in order, Swift's own log lines out.
const shape = o => ({
  posts: o.posts.filter(p => p.path !== '/live').map(p => [+p.t.toFixed(3), p.path, JSON.stringify(p.body, Object.keys(p.body).sort())]),
  live: o.posts.filter(p => p.path === '/live').map(p => [+p.t.toFixed(3), JSON.stringify(p.body)]),
  media: o.media.map(m => [+m.t.toFixed(3), m.k, m.text, m.dur].filter(x => x !== undefined)),
  logs: o.logs.filter(l => !l.text.startsWith('[mouth]')).map(l => [+l.t.toFixed(3), l.text]),
})
// Real differences found and left as they are (neither side is changed to match). Each has its smallest case in
// diff-cases/, which must still differ (else it is fixed: take it off this list); elsewhere only what it explains is let by.
const KNOWN = [{
  file: 'held-quarter.jsonl', // an answer held exactly 0.25 s (1.25 s, ...): voice.mjs toFixed(1) rounds the tie up, Swift's "%.1f" to even
  alike: (k, a, b) => k === 'logs' && a?.[0] === b?.[0] && [a, b].every(x => /^\[turn\] answer held \d+\.\d s /.test(x[1])) && a[1].replace(/\d+\.\d/, '') === b[1].replace(/\d+\.\d/, ''),
}]
function first(a, b, known = KNOWN) { // the first difference between two shapes that no known one explains, or null
  for (const k of Object.keys(a)) {
    const n = Math.max(a[k].length, b[k].length)
    for (let i = 0; i < n; i++) {
      if (JSON.stringify(a[k][i]) === JSON.stringify(b[k][i]) || known.some(x => x.alike(k, a[k][i], b[k][i]))) continue
      return `${k}[${i}]: voice.mjs ${JSON.stringify(a[k][i])}, Swift ${JSON.stringify(b[k][i])}`
    }
  }
  return null
}

// A hand-written replay case (call/replay/cases) as events, when it stays on the shared path (exclusions 1, 2 and 6).
function fromCase(c) {
  const o = c.opts ?? {}
  if (o.takesTrack === false || o.echo === false || o.micError || o.browserMs || c.steps.some(s => s.error || 'phones' in s)) return null
  let live = false, muted = false
  const L = [], tts = (o.tts ?? []).map(x => ({ t: x.at ?? 0, k: 'tts', text: x.text, dur: x.dur }))
  const clip = text => { if (tts.filter(x => x.text === text).length <= L.filter(e => (e.k === 'sse' && e.e.type === 'say' ? e.e.text : e.k === 'voice' ? 'This is how I sound now.' : null) === text).length) tts.push({ t: 0, k: 'tts', text, dur: o.ttsDur ?? 2 }) } // stubs.js: any other sentence gets a clip at once
  for (const s of c.steps) {
    const t = s.t
    if (s.sse) { if (s.sse.type === 'say') clip(s.sse.text); L.push({ t, k: 'sse', e: s.sse }) }
    else if (s.result) L.push({ t, k: 'result', i: s.result.i, r: s.result.r })
    else if (s.end) L.push({ t, k: 'end' })
    else if (s.click === 'call') { L.push({ t, k: live ? 'hangup' : 'mic' }); live = !live; muted = false }
    else if ((s.click === 'mute' || s.key === 'KeyM') && live) L.push({ t, k: 'mute', on: (muted = !muted) })
    else if (s.type != null) L.push({ t, k: 'type', text: s.type })
    else if (s.voice) { clip('This is how I sound now.'); L.push({ t, k: 'voice', name: s.voice }) }
  }
  return [...tts, ...L, { t: (c.steps.at(-1)?.t ?? 0) + (c.tail ?? 15000), k: 'tail' }]
}

// A generated call: plausible, not real. Seeded, so the same seed is always the same call.
export function generate(seed) {
  let a = seed >>> 0
  const rnd = () => { a = (a + 0x6d2b79f5) >>> 0; let x = Math.imul(a ^ (a >>> 15), a | 1); x ^= x + Math.imul(x ^ (x >>> 7), x | 61); return ((x ^ (x >>> 14)) >>> 0) / 4294967296 }
  const int = (lo, hi) => lo + Math.floor(rnd() * (hi - lo + 1)), pick = xs => xs[int(0, xs.length - 1)], maybe = p => rnd() < p
  const SAY = ['Sure.', 'Let me look at the tests first.', 'The build failed on the parser.', 'I changed two files.', 'It wants to run git push. Should it go ahead?',
    'Closures capture the variables around them.', 'Done.', 'That is the last step.', "You've used 90 percent of your session limit."]
  const YOU = ['tell me about', 'run the tests', 'and also the parser', 'what about the build', 'I want to', 'refactor the', 'yes', 'no thanks',
    'stop', 'wait', 'hold on', 'enough', 'stop please', 'so', 'um', 'okay', 'the build failed on', 'let me look at']
  const L = [{ t: 0, k: 'sse', e: { type: 'hello', voices: ['af_heart', 'am_adam'] } }, { t: 100, k: 'mic' }]
  let t = 100, i = 0, live = true, muted = false, ask = 0
  const answer = at => { // the voice answers: one to three sentences, each with its clip (sometimes late, sometimes failed)
    const n = int(1, 3)
    for (let k = 0; k < n; k++) {
      const text = pick(SAY), s = at + k * int(0, 300)
      L.push({ t: s, k: 'sse', e: { type: 'say', text } }, { t: s + int(-200, 1500), k: 'tts', text, ...(maybe(0.95) && { dur: int(3, 40) / 10 }) })
      at = s
    }
    const id = maybe(0.25) ? `a${++ask}` : null
    L.push({ t: at + int(20, 400), k: 'sse', e: { type: 'turn_end', ...(id && { ask: id }) } })
    if (id && maybe(0.5)) L.push({ t: at + int(500, 8000), k: 'sse', e: { type: 'asked', id } })
  }
  for (let beat = int(4, 12); beat > 0; beat--) {
    t += int(100, 5000)
    if (maybe(0.08)) { L.push({ t, k: 'end' }); i = 0; t += int(10, 300) } // the recogniser restarts
    if (live && maybe(0.08)) { L.push({ t, k: 'mute', on: (muted = !muted) }); t += int(50, 2000) }
    if (live && muted && maybe(0.6)) { L.push({ t, k: 'mute', on: (muted = false) }); t += int(50, 500) }
    if (maybe(0.06)) { L.push({ t, k: 'type', text: pick(YOU) }); answer(t + int(200, 3000)); continue }
    if (maybe(0.04)) { L.push({ t, k: 'voice', name: pick(['af_heart', 'am_adam']) }, { t: t + int(0, 500), k: 'tts', text: 'This is how I sound now.', dur: 1.5 }); continue }
    if (maybe(0.05)) { L.push({ t, k: 'hangup' }); live = muted = false; t += int(500, 3000); L.push({ t, k: 'mic' }); live = true; i = 0; continue }
    // you talk: the words grow, then turn final (or the recogniser ends first); the microphone is loud while you do
    const words = (maybe(0.15) ? pick(SAY).toLowerCase().replace(/[.?,]/g, '') : pick(YOU)).split(' ')
    const parts = int(1, Math.min(4, words.length)), done = maybe(0.92), prev = Array(i).fill(['', true]), from = t
    for (let k = 1; k <= parts; k++) {
      const final = k === parts && done
      L.push({ t, k: 'result', i, r: [...prev, [words.slice(0, Math.ceil((k / parts) * words.length)).join(' '), final]] })
      if (!final) t += int(100, 600)
    }
    if (maybe(0.85)) for (let u = from; u <= t; u += 20) L.push({ t: u, k: 'level', db: int(-48, -25) })
    if (maybe(0.15)) for (let u = t + int(0, 3000), e = u + int(20, 400); u < e; u += 20) L.push({ t: u, k: 'level', db: int(-45, -30) }) // a noise
    if (done) i++; else { t += int(50, 500); L.push({ t, k: 'end' }); i = 0 }
    if (done && maybe(0.25)) L.push({ t: t + int(100, 1500), k: 'sse', e: { type: 'wait' } })
    if (done && maybe(0.8)) answer(t + int(200, 5000))
  }
  if (live && maybe(0.3)) L.push({ t: t + int(500, 5000), k: 'hangup' })
  L.push({ t: Math.max(...L.map(e => e.t)) + 15000, k: 'tail' })
  return L.sort((x, y) => x.t - y.t)
}

// Every input through both sides. Returns the counts and every difference ({ name, at }), a known case that stopped differing included.
export async function differ(app, seeds = 300) {
  const results = path.join(ROOT, 'Tests/recordings'), dir = path.join(CALL, 'replay/cases'), lines = f => readFileSync(f, 'utf8').trim().split('\n').map(l => JSON.parse(l))
  const named = [
    ...readdirSync(results).filter(f => /^(chrome|native|recorded-call)-.*\.jsonl$/.test(f) && !f.includes('.silent.')).sort().map(f => [f, events(path.join(results, f))]),
    ...readdirSync(dir).filter(f => f.startsWith('hand-')).sort().map(f => [f, fromCase(JSON.parse(readFileSync(path.join(dir, f), 'utf8')))]).filter(([, L]) => L),
    ...Array.from({ length: seeds }, (_, s) => [`seed ${s}`, generate(s)]),
    ...KNOWN.map(x => [x.file, lines(path.join(HERE, 'diff-cases', x.file))]),
  ]
  const theirs = swift(app, named.map(([, L]) => L)), diffs = []
  for (const [k, [name, L]] of named.entries()) {
    const ours = shape(await js(L)), at = first(ours, shape(theirs[k]))
    if (at) diffs.push({ name, at })
    else if (KNOWN.some(x => x.file === name) && !first(ours, shape(theirs[k]), [])) diffs.push({ name, at: 'no longer differs: take it off KNOWN' })
  }
  const n = re => named.filter(([x]) => re.test(x)).length
  return { counts: { logs: n(/^(chrome|native|owner)/), hand: n(/^hand-/), seeds, known: KNOWN.length }, diffs }
}

// Prints every difference and one line for all; true when nothing differs.
export function report({ counts: c, diffs }) {
  for (const d of diffs) console.log(`DIFFERENT  ${d.name}  ${d.at}`)
  console.log(`differential, voice.mjs against Swift: ${c.logs} logs, ${c.hand} hand-written, ${c.seeds} generated: ${diffs.length ? `${diffs.length} different` : `all the same, but for ${c.known} known difference${c.known === 1 ? '' : 's'} (diff-cases/)`}`)
  return !diffs.length
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(report(await differ(built(), +(process.argv[2] ?? 300))) ? 0 : 1)
