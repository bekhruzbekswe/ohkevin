// What a call has measured so far: pure helpers over a plain list of entries.
// Loaded by index.html (served at /stats.mjs) and tested by stats.test.mjs.

export const record = (list, entry) => list.push(entry)

export function summary(list) {
  const delays = list.filter(e => e.kind === 'reply').map(e => e.delay).sort((a, b) => a - b)
  const n = delays.length, mid = n >> 1
  const count = kind => list.filter(e => e.kind === kind).length
  return {
    turns: n,
    medianDelay: n ? (n % 2 ? delays[mid] : (delays[mid - 1] + delays[mid]) / 2) : null,
    slowest: n ? delays[n - 1] : 0,
    joined: count('joined'), waited: count('waited'), pausedForNothing: count('nothing'), cutOffs: count('cut'),
  }
}

export function line(s) {
  const med = s.medianDelay === null ? '-' : `${s.medianDelay.toFixed(1)} s`
  return `${s.turns} ${s.turns === 1 ? 'reply' : 'replies'}, median ${med}, slowest ${s.slowest.toFixed(1)} s, joined ${s.joined}, waited ${s.waited}, paused for nothing ${s.pausedForNothing}, cut off ${s.cutOffs}`
}
