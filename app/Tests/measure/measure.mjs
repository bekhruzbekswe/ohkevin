// What one call log says, measured the same way for every listener: the recorded lines and live trials (trial.mjs).
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const HANG = 700, LOUD_MIN = 60 // speech: level above -45 dBFS; gaps shorter than HANG ms are inside one stretch of speech

const norm = w => w.toLowerCase().replace(/[^\p{L}\p{N}']/gu, '') // ears.mjs's norm
export const words = s => s.split(/\s+/).map(norm).filter(Boolean)
function edits(a, b) { // word-level Levenshtein distance
  let prev = Array.from({ length: b.length + 1 }, (_, j) => j)
  for (let i = 1; i <= a.length; i++) {
    const cur = [i]
    for (let j = 1; j <= b.length; j++) cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1))
    prev = cur
  }
  return prev[b.length]
}
export const r2 = x => (x == null ? null : Math.round(x * 100) / 100)

export function measure(file, script) {
  const L = readFileSync(file, 'utf8').trim().split('\n').map(l => JSON.parse(l))
  const mic = L.find(e => e.k === 'mic'), t0 = mic.t, s = e => (e.t - t0) / 1000
  // stretches of speech in what the recogniser heard
  const segs = []
  for (const e of L.filter(e => e.k === 'vad')) {
    if (e.on) { const last = segs.at(-1); if (last && e.t - last.off < HANG) last.off = null; else segs.push({ on: e.t, off: null }) }
    else if (segs.at(-1) && segs.at(-1).off == null) segs.at(-1).off = e.t
  }
  const speech = segs.filter(x => x.off && x.off - x.on > LOUD_MIN)
  // results: what was on screen after each event, and each result that turned final
  const results = L.filter(e => e.k === 'result'), finals = []
  for (const e of results) e.r.forEach(([text, fin], j) => { if (fin && j >= e.i && text.trim()) finals.push({ t: e.t, text: text.trim() }) })
  const firstWord = results.find(e => e.t >= speech[0]?.on && e.r.some(([x]) => x.trim()))
  const parts = speech.map((x, k) => {
    const f = finals.find(f => f.t > x.off)
    const next = speech[k + 1]?.on ?? Infinity
    return { on: r2(s({ t: x.on })), off: r2(s({ t: x.off })), finalAfter: f && f.t < next ? r2((f.t - x.off) / 1000) : null }
  })
  const text = finals.map(f => f.text).join(' ')
  const wrong = edits(words(script), words(text))
  const posts = L.filter(e => e.k === 'post')
  const says = posts.filter(e => e.path === '/say').map(e => ({ t: r2(s(e)), text: e.body.text, ...(e.body.done && { done: true }) }))
  const hushes = posts.filter(e => e.path === '/hush').map(e => ({ t: r2(s(e)), ...(e.body.heard != null && { heard: e.body.heard }) }))
  const logs = L.filter(e => e.k === 'log').map(e => e.text)
  const count = re => logs.filter(x => re.test(x)).length
  const plays = L.filter(e => e.k === 'play')
  // reply delay: from the end of the speech before the first turn to the first sentence of the voice after it
  const say1 = posts.find(e => e.path === '/say'), play1 = say1 && plays.find(e => e.t > say1.t)
  const before = say1 && speech.filter(x => x.off <= say1.t).at(-1)
  // talking over the voice: speech that started while the voice was playing, and what the call did about it
  const playing = t => L.some(e => e.k === 'play' && e.t <= t && (L.find(x => (x.k === 'ended' || x.k === 'stop') && x.t > e.t)?.t ?? Infinity) > t)
  // talking over the voice counts only when it brought words (an echo blip is a level edge, not a person); the pause and
  // the cut belong to it only if they came within REACT_MS of its start
  const REACT_MS = 3000, worded = x => results.some(e => e.t >= x.on && e.t <= x.off + 1500 && e.r.slice(e.i).some(([t]) => t.trim()))
  const over = speech.filter(x => playing(x.on) && worded(x)).map(x => {
    const soon = e => e.t >= x.on && e.t - x.on <= REACT_MS
    const pause = L.find(e => e.k === 'suspend' && soon(e)), hush = L.find(e => e.k === 'post' && e.path === '/hush' && soon(e))
    // how much of the sentence playing at the cut had really played, by the wall clock, not counting the pause
    const clip = hush && plays.filter(p => p.t <= hush.t).at(-1)
    const frozen = clip && pause && pause.t >= clip.t && pause.t <= hush.t ? hush.t - pause.t : 0
    const sentence = clip && L.filter(e => e.k === 'tts' && e.dur === clip.dur).at(-1)?.text
    return { on: r2(s({ t: x.on })), pausedAfter: pause ? r2((pause.t - x.on) / 1000) : null, cutAfter: hush ? r2((hush.t - x.on) / 1000) : null,
      heard: hush?.body.heard ?? null, sentence: sentence ?? null, played: clip ? r2((hush.t - clip.t - frozen) / 1000) : null, of: clip ? r2(clip.dur) : null }
  })
  // a pause, or the ears cutting the voice off, with no speech in the 1.5 s before it is a false one (a join's hush is not a cut)
  const near = t => speech.some(x => x.on <= t && t - x.off < 1500)
  const falsePauses = L.filter(e => e.k === 'suspend' && !near(e.t)).length
  const falseCuts = L.filter(e => e.k === 'log' && /^\[ears\] cut off/.test(e.text) && !near(e.t)).length
  // how often the words on screen change while someone talks: gaps between updates inside speech
  const inSpeech = t => speech.some(x => t >= x.on && t <= x.off + 300)
  const gaps = results.slice(1).map((e, i) => (inSpeech(e.t) && inSpeech(results[i].t) ? e.t - results[i].t : null)).filter(x => x != null)
  // the app's endpoint rule: which half became true last, the words (700 ms unchanged) or the quiet (700 ms below the bar)
  const decided = L.filter(e => e.k === 'finalize').map(f => {
    const changed = results.filter(e => e.t < f.t).at(-1)?.t, quiet = L.filter(e => e.k === 'vad' && e.t < f.t).at(-1)
    const wordsMs = f.wordsMs ?? (changed ? f.t - changed : 0), quietMs = f.quietMs ?? (quiet && !quiet.on ? f.t - quiet.t : 0)
    return wordsMs <= quietMs ? 'words' : 'quiet'
  })
  return {
    recogniser: mic.recogniser, partials: results.length, at: [L[0].t, L.at(-1).t],
    firstWord: firstWord ? r2((firstWord.t - speech[0].on) / 1000) : null,
    parts, text, accuracy: r2(1 - wrong / words(script).length), wrong,
    says, hushes, joined: count(/^\[turn\] joined/), waited: count(/^\[turn\] held/), nudged: count(/nothing more came/),
    paused: count(/^\[ears\] paused/), released: count(/no words, carrying on/), cuts: count(/^\[ears\] cut off/),
    reply: play1 && before ? { total: r2((play1.t - before.off) / 1000), words: r2((say1.t - before.off) / 1000), voice: r2((play1.t - say1.t) / 1000) } : null,
    over, falsePauses, falseCuts, gaps, decided,
    finals: finals.map(f => [r2(s(f)), f.text]),
    timeline: results.map(e => [r2(s(e)), e.r.map(([x]) => x.trim()).filter(Boolean).join(' ')]),
    speech: speech.map(x => [r2(s({ t: x.on })), r2(s({ t: x.off }))]),
    voice: plays.map(p => [r2(s(p)), r2(s(L.find(x => (x.k === 'ended' || x.k === 'stop') && x.t > p.t) ?? { t: p.t + p.dur * 1000 }))]),
  }
}

// A recorded call as the replay reads it. Logs from before the voice menu was recorded have no 'voice' events, yet the menu's
// pick hushes and says "This is how I sound now." (an empty /hush, then that sentence fetched). Only for such logs, read that
// pair as the pick, so the replay can make the same hush. Logs with 'voice' events are used as they are.
export function events(file) {
  const L = readFileSync(file, 'utf8').trim().split('\n').map(l => JSON.parse(l))
  if (L.some(e => e.k === 'voice')) return L
  const at = (e, i) => e.k === 'post' && e.path === '/hush' && !Object.keys(e.body).length &&
    L.slice(i + 1).some(x => x.k === 'tts' && x.t - e.t < 5000 && x.text === 'This is how I sound now.')
  const pick = L.map((e, i) => (at(e, i) ? { t: e.t, k: 'voice' } : null)).filter(Boolean)
  return pick.length ? [...L, ...pick].sort((a, b) => a.t - b.t) : L
}
// The Swift rules on calls (each a list of events): what each posted, logged and played. One run of the app for them all.
export const swift = (app, calls) => execFileSync(app, ['--replay', '-'], { input: calls.map(c => JSON.stringify(c)).join('\n'), encoding: 'utf8', maxBuffer: 1 << 28 })
  .trim().split('\n').map(l => JSON.parse(l))

// The Swift rules, run on the recorded stream: do they send what the call sent?
export function replay(file, app) {
  const L = events(file), [got] = swift(app, [L])
  const key = p => `${p.path} ${JSON.stringify(p.body, Object.keys(p.body).sort())}` // key order is not meaning
  // End call is the person's act, not the rules': compare up to it. The app records it as 'hangup'; the owner's first
  // trial predates that, and its End call shows only as the empty /hush that closes the file.
  const last = L.findLast(e => e.k === 'post' && (e.path === '/say' || e.path === '/hush')), endAt = L.find(e => e.k === 'hangup')?.t ?? (last.k === 'post' && last.path === '/hush' && !Object.keys(last.body).length ? last.t : Infinity)
  const want = L.filter(e => e.k === 'post' && (e.path === '/say' || e.path === '/hush') && e.t < endAt)
  const mine = got.posts.filter(p => (p.path === '/say' || p.path === '/hush') && p.t < endAt)
  // A cut-off /hush {heard} is the sentences played whole plus the played share of the one playing. That share is the player's
  // clock, which the replay cannot match to the word: a gate decision within a millisecond of its 120 ms rule (the recorded
  // stamps are not that exact) pauses the voice there or one level reading later, and a pause is over a second. So two heard
  // texts agree when one is the other plus more words of the same sentence (no sentence end in between). Everything else is exact.
  const sameCut = (a, b) => {
    if (a.path !== '/hush' || b.path !== '/hush' || typeof a.body.heard !== 'string' || typeof b.body.heard !== 'string') return false
    const [x, y] = [a.body.heard.split(/\s+/), b.body.heard.split(/\s+/)].sort((p, q) => p.length - q.length)
    return x.every((w, i) => w === y[i]) && !y.slice(x.length - 1, -1).some(w => /[.?!]$/.test(w))
  }
  const same = want.length === mine.length && want.every((w, i) => key(w) === key(mine[i]) || sameCut(w, mine[i]))
  const drift = same ? Math.max(0, ...want.map((w, i) => Math.abs(w.t - mine[i].t))) : null
  return { same, posts: want.length, drift: r2(drift), want: want.map(key), got: mine.map(key) }
}
