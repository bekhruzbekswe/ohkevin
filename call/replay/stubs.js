// Injected into the call page before its own script by voice.replay.test.mjs. It replaces everything the page reaches
// outside itself (clock, timers, the server, the recogniser, the microphone, the voice) with fakes that run on a handed
// clock, and logs what the page does with them. window.__replay(steps) then feeds a recorded call in and returns the log.
// The same inputs always give the same log, however busy the machine is: no real time is ever read.
(() => {
  const C = window.__case ?? {} // { takesTrack, endDelay, tts: [{ text, at, dur }], levels: [[t, db]], browserMs }
  localStorage.clear()
  const out = [], round = x => Math.round(x * 1000) / 1000
  let now = 0
  const log = o => out.push({ t: round(now), ...o })

  // ── the clock and timers ─────────────────────────────────────────────────────
  const timers = new Map()
  let seq = 0
  const add = (fn, ms, every) => { const id = ++seq; timers.set(id, { id, fn, due: now + Math.max(0, +ms || 0), every: every ? Math.max(1, +ms || 0) : 0 }); return id }
  window.setTimeout = (fn, ms, ...a) => add(() => fn(...a), ms, false)
  window.setInterval = (fn, ms, ...a) => add(() => fn(...a), ms, true)
  window.clearTimeout = window.clearInterval = id => { timers.delete(id) }
  window.requestAnimationFrame = () => 0 // the strip is drawing only
  performance.now = () => now
  const flush = () => new Promise(r => { const ch = new MessageChannel(); ch.port1.onmessage = () => r(); ch.port2.postMessage(0) }) // every promise settles first
  async function runTo(T) {
    for (;;) {
      let next = null
      for (const x of timers.values()) if (x.due <= T && (!next || x.due < next.due || (x.due === next.due && x.id < next.id))) next = x
      if (!next) { now = Math.max(now, T); return }
      now = Math.max(now, next.due)
      if (next.every) next.due += next.every; else timers.delete(next.id)
      try { next.fn() } catch (err) { log({ k: 'throw', text: String(err) }) }
      await flush()
    }
  }

  // ── the server: the event stream and every request ───────────────────────────
  window.EventSource = class { constructor(url) { window.__es = this; this.url = url } close() {} }
  const clips = new Map()
  for (const c of C.tts ?? []) (clips.get(c.text) ?? clips.set(c.text, []).get(c.text)).push(c)
  window.fetch = (input, init = {}) => {
    const url = new URL(String(input), location.href)
    if (init.method === 'POST') { log({ k: 'post', path: url.pathname, body: JSON.parse(init.body || '{}') }); return Promise.resolve({ ok: true, status: 204 }) }
    if (url.pathname === '/tts') {
      const text = url.searchParams.get('text'), c = clips.get(text)?.shift() ?? { dur: C.ttsDur ?? 2 }
      log({ k: 'tts', voice: url.searchParams.get('voice'), text })
      const res = { ok: true, arrayBuffer: () => Promise.resolve({ dur: c.dur, text }) }
      return new Promise(r => (c.at > now ? setTimeout(() => r(res), c.at - now) : r(res)))
    }
    log({ k: 'fetch', path: url.pathname })
    return Promise.reject(new Error('not in the replay'))
  }
  navigator.permissions.query = () => Promise.resolve({ state: C.permission ?? 'granted', onchange: null })

  // ── the microphone ───────────────────────────────────────────────────────────
  navigator.mediaDevices.getUserMedia = () => {
    log({ k: 'mic' })
    if (C.micError) return Promise.reject(Object.assign(new Error(C.micError.message), { name: C.micError.name }))
    const track = { kind: 'audio', readyState: 'live', getSettings: () => ({ echoCancellation: C.echo ?? true }), stop() { if (track.readyState === 'live') log({ k: 'mic-stop' }); track.readyState = 'ended' } }
    return Promise.resolve({ getAudioTracks: () => [track] })
  }
  const levelAt = () => { // the recorded level nearest before now, if it is recent; otherwise silence
    const L = C.levels ?? []
    let lo = 0, hi = L.length - 1, at = -1
    while (lo <= hi) { const m = (lo + hi) >> 1; if (L[m][0] <= now) { at = m; lo = m + 1 } else hi = m - 1 }
    return at >= 0 && now - L[at][0] < 40 ? L[at][1] : -100
  }

  // ── the voice: Web Audio and the browser's own speech ────────────────────────
  class Source {
    constructor(ctx) { this.ctx = ctx; this.buffer = null; this.onended = null; this.timer = 0; this.left = 0; this.from = 0; this.on = false }
    connect(x) { return x }
    start() { log({ k: 'play', text: this.buffer?.text, dur: this.buffer?.duration }); this.left = (this.buffer?.duration ?? 0) * 1000; this.on = true; this.ctx.srcs.add(this); if (this.ctx.state === 'running') this.go() }
    go() { this.from = now; this.timer = setTimeout(() => this.end('ended'), this.left) }
    pause() { clearTimeout(this.timer); this.left -= now - this.from }
    end(how) { if (!this.on) return; this.on = false; clearTimeout(this.timer); this.ctx.srcs.delete(this); log({ k: how }); if (how === 'ended') this.onended?.(); else setTimeout(() => this.onended?.()) }
    stop() { this.end('stop') }
  }
  const node = extra => ({ connect: x => x, disconnect() {}, ...extra })
  const param = () => ({ value: 0, setValueAtTime() {}, exponentialRampToValueAtTime() {} })
  window.AudioContext = class {
    constructor() { this.state = 'running'; this.acc = 0; this.since = now; this.srcs = new Set(); this.destination = {}; log({ k: 'audio' }) }
    get currentTime() { return (this.acc + (this.state === 'running' ? now - this.since : 0)) / 1000 }
    suspend() { if (this.state === 'running') { this.acc += now - this.since; this.state = 'suspended'; log({ k: 'suspend' }); for (const s of this.srcs) s.pause() } return Promise.resolve() }
    resume() { if (this.state === 'suspended') { this.since = now; this.state = 'running'; log({ k: 'resume' }); for (const s of this.srcs) s.go() } return Promise.resolve() }
    createBufferSource() { return new Source(this) }
    createOscillator() { const o = node({ frequency: param(), start() { log({ k: 'tone', f: o.frequency.value }) }, stop() {} }); return o }
    createGain() { return node({ gain: param() }) }
    createMediaStreamSource() { return node() }
    createAnalyser() { return node({ fftSize: 2048, getFloatTimeDomainData(a) { a.fill(10 ** (levelAt() / 20)) } }) }
    decodeAudioData(b) { return Promise.resolve({ duration: b.dur, text: b.text }) }
  }
  const synth = { speaking: false, pending: false, queue: [], current: null, timer: 0 }
  const next = () => {
    const u = synth.current = synth.queue.shift()
    synth.pending = synth.queue.length > 0; synth.speaking = !!u
    if (!u) return
    setTimeout(() => { log({ k: 'speak-start', text: u.text }); u.onstart?.() })
    synth.timer = setTimeout(() => { synth.current = null; log({ k: 'speak-end', text: u.text }); next(); u.onend?.() }, C.browserMs ?? 1500)
  }
  synth.speak = u => { log({ k: 'speak', text: u.text }); synth.queue.push(u); if (synth.current) synth.pending = true; else next() }
  synth.cancel = () => {
    const u = synth.current
    if (!u && !synth.queue.length) return
    log({ k: 'speak-cancel' }); clearTimeout(synth.timer); synth.queue = []; synth.current = null; synth.speaking = synth.pending = false
    if (u) setTimeout(() => u.onerror?.({ error: 'interrupted' }))
  }
  Object.defineProperty(window, 'speechSynthesis', { value: synth, configurable: true })
  window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text } }

  // ── the recogniser ───────────────────────────────────────────────────────────
  const recs = []
  class Recognition {
    constructor() { this.n = recs.push(this); this.started = false }
    start(track) {
      if (arguments.length && C.takesTrack !== false && track?.kind !== 'audio') throw new TypeError('not a MediaStreamTrack')
      if (this.started) { log({ k: 'sr-throw', n: this.n }); throw new DOMException('already started', 'InvalidStateError') }
      this.started = true; this.probe = arguments.length && track?.kind !== 'audio'
      if (!this.probe) { log({ k: 'sr-start', n: this.n, track: !!track }); setTimeout(() => this.started && this.onaudiostart?.()) }
    }
    finish(error) {
      if (!this.started) return
      this.started = false
      setTimeout(() => { if (error) this.onerror?.({ error }); this.onend?.() }, C.endDelay ?? 0)
    }
    abort() { if (!this.probe) log({ k: 'sr-abort', n: this.n }); this.finish('aborted') }
    stop() { log({ k: 'sr-stop', n: this.n }); this.finish('') }
  }
  window.SpeechRecognition = window.webkitSpeechRecognition = Recognition
  const live = () => recs.findLast(r => r.started && !r.probe)

  // ── what the page shows and says ─────────────────────────────────────────────
  const info = console.info
  console.info = (...a) => { log({ k: 'log', text: a.join(' ') }); info.apply(console, a) }
  let lastTalk = '', lastUi = ''
  const $ = id => document.getElementById(id)
  const look = () => {
    const talk = JSON.stringify([...$('talk').querySelectorAll('.cv-bubble')].map(b => [b.parentElement.classList.contains('cv-turn--you') ? (b.classList.contains('cv-bubble--live') ? 'ghost' : 'you') : 'voice', b.textContent]))
    if (talk !== lastTalk) { lastTalk = talk; log({ k: 'talk', msgs: JSON.parse(talk) }) }
    const ui = JSON.stringify({ state: $('idle').hidden ? $('state').textContent : $('idleH').textContent, note: $('note').textContent, mute: $('mute').textContent.trim() })
    if (ui !== lastUi) { lastUi = ui; log({ k: 'ui', ...JSON.parse(ui) }) }
  }
  addEventListener('DOMContentLoaded', () => { new MutationObserver(look).observe(document.body, { subtree: true, childList: true, characterData: true, attributes: true }) })

  // ── feeding a recorded call in ───────────────────────────────────────────────
  const results = r => r.map(([transcript, isFinal]) => ({ 0: { transcript }, length: 1, isFinal }))
  const act = s => {
    if (s.sse) return window.__es.onmessage({ data: JSON.stringify(s.sse) })
    if (s.result) { const r = live(); if (!r) return log({ k: 'no-recogniser' }); return r.onresult({ resultIndex: s.result.i, results: results(s.result.r) }) }
    if (s.end) { const r = live(); if (r) { r.started = false; r.onend?.() } return }
    if (s.error) { const r = live(); if (r) { r.started = false; r.onerror?.({ error: s.error }); r.onend?.() } return }
    if (s.click) return $(s.click).click()
    if ('phones' in s) { $('phones').checked = s.phones; return $('phones').dispatchEvent(new Event('change', { bubbles: true })) }
    if (s.type != null) { $('box').value = s.type; return $('typed').requestSubmit() }
    if (s.key) return document.body.dispatchEvent(new KeyboardEvent('keydown', { code: s.key, bubbles: true }))
    if (s.voice) return $('vo-' + s.voice).click()
  }
  window.__replay = async (steps, tail = 15000) => {
    look()
    for (const s of steps) { await runTo(s.t); try { act(s) } catch (err) { log({ k: 'throw', text: String(err) }) } await flush() }
    await runTo((steps.at(-1)?.t ?? 0) + tail)
    return out
  }
})()
