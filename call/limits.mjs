// Usage-limit warnings the voice says on its own: which rate_limit_event is worth a line, the line, and when it may be said.
// Pure: the server passes in the time and the call's state. Tested by limits.test.mjs.
import { TUNE } from './ears.mjs'

// A held line waits for a lull this long, so it never lands while the page may still join your words or wait for more (ears.mjs).
export const QUIET_MS = Math.max(TUNE.joinMs, 5000)
// One warning per limit window, at this share used. The CLI also warns earlier (a quarter of a week): not worth breaking into a call for.
const LEVELS = [0.75]
const HIT = 99 // the memory level of a limit already hit: nothing more is said for that window
const NAMES = { five_hour: 'five-hour limit', seven_day: 'weekly limit', seven_day_opus: 'weekly Opus limit', seven_day_sonnet: 'weekly Sonnet limit', seven_day_overage_included: 'weekly limit', overage: 'extra usage limit' }
const FIVE_HOURS = 5 * 3600

// When a limit resets, as said aloud: "at 3:40 PM" today, "tomorrow at 9 AM", otherwise "on Wednesday at 9 AM".
export function whenWords(resetsAt, now, timeZone) {
  const at = new Date(resetsAt * 1000)
  const day = d => d.toLocaleDateString('en-US', { timeZone })
  const time = at.toLocaleTimeString('en-US', { timeZone, hour: 'numeric', minute: '2-digit' }).replace(/\s+/g, ' ').replace(':00 ', ' ') // ICU puts a narrow space before PM
  if (day(at) === day(new Date(now))) return `at ${time}`
  if (day(at) === day(new Date(now + 86400000))) return `tomorrow at ${time}`
  return `on ${at.toLocaleDateString('en-US', { timeZone, weekday: 'long' })} at ${time}`
}

// What a rate_limit_event from either session means for the call: { type, line, until, hit } to say in the next lull, or null.
// said: Map limit type -> { level, until }, kept by the caller: a warning and a limit hit are each said once per window.
export function limitLine(info, said, now, timeZone) {
  const hit = info?.status === 'rejected'
  if (!hit && info?.status !== 'allowed_warning') return null // 'allowed' is routine
  const type = typeof info.rateLimitType === 'string' ? info.rateLimitType : ''
  const nowS = now / 1000
  const until = Number.isFinite(info.resetsAt) && info.resetsAt > nowS ? info.resetsAt : null
  const name = NAMES[type] ?? 'usage limit'
  if (hit) {
    const last = said.get(type)
    if (last && nowS < last.until && last.level === HIT) return null
    said.set(type, { level: HIT, until: until ?? nowS + FIVE_HOURS })
    return { type, until, hit, line: `You've hit your ${name}${until ? `; it resets ${whenWords(until, now, timeZone)}` : ''}.` }
  }
  const used = [info.utilization, info.surpassedThreshold].find(Number.isFinite) ?? null // a share, 0 to 1
  const level = used === null ? LEVELS.length : LEVELS.filter(l => used >= l).length // no number: said once, never raised
  const last = said.get(type)
  if (!level || (last && nowS < last.until && level <= last.level)) return null
  said.set(type, { level, until: until ?? nowS + FIVE_HOURS })
  const when = until ? `, and it resets ${whenWords(until, now, timeZone)}` : ''
  return { type, until, hit, line: used === null ? `You're close to your ${name}${when}.` : `You've used ${Math.floor(used * 100 + 1e-9)} percent of your ${name}${when}.` }
}

// May a held line be said now? Someone is listening, nobody talks, no reply is being written or played, no approval waits
// for an answer, and all of that has lasted QUIET_MS. s: { pages, you, voice, talking, asking, quietFrom }
// A limit hit does not wait for the talker: the talker shares the limit and may be the thing that failed.
export const mayAnnounce = (s, now, hit = false) => s.pages > 0 && !s.you && !s.voice && (hit || !s.talking) && !s.asking && now - s.quietFrom >= QUIET_MS

// The held lines to say now, in the order they came, taken out of held; [] while the call is not in a lull.
// A line whose limit has reset while it waited is dropped: it would no longer be true.
export function dueLines(held, s, now) {
  for (const [type, it] of held) if (it.until && it.until * 1000 <= now) held.delete(type)
  const due = [...held].filter(([, it]) => mayAnnounce(s, now, it.hit))
  for (const [type] of due) held.delete(type)
  return due.map(([, it]) => it.line)
}
