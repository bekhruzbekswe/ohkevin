// Injected into the call page before its own script (measure/run.mjs). It only watches: every hook calls the original
// and logs what passed through, as console.debug('[m2] {json}'), with t in epoch milliseconds. Nothing on the page changes.
(() => {
  const log = o => console.debug('[m2] ' + JSON.stringify({ t: performance.timeOrigin + performance.now(), ...o }))
  const SR = window.webkitSpeechRecognition
  if (SR) {
    class Spy extends SR { // the recogniser's events, before the page's own handlers see them
      constructor() {
        super()
        this.addEventListener('result', e => log({ k: 'result', i: e.resultIndex, r: Array.from(e.results, r => [r[0].transcript, r.isFinal]) }))
        this.addEventListener('end', () => log({ k: 'end' }))
        this.addEventListener('error', e => log({ k: 'error', error: e.error }))
        for (const k of ['start', 'audiostart', 'speechstart', 'nomatch']) this.addEventListener(k, () => log({ k: 'sr-' + k }))
      }
    }
    window.webkitSpeechRecognition = window.SpeechRecognition = Spy
  }
  const ES = window.EventSource // the server's events, as the page receives them
  window.EventSource = class extends ES { constructor(...a) { super(...a); this.addEventListener('message', m => log({ k: 'sse', e: JSON.parse(m.data) })) } }
  const F = window.fetch // what the page posts, and when each sentence of the voice arrived and how long it is
  const wavDur = b => { const v = new DataView(b); if (b.byteLength < 44 || v.getUint32(0) !== 0x52494646) return null
    let p = 12, rate = 0; while (p + 8 <= b.byteLength) { const id = v.getUint32(p), n = v.getUint32(p + 4, true); if (id === 0x666d7420) rate = v.getUint32(p + 12, true); if (id === 0x64617461) return n / 2 / rate; p += 8 + n } return null }
  window.fetch = function (input, init) {
    const url = new URL(String(input), location.href), p = F.apply(this, arguments)
    if (init?.method === 'POST') log({ k: 'post', path: url.pathname, body: JSON.parse(init.body || '{}') })
    if (url.pathname === '/tts') { const text = url.searchParams.get('text'); p.then(r => r.clone().arrayBuffer()).then(b => log({ k: 'tts', text, dur: wavDur(b) }), () => log({ k: 'tts', text, dur: null })) }
    return p
  }
  const AS = AudioBufferSourceNode.prototype, start = AS.start, stop = AS.stop // the voice playing, stopped
  AS.start = function () { log({ k: 'play', dur: this.buffer?.duration }); this.addEventListener('ended', () => log({ k: 'ended' })); return start.apply(this, arguments) }
  AS.stop = function () { log({ k: 'stop' }); return stop.apply(this, arguments) }
  const AC = AudioContext.prototype, sus = AC.suspend, res = AC.resume // the voice frozen mid-word, and carrying on
  AC.suspend = function () { log({ k: 'suspend' }); return sus.apply(this, arguments) }
  AC.resume = function () { if (this.state === 'suspended') log({ k: 'resume' }); return res.apply(this, arguments) }
  const AN = AnalyserNode.prototype, read = AN.getFloatTimeDomainData // the level the page's gate reads (only while the voice talks)
  AN.getFloatTimeDomainData = function (a) { read.call(this, a); let s = 0; for (const x of a) s += x * x; log({ k: 'level', db: 10 * Math.log10(s / a.length + 1e-12) }) }
  const SI = Storage.prototype.setItem // the voice menu: the page stores the pick, then hushes and says "This is how I sound now."
  Storage.prototype.setItem = function (k, v) { if (k === 'voice') log({ k: 'voice', name: v }); return SI.apply(this, arguments) }
  const md = navigator.mediaDevices, gum = md.getUserMedia.bind(md)
  md.getUserMedia = async c => { // the ears open; and our own meter on a copy of the track: when speech starts and stops in what is heard
    const s = await gum(c)
    log({ k: 'mic', recogniser: 'Chrome (webkitSpeechRecognition)' })
    const ctx = new AudioContext(), an = ctx.createAnalyser(), buf = new Float32Array(1024)
    an.fftSize = 1024; ctx.createMediaStreamSource(new MediaStream([s.getAudioTracks()[0].clone()])).connect(an)
    let loud = false
    setInterval(() => { read.call(an, buf); let q = 0; for (const x of buf) q += x * x; const on = 10 * Math.log10(q / 1024 + 1e-12) > -45; if (on !== loud) { loud = on; log({ k: 'vad', on }) } }, 10)
    return s
  }
})()
