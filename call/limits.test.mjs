import { test } from 'node:test'
import assert from 'node:assert/strict'
import { TUNE } from './ears.mjs'
import { limitLine, whenWords, mayAnnounce, dueLines, QUIET_MS } from './limits.mjs'

const NOW = Date.UTC(2026, 10, 16, 12, 0) // Monday 16 November 2026, 12:00 UTC
const S = NOW / 1000
const WEEK_END = 1794974400 // Wednesday 18 November 2026, 04:00 UTC
// Recorded from a real worker run (SDK 0.3.325, haiku, a subscription login): the routine event, status allowed.
const REAL = { status: 'allowed', resetsAt: WEEK_END, rateLimitType: 'seven_day', overageStatus: 'rejected', overageDisabledReason: 'org_level_disabled', isUsingOverage: false, unifiedWindows: { seven_day: { utilization: 0.62, resetsAt: WEEK_END, status: 'allowed' } } }
// A warning shaped as the CLI builds it from its own pace check or from the server's surpassed-threshold header.
const warn = (rateLimitType, utilization, resetsAt, more = {}) =>
  ({ status: 'allowed_warning', resetsAt, rateLimitType, utilization, unifiedRateLimitFallbackAvailable: false, isUsingOverage: false, overageStatus: 'rejected', ...more })
const line = (info, said = new Map(), now = NOW) => limitLine(info, said, now, 'UTC')?.line ?? null
const LULL = { pages: 1, you: false, voice: false, talking: false, asking: false, quietFrom: NOW - QUIET_MS }

test('routine and malformed events say nothing', () => {
  assert.equal(line(REAL), null)
  for (const x of [undefined, null, {}, 'allowed_warning', { status: 'allowed' }, 42]) assert.equal(line(x), null)
})

test('a warning is one plain sentence: the share used, the limit, and when it resets', () => {
  assert.equal(line(warn('five_hour', 0.91, S + 9600)), "You've used 91 percent of your five-hour limit, and it resets at 2:40 PM.")
  assert.equal(line(warn('seven_day', 0.75, WEEK_END)), "You've used 75 percent of your weekly limit, and it resets on Wednesday at 4 AM.")
  assert.equal(line(warn('seven_day_opus', 0.8, S + 21 * 3600)), "You've used 80 percent of your weekly Opus limit, and it resets tomorrow at 9 AM.")
  assert.equal(line(warn('overage', 0.9, S + 3600)), "You've used 90 percent of your extra usage limit, and it resets at 1 PM.")
  assert.equal(line(warn('something_new', 0.9, S + 3600)), "You've used 90 percent of your usage limit, and it resets at 1 PM.")
  assert.equal(line(warn(undefined, 0.9, S + 3600)), "You've used 90 percent of your usage limit, and it resets at 1 PM.")
})

test('it says only what the event holds', () => {
  assert.equal(line(warn('seven_day', undefined, WEEK_END, { surpassedThreshold: 0.75 })), "You've used 75 percent of your weekly limit, and it resets on Wednesday at 4 AM.")
  assert.equal(line(warn('seven_day', undefined, WEEK_END)), "You're close to your weekly limit, and it resets on Wednesday at 4 AM.")
  assert.equal(line(warn('five_hour', 0.9, undefined)), "You've used 90 percent of your five-hour limit.")
  assert.equal(line(warn('five_hour', 0.9, S - 60)), "You've used 90 percent of your five-hour limit.") // a reset time already past is not said
})

test('below three quarters of a limit is not worth a line', () => {
  for (const u of [0, 0.25, 0.5, 0.74]) assert.equal(line(warn('seven_day', u, WEEK_END)), null, String(u))
})

test('a warning is said once per window, at 75 percent', () => {
  const said = new Map()
  assert.equal(line(warn('seven_day', 0.5, WEEK_END), said), null)
  assert.ok(line(warn('seven_day', 0.75, WEEK_END), said))
  for (const u of [0.76, 0.9, 0.99]) assert.equal(line(warn('seven_day', u, WEEK_END), said), null) // the CLI sends one event per percent
  assert.ok(line(warn('five_hour', 0.9, S + 3600), said)) // each limit has its own memory
  assert.equal(line(warn('five_hour', 0.95, S + 3600), said), null)
  assert.ok(line(warn('five_hour', 0.9, S + 3600 + 18000), said, NOW + 3601000)) // the next window warns again
})

test('a limit hit is said once per window, in its own words', () => {
  const said = new Map(), hit = (type, at, now = NOW) => line({ status: 'rejected', rateLimitType: type, resetsAt: at }, said, now)
  assert.equal(hit('seven_day', WEEK_END), "You've hit your weekly limit; it resets on Wednesday at 4 AM.")
  assert.equal(hit('seven_day', WEEK_END), null)
  assert.equal(line(warn('seven_day', 0.9, WEEK_END), said), null) // no warning after the hit
  assert.equal(hit('five_hour', S + 9600), "You've hit your five-hour limit; it resets at 2:40 PM.")
  assert.equal(hit('five_hour', undefined, NOW + 3600e3), null)
  assert.equal(hit(undefined, undefined, NOW), "You've hit your usage limit.")
  assert.ok(hit('five_hour', S + 9600 + 18000, NOW + 9601000)) // the next window
  const after = new Map([['seven_day', { level: 1, until: WEEK_END }]]) // a hit after a warning is still said
  assert.equal(line({ status: 'rejected', rateLimitType: 'seven_day', resetsAt: WEEK_END }, after, NOW), "You've hit your weekly limit; it resets on Wednesday at 4 AM.")
})

test('a warning with no number is said once for its window', () => {
  const said = new Map()
  assert.ok(line(warn('seven_day', undefined, WEEK_END), said))
  assert.equal(line(warn('seven_day', 0.9, WEEK_END), said), null)
})

test('without a reset time a limit stays quiet for five hours', () => {
  const said = new Map()
  assert.ok(line(warn('five_hour', 0.9, undefined), said))
  assert.equal(line(warn('five_hour', 0.9, undefined), said, NOW + 4 * 3600e3), null)
  assert.ok(line(warn('five_hour', 0.9, undefined), said, NOW + 5 * 3600e3 + 1000))
})

test('whenWords', () => {
  assert.equal(whenWords(S + 9600, NOW, 'UTC'), 'at 2:40 PM')
  assert.equal(whenWords(S + 12 * 3600 - 60, NOW, 'UTC'), 'at 11:59 PM')
  assert.equal(whenWords(S + 12 * 3600, NOW, 'UTC'), 'tomorrow at 12 AM')
  assert.equal(whenWords(WEEK_END, NOW, 'UTC'), 'on Wednesday at 4 AM')
  assert.equal(whenWords(WEEK_END, NOW, 'Asia/Tashkent'), 'on Wednesday at 9 AM')
  assert.ok(!/[^\x20-\x7e]/.test(whenWords(S + 9600, NOW, 'UTC'))) // plain spaces only
})

test('a line waits for a lull', () => {
  assert.ok(QUIET_MS >= TUNE.joinMs && QUIET_MS >= 5000)
  assert.ok(mayAnnounce(LULL, NOW))
  for (const busy of [{ pages: 0 }, { you: true }, { voice: true }, { talking: true }, { asking: true }, { quietFrom: NOW - QUIET_MS + 1 }])
    assert.ok(!mayAnnounce({ ...LULL, ...busy }, NOW), JSON.stringify(busy))
  assert.ok(mayAnnounce({ ...LULL, talking: true }, NOW, true)) // a limit hit does not wait for the talker
  for (const busy of [{ pages: 0 }, { you: true }, { voice: true }, { asking: true }, { quietFrom: NOW - QUIET_MS + 1 }])
    assert.ok(!mayAnnounce({ ...LULL, ...busy }, NOW, true), JSON.stringify(busy))
})

test('dueLines: in a lull it gives what is held, newest per limit, and drops what is no longer true', () => {
  const said = new Map(), held = new Map()
  const hold = info => { const it = limitLine(info, said, NOW, 'UTC'); if (it) held.set(it.type, it) } // as the server does
  hold(warn('seven_day', 0.76, WEEK_END)); hold(warn('five_hour', 0.9, S + 3600)); hold({ status: 'rejected', rateLimitType: 'seven_day', resetsAt: WEEK_END })
  assert.deepEqual(dueLines(held, { ...LULL, you: true }, NOW), [])
  assert.equal(held.size, 2) // kept for the next lull
  assert.deepEqual(dueLines(held, { ...LULL, talking: true }, NOW), ["You've hit your weekly limit; it resets on Wednesday at 4 AM."]) // only the hit ignores a busy talker
  assert.equal(held.size, 1)
  assert.deepEqual(dueLines(held, LULL, NOW), ["You've used 90 percent of your five-hour limit, and it resets at 1 PM."])
  assert.equal(held.size, 0)
  assert.deepEqual(dueLines(held, LULL, NOW), [])
  const late = new Map([['five_hour', { type: 'five_hour', until: S + 60, line: 'x' }]])
  assert.deepEqual(dueLines(late, LULL, NOW + 61000), []) // its limit reset while it waited
  assert.equal(late.size, 0)
})
