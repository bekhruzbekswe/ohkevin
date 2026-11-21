// Turns a call log written by the measurement hook (one JSON line per thing the page saw or did) into a replay case:
// what came in (server events, recognition results and ends, the clips' lengths, the microphone level) at the time it
// came. What the page did in that log (its posts, plays, pauses) is left out: the replay makes the page do it again.
//   node replay/from-log.mjs <log.jsonl> <case.json>
import { readFileSync, writeFileSync } from 'node:fs'

export function fromLog(text, name) {
  const L = text.trim().split('\n').map(l => JSON.parse(l))
  const t0 = L[0].t, at = e => Math.round((e.t - t0) * 10) / 10
  const steps = [], tts = [], levels = []
  let live = false, muted = false
  for (const [j, e] of L.entries()) {
    if (e.k === 'sse') steps.push({ t: at(e), sse: e.e })
    else if (e.k === 'mic' && !live) { live = true; steps.push({ t: at(e), click: 'call' }) } // the call was started
    else if (e.k === 'mic' && muted) { muted = false; steps.push({ t: at(e), click: 'mute' }) } // unmuted
    else if (e.k === 'error' && e.error === 'aborted') { muted = true; steps.push({ t: at(e), click: 'mute' }) } // only muting aborts the recogniser
    else if (e.k === 'error') steps.push({ t: at(e), error: e.error })
    else if (e.k === 'end' && L[j - 1]?.k !== 'error') steps.push({ t: at(e), end: true })
    else if (e.k === 'result') steps.push({ t: at(e), result: { i: e.i, r: e.r } })
    else if (e.k === 'tts') tts.push({ text: e.text, at: at(e), dur: e.dur })
    else if (e.k === 'level') levels.push([at(e), Math.round(e.db * 10) / 10])
  }
  return { name, opts: { tts, levels }, steps }
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const [src, dst] = process.argv.slice(2)
  writeFileSync(dst, JSON.stringify(fromLog(readFileSync(src, 'utf8'), dst.split('/').pop().replace(/\.json$/, ''))) + '\n')
}
