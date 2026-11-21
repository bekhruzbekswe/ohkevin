// voice.mjs runs without a browser: a host made of plain objects and a handed clock drives it (as the Swift app's
// differential check does). The full behaviour is pinned by voice.replay.test.mjs; this only shows the shape of a host.
import test from 'node:test'
import assert from 'node:assert/strict'
import * as ears from './ears.mjs'
import { createCall } from './voice.mjs'

function host() {
  let t = 0, n = 0
  const timers = new Map(), posts = [], recs = []
  const flush = () => new Promise(r => setImmediate(r))
  const h = {
    ears, lang: 'en-US', voice: 'af_heart', now: () => t,
    setTimeout: (f, ms) => (timers.set(++n, { f, at: t + ms }), n), clearTimeout: id => timers.delete(id),
    setInterval: () => 0, clearInterval: () => {},
    post: (path, body) => (posts.push([path, body]), Promise.resolve()),
    tts: () => Promise.resolve({ ok: true, arrayBuffer: () => Promise.resolve({}) }),
    audioContext: () => ({ resume() {}, currentTime: 0, decodeAudioData: () => Promise.resolve({ duration: 1 }) }),
    Recognition: class { constructor() { recs.push(this) } start(x) { if (x && x.kind !== 'audio') throw new TypeError() } abort() {} stop() {} },
    getUserMedia: () => Promise.reject(Object.assign(new Error('none'), { name: 'NotFoundError' })), // no echo-cancelled track: the plain path
    speech: { speaking: false, pending: false, speak() {}, cancel() {} }, Utterance: class {},
  }
  const run = async ms => { // the handed clock: every timer due by then, in order
    for (const end = t + ms; ;) {
      const [id, x] = [...timers].filter(([, x]) => x.at <= end).sort((a, b) => a[1].at - b[1].at)[0] ?? []
      if (!x) { t = end; return }
      t = x.at; timers.delete(id); x.f(); await flush()
    }
  }
  return { h, posts, recs, run, flush }
}

test('a host of plain objects: words heard become a turn, a pause to think joins the next words to it', async () => {
  const { h, posts, recs, run, flush } = host()
  const call = createCall(h), seen = []
  call.on('heard', e => seen.push(e)); call.on('problem', code => seen.push(code))
  call.server({ type: 'hello', voices: [] })
  await call.start(true)
  const rec = recs.at(-1), say = (i, text, isFinal) => rec.onresult({ resultIndex: i, results: [...Array(i).fill({ 0: { transcript: '' }, isFinal: true }), { 0: { transcript: text }, isFinal }] })
  assert.equal(call.state.live, true)
  say(0, 'tell me about', false)
  assert.equal(call.state.hearing, true)
  await run(500); say(0, 'tell me about', true); await flush()
  await run(1000); say(1, 'closures', false); await run(300); say(1, 'closures', true); await flush()
  assert.deepEqual(seen, ['no-talk-over', { text: 'tell me about', replaces: false }, { text: 'tell me about closures', replaces: true }])
  assert.deepEqual(posts.filter(([p]) => p === '/say').map(([, b]) => b.text), ['tell me about', 'tell me about closures'])
})
