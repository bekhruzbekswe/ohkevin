// Makes call/problem.mp3, the sound the call page plays when the call server reports a problem, from numbers alone:
// two notes, D3 then A3, each three sine partials (1, 2 and 4 times the note), a short attack, a hold, a fast decay into
// a quieter detuned tail that beats slowly, in a made-up room (seeded noise as its echo) a little different in each ear.
//   node call/tools/problem-sound.mjs /tmp/problem.wav && ffmpeg -y -i /tmp/problem.wav -b:a 128k call/problem.mp3
import { writeFileSync } from 'node:fs'

const SR = 44100
const P = {
  dur: 1.5, fade: 0.093, loudness: -15.7, // loudness: RMS in dB of full scale
  notes: [{ f: 146.83, at: 0.050, levels: [-22.0, -14.3, -7.6] }, { f: 220.0, at: 0.316, levels: [-16.2, -9.2, -8.3] }],
  attack: 0.0072, hold: 0.143, decay: 72.1, tail: -19.75, tailDecay: 18.05, cents: 10.6, width: 0.099, wet: -11.72, rt60: 1.855,
}
const db = d => 10 ** (d / 20), n = Math.round(P.dur * SR)

// two notes
const L = new Float64Array(n), R = new Float64Array(n)
for (const note of P.notes) {
  for (let i = Math.ceil(note.at * SR); i < n; i++) {
    const u = i / SR - note.at, att = Math.min(u / P.attack, 1), after = Math.max(u - P.attack - P.hold, 0)
    const body = att * Math.exp(-after * P.decay / 8.686), tail = att * db(P.tail) * Math.exp(-after * P.tailDecay / 8.686)
    ;[1, 2, 4].forEach((k, j) => {
      const a = db(note.levels[j]), f = note.f * k, d = f * (2 ** (P.cents / 1200) - 1)
      const main = a * body * Math.sin(2 * Math.PI * f * u)
      const lo = a * tail * Math.sin(2 * Math.PI * (f - d) * u), hi = a * tail * Math.sin(2 * Math.PI * (f + d) * u)
      L[i] += main + lo * (1 + P.width) + hi * (1 - P.width)
      R[i] += main + lo * (1 - P.width) + hi * (1 + P.width)
    })
  }
}

// the room: each ear convolved with its own decaying seeded noise
function fft(re, im, inverse) { // in place, length a power of two
  const N = re.length
  for (let i = 1, j = 0; i < N; i++) { let b = N >> 1; for (; j & b; b >>= 1) j ^= b; j ^= b; if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]] } }
  for (let len = 2; len <= N; len <<= 1) {
    const ang = (inverse ? 2 : -2) * Math.PI / len, wr = Math.cos(ang), wi = Math.sin(ang)
    for (let i = 0; i < N; i += len) {
      let cr = 1, ci = 0
      for (let k = 0; k < len / 2; k++) {
        const a = i + k, b = a + len / 2, tr = re[b] * cr - im[b] * ci, ti = re[b] * ci + im[b] * cr
        re[b] = re[a] - tr; im[b] = im[a] - ti; re[a] += tr; im[a] += ti
        ;[cr, ci] = [cr * wr - ci * wi, cr * wi + ci * wr]
      }
    }
  }
  if (inverse) for (let i = 0; i < N; i++) { re[i] /= N; im[i] /= N }
}
let seed = Number(process.env.SEED ?? 11) // the room that came closest of 40 tried
const noise = () => { // mulberry32, then Box-Muller: a fixed seed, so the file is the same every time
  const u = () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296 }
  return Math.sqrt(-2 * Math.log(u() || 1e-12)) * Math.cos(2 * Math.PI * u())
}
function room(x) {
  const m = Math.round(P.rt60 * SR); let N = 1; while (N < x.length + m) N <<= 1
  const a = new Float64Array(N), ai = new Float64Array(N), h = new Float64Array(N), hi = new Float64Array(N)
  a.set(x)
  for (let i = 0; i < m; i++) h[i] = noise() * Math.exp(-i / SR * 6.9 / P.rt60) / Math.sqrt(SR * P.rt60 / 13.8)
  fft(a, ai); fft(h, hi)
  for (let i = 0; i < N; i++) { const r = a[i] * h[i] - ai[i] * hi[i]; ai[i] = a[i] * hi[i] + ai[i] * h[i]; a[i] = r }
  fft(a, ai, true)
  return x.map((v, i) => v + db(P.wet) * a[i])
}
const l = room(L), r = room(R)

// fade, loudness, 16-bit stereo WAV
let sum = 0
for (let i = 0; i < n; i++) { const g = Math.min((P.dur - i / SR) / P.fade, 1) ** 2; l[i] *= g; r[i] *= g; sum += ((l[i] + r[i]) / 2) ** 2 }
const gain = db(P.loudness) / Math.sqrt(sum / n)
const out = Buffer.alloc(44 + n * 4)
out.write('RIFF', 0); out.writeUInt32LE(36 + n * 4, 4); out.write('WAVEfmt ', 8); out.writeUInt32LE(16, 16); out.writeUInt16LE(1, 20)
out.writeUInt16LE(2, 22); out.writeUInt32LE(SR, 24); out.writeUInt32LE(SR * 4, 28); out.writeUInt16LE(4, 32); out.writeUInt16LE(16, 34)
out.write('data', 36); out.writeUInt32LE(n * 4, 40)
const s16 = v => Math.max(-32768, Math.min(32767, Math.round(v * gain * 32767)))
for (let i = 0; i < n; i++) { out.writeInt16LE(s16(l[i]), 44 + i * 4); out.writeInt16LE(s16(r[i]), 46 + i * 4) }
writeFileSync(process.argv[2] ?? 'problem.wav', out)
