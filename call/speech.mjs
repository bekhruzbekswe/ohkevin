// Turns the talker's streamed text into things to say aloud and control lines to act on.
// A control line looks like  ">>> do"  or  ">>> model: opus". It should stand on its own line,
// but the model sometimes puts it straight after a sentence, so both forms are accepted.
const CONTROL = /^>>>\s*(do|stop|model|topic|wait|open)\b:?\s*(.*)$/i
const INLINE = /\s>>>\s*(?:do|stop|model|topic|wait|open)\b/i
const SENTENCE_END = /[.!?…]["')\]]?(?=\s)/
const clean = s => s.replace(/[*_`#]/g, '').replace(/\s+/g, ' ').trim()

export class Splitter {
  buf = ''

  feed(delta) { this.buf += delta; return this.#drain(false) }
  flush() { return this.#drain(true) }

  #drain(end) {
    const out = []
    const say = text => { const t = clean(text); if (t) out.push({ say: t }) }
    for (;;) {
      this.buf = this.buf.replace(/^\s+/, '') // the buffer always starts at the start of a sentence or line
      if (!this.buf) break
      const nl = this.buf.indexOf('\n')

      if ('>>>'.startsWith(this.buf.slice(0, 3))) {
        if (nl < 0 && !end) break // may be a control line: wait for the whole line
        let line = nl < 0 ? this.buf : this.buf.slice(0, nl)
        this.buf = nl < 0 ? '' : this.buf.slice(nl + 1)
        const next = INLINE.exec(line) // two control lines written on one line: the second goes back to be read on its own
        if (next) { this.buf = `${line.slice(next.index).trim()}\n${this.buf}`; line = line.slice(0, next.index) }
        const m = CONTROL.exec(line.trim())
        if (m) out.push({ cmd: m[1].toLowerCase(), arg: m[2].trim() })
        else say(line)
        continue
      }

      const stop = SENTENCE_END.exec(this.buf)
      const inline = INLINE.exec(this.buf)
      const cuts = [stop ? stop.index + stop[0].length : -1, nl, inline ? inline.index : -1].filter(i => i >= 0)
      if (!cuts.length) {
        if (end) { say(this.buf); this.buf = '' }
        break
      }
      const cut = Math.min(...cuts)
      say(this.buf.slice(0, cut))
      this.buf = this.buf.slice(cut)
    }
    return out
  }
}
