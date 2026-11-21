// Drives a test call server without a browser: sends each argument as if spoken, approves requests, logs events with timings.
// Start the server first:  NO_OPEN=1 CALL_KEY=testkey PORT=4799 WORKER_MODEL=haiku node server.mjs <throwaway-folder>
// CUT=1 cuts the voice off after the first sentence of each reply, as if talked over, and logs later sentences of that reply as AFTER.
// PERMIT=0 does not click Approve: answers are spoken instead, and the next line is sent while an approval is open.
// A line starting with + is sent as a clean spoken answer to the last question the voice finished (the page's ask field).
// Then:                    node drive.mjs "first thing said" "second thing said"
const base = `http://127.0.0.1:${process.env.PORT ?? 4799}`, k = process.env.CALL_KEY ?? 'testkey'
const lines = process.argv.slice(2)
const t0 = Date.now()
const log = (...a) => console.log(((Date.now() - t0) / 1000).toFixed(2).padStart(7), ...a)
const post = (p, b) => fetch(base + p, { method: 'POST', headers: { 'content-type': 'application/json', 'x-key': k }, body: JSON.stringify(b) })
const CUT = process.env.CUT === '1'
const PERMIT = process.env.PERMIT !== '0'
let armed = ''
let cut = false
let state = 'idle', model = '', title = '', sentAt = 0, started = false
const next = () => {
  const line = lines.shift()
  if (!line) { log('done'); process.exit(0) }
  sentAt = Date.now(); log('YOU    ', line)
  post('/say', line.startsWith('+') ? { text: line.slice(1), ask: armed } : { text: line })
}
setTimeout(() => { log('TIMEOUT'); process.exit(1) }, 280000)
const res = await fetch(`${base}/events?k=${k}`)
let buf = ''
for await (const chunk of res.body) {
  buf += Buffer.from(chunk).toString()
  let i
  while ((i = buf.indexOf('\n\n')) >= 0) {
    const raw = buf.slice(0, i); buf = buf.slice(i + 2)
    if (!raw.startsWith('data: ')) continue
    const e = JSON.parse(raw.slice(6))
    if (e.type === 'board') {
      if (e.state !== state || e.model !== model || e.title !== title) log('board  ', e.state, '| model', e.model, '|', e.title)
      state = e.state; model = e.model; title = e.title
      if (!started) { started = true; next() }
    }
    else if (e.type === 'say') {
      log(cut ? 'AFTER  ' : 'VOICE  ', e.text, sentAt ? `(+${((Date.now() - sentAt) / 1000).toFixed(2)}s)` : ''); sentAt = 0
      if (CUT && !cut) { cut = true; post('/hush', { heard: e.text.split(' ').slice(0, 3).join(' ') }) }
    }
    else if (e.type === 'ask') { log('ASK    ', e.detail); if (PERMIT) setTimeout(() => post('/permit', { id: e.id, allow: true }), 300) }
    else if (e.type === 'turn_end') {
      if (e.ask) { armed = e.ask; log('ARMED  ', e.ask) }
      cut = false
      const ready = () => state === 'idle' || (!PERMIT && state === 'waiting')
      if (ready()) setTimeout(() => ready() && next(), 1500)
    }
    else if (e.type === 'task') log('TASK   ', JSON.stringify({ said: e.said, note: e.note, steer: e.steer }))
    else if (e.type === 'step') log('step   ', e.text.slice(0, 100))
    else if (e.type === 'worktext') log('worker ', e.text.replace(/\s+/g, ' ').slice(0, 160))
    else if (e.type === 'hello') log('hello  ', e.voices.length, 'voices')
    else if (e.type !== 'voices' && e.type !== 'session') log(e.type.padEnd(7), JSON.stringify(e).slice(0, 160))
  }
}
