// A live call's log (the app writes one only when started with --log <file>; live.mjs writes the Chrome side; one is kept,
// with made-up words, as recorded-call-<n>.jsonl), measured as the recorded lines are (any chrome-*.jsonl too: one schema),
// plus what only a room shows: the echo left in the microphone while the voice talks. The page logs its gate's level
// only while the voice talks, as does the app, so both give the echo the same way.
//   node Tests/measure/trial.mjs Tests/recordings/recorded-call-1.jsonl [...]                 → trials.json, beside the recordings
//   node Tests/measure/trial.mjs --compare <chrome.jsonl> <native.jsonl>           → the two side by side, and trials.json beside the recordings
import { readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { TUNE } from '../../../call/ears.mjs'
import { measure, r2 } from './measure.mjs'

const median = xs => { const v = xs.filter(x => x != null).sort((a, b) => a - b); return v.length ? r2(v[v.length >> 1]) : null }
const pct = (xs, p) => { const v = [...xs].sort((a, b) => a - b); return v.length ? r2(v[Math.min(v.length - 1, Math.floor(p * v.length))]) : null }

export function trial(file) {
  const L = readFileSync(file, 'utf8').trim().split('\n').map(l => JSON.parse(l))
  const m = measure(file, '')
  const t0 = L.find(e => e.k === 'mic').t, s = t => (t - t0) / 1000
  const results = L.filter(e => e.k === 'result')
  // every stretch of speech: when its first words showed, when its words turned final
  const utterances = m.speech.map(([on, off], k) => {
    const next = m.speech[k + 1]?.[0] ?? Infinity
    const first = results.find(e => s(e.t) >= on && s(e.t) < next)
    return { on, off, firstWord: first ? r2(s(first.t) - on) : null, finalAfter: m.parts[k]?.finalAfter ?? null }
  })
  // the echo: the gate's level while the voice played, away from anyone talking (1.5 s either side of speech)
  const talking = t => m.speech.some(([on, off]) => s(t) > on - 1.5 && s(t) < off + 1.5)
  const levels = L.filter(e => e.k === 'level'), echo = levels.filter(e => !talking(e.t)).map(e => e.db)
  // the longest run of 20 ms levels above the bar with no one talking: the gate fires at TUNE.riseMs
  let run = 0, longest = 0, prev = null
  for (const e of levels) {
    const up = e.db > TUNE.barDb && !talking(e.t) && prev != null && e.t - prev < 40
    run = up ? run + (e.t - prev) : 0; longest = Math.max(longest, run); prev = e.t
  }
  const voiceSec = r2(m.voice.reduce((a, [p, q]) => a + q - p, 0))
  return {
    file: path.basename(file), seconds: r2(s(L.at(-1).t)), talkSec: r2(m.speech.reduce((a, [on, off]) => a + off - on, 0)), recogniser: m.recogniser, turns: m.says.length,
    utterances, firstWord: median(utterances.map(u => u.firstWord)), finalAfter: median(utterances.map(u => u.finalAfter)),
    updateGap: median(m.gaps), decided: { words: m.decided.filter(d => d === 'words').length, quiet: m.decided.filter(d => d === 'quiet').length },
    finalize: L.filter(e => e.k === 'finalize').map(({ wordsMs, quietMs, bar }) => ({ wordsMs, quietMs, bar })),
    voiceSec, over: m.over, paused: m.paused, released: m.released, falsePauses: m.falsePauses, falseCuts: m.falseCuts,
    echo: { n: echo.length, median: pct(echo, 0.5), p99: pct(echo, 0.99), max: r2(Math.max(...echo)), longestAboveBarMs: Math.round(longest), bar: TUNE.barDb, riseMs: TUNE.riseMs },
    joined: m.joined, waited: m.waited, nudged: m.nudged,
  }
}

const ROWS = [ // label, what to show
  ['you talk (s)', t => t.talkSec], ['utterances', t => t.utterances.length], ['voice talks (s)', t => t.voiceSec],
  ['first words, median (s)', t => t.firstWord], ['words final after the last sound, median (s)', t => t.finalAfter],
  ['live words update every (ms, median)', t => t.updateGap],
  ['interruptions', t => t.over.length], ['voice paused after (s, median)', t => median(t.over.map(o => o.pausedAfter))],
  ['false pauses', t => t.falsePauses], ['false cut-offs', t => t.falseCuts],
  ['echo while the voice talks, median (dB)', t => t.echo.median], ['echo, 99th percentile (dB)', t => t.echo.p99],
  ['echo, longest run above the bar (ms)', t => t.echo.longestAboveBarMs], ['turns joined', t => t.joined], ['turns waited', t => t.waited],
]
if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2), compare = args[0] === '--compare', out = args.filter(a => a !== '--compare').map(trial)
  writeFileSync(path.join(path.dirname(process.argv[1]), '../recordings/trials.json'), JSON.stringify(out, null, 1) + '\n')
  if (compare) {
    const w = Math.max(...ROWS.map(([l]) => l.length)) + 2
    console.log(''.padEnd(w) + out.map(t => t.file.padEnd(26)).join('') + '\n' + ''.padEnd(w) + out.map(t => t.recogniser.slice(0, 24).padEnd(26)).join(''))
    for (const [label, f] of ROWS) console.log(label.padEnd(w) + out.map(t => String(f(t) ?? '-').padEnd(26)).join(''))
  } else for (const t of out) console.log(JSON.stringify({ ...t, utterances: undefined, finalize: undefined, over: t.over.map(o => o.pausedAfter) }))
}
