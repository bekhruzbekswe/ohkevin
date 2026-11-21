// The page's ears: small pure helpers for talking over the voice on laptop speakers.
// Loaded by index.html (served at /ears.mjs) and tested by ears.test.mjs.

// Tunables, in one place. Edit and reload the page. The server reads joinMs at startup, so restart it after changing that one.
export const TUNE = {
  barDb: -42,   // echo-cancelled mic level (dBFS) that counts as someone talking over the voice
  capDb: -30,   // false alarms raise the bar, never above this
  stepDb: 3,    // how much each false alarm raises the bar
  riseMs: 120,  // the level must stay above the bar this long
  guardMs: 300, // no pausing in the first moments of each spell of talking, while the echo canceller settles
  holdMs: 1200, // how long a pause waits for the recogniser to confirm real words
  restMs: 1500, // no new pause this soon after a false one
  joinMs: 8000, // a pause to think: words you add this soon are joined to your last ones (see stillOpen); 0 turns all of it off
  waitMs: 3000, // when the voice waits for the rest of your thought and you stay quiet this long, it answers what it has
}

const norm = w => w.toLowerCase().replace(/[^\p{L}\p{N}']/gu, '')
const hasRun = (words, run) => words.some((_, i) => run.every((w, j) => words[i + j] === w))

// What the developer said, minus leading words that are the voice's own echo; '' when it is all echo.
export function userPart(heard, aired) {
  const tokens = heard.trim().split(/\s+/).filter(t => norm(t))
  const h = tokens.map(norm), a = aired.split(/\s+/).map(norm).filter(Boolean)
  let k = h.length
  while (k > 0 && !hasRun(a, h.slice(0, k))) k--
  if (k === h.length) return ''
  return tokens.slice(k < 2 ? 0 : k).join(' ') // one shared word is chance; two or more in a row is echo
}

// The start of a sentence, in proportion to how much of its audio has played.
export function cutText(text, fraction) {
  const words = text.trim().split(/\s+/).filter(Boolean)
  return words.slice(0, Math.floor(words.length * Math.min(1, Math.max(0, fraction || 0)))).join(' ')
}

// A whole utterance that only asks the voice to stop: it cuts the voice off and is not sent as a turn.
const CALM = new Set(['stop', 'wait', 'hold', 'pause', 'quiet', 'enough'])
const FILL = new Set(['on', 'it', 'please', 'now', 'ok', 'okay', 'a', 'sec', 'second', 'moment'])
export function isStopOnly(text) {
  const w = text.split(/\s+/).map(norm).filter(Boolean)
  return w.some(x => CALM.has(x)) && w.every(x => CALM.has(x) || FILL.has(x))
}

// Loudness of a block of samples, in dBFS.
export function levelDb(samples) {
  let sum = 0
  for (const x of samples) sum += x * x
  return 10 * Math.log10(sum / samples.length + 1e-12)
}

// Says when the echo-cancelled microphone has stayed loud long enough to be someone talking over the voice.
export class Gate {
  bar = TUNE.barDb
  since = null // when the level went above the bar
  until = 0    // no firing before this time
  feed(db, t) {
    if (t < this.until || db <= this.bar) { this.since = null; return false }
    this.since ??= t
    return t - this.since >= TUNE.riseMs
  }
  quiet(t, ms) { this.until = Math.max(this.until, t + ms); this.since = null }
  miss() { this.bar = Math.min(this.bar + TUNE.stepDb, TUNE.capDb) } // that was not a person: ask for more next time
}

// A pause to think. After your words are sent, the turn stays open to more of them:
//   'sent'      its answer has not started playing: more words cancel that answer and are joined;
//   'waiting'   the voice judged the thought unfinished and is waiting for the rest;
//   'answering' its answer started ageMs ago: words that talk over it are joined too.
// ageMs counts from when the words were sent, the voice began waiting, or the answer started.
export function stillOpen(state, ageMs) {
  if (state === 'waiting') return true // the server only waits when it has the feature on, so honour it either way
  if (!(TUNE.joinMs > 0) || ageMs >= TUNE.joinMs) return false
  return state === 'sent' // once its answer is playing, what you say over it is a new turn, not more of the old one
}

// More words for an open turn: the whole thought, to send in place of the first part.
// '' means a new turn, as before: a bare "stop" is not more of the thought.
export const joinTurn = (before, more) => (isStopOnly(more) ? '' : `${before} ${more}`)

// Words that never end a finished sentence. The server tells the voice when a turn ends on one (a hint only).
const OPEN = new Set(['and', 'or', 'but', 'because', 'the', 'a', 'an', 'my', 'your', 'our', 'their', 'um', 'uh', 'er', 'erm'])
export const unfinished = text => OPEN.has(norm(text.trim().split(/\s+/).at(-1) ?? ''))
