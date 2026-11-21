// A stand-in for call/server.mjs in AppChecks --scene: the same event stream and routes, a call page that only
// connects (no microphone), and no Claude, so a test costs nothing. It records what it is sent.
// The test steers it through files beside it (read at start) and routes of its own:
//   file "die"      exits at once, as a server that breaks while starting
//   file "silent"   never listens, as a server that never answers
//   file "printed"  the hand-over did not open the Claude app: an ending exits with 3, as call/server.mjs does
//   file "stuck"    an ending never finishes (the app must end it after 30 s)
//   POST /_emit {type, …}  puts an event on the stream (keeping the board and open requests for new connections)
//   POST /_drop            closes every stream, as a sleep or a network hiccup would
//   POST /_fail            the next /permit or /stop answers 500
//   POST /_exit            exits with code 1, as a crash would
//   GET  /_log             what it was sent, as JSON
// Every start is written to the file "starts" beside it, one line each.
import http from 'node:http'
import { existsSync, appendFileSync } from 'node:fs'

const here = file => existsSync(new URL(file, import.meta.url))
appendFileSync(new URL('starts', import.meta.url), `${process.pid}\n`)
process.stdin.on('end', () => process.exit(0)).resume() // the app's pipe, as in server.mjs
if (here('die')) process.exit(1)
if (!here('silent')) {
  const PORT = Number(process.env.PORT), KEY = process.env.CALL_KEY
  const streams = new Set(), log = [], asks = new Map()
  let board = { type: 'board', state: 'idle', workers: [{ name: 'api', state: 'idle', task: '', step: '', model: 'opus' }] }
  let fail = false
  const line = e => `data: ${JSON.stringify(e)}\n\n`
  const send = e => { for (const s of streams) s.write(line(e)) }
  const pages = () => [...streams].filter(s => !s.watch).length
  let stopping = false // as in server.mjs: a second word while ending is ignored, so the exit code stays true
  const end = () => { if (stopping || here('stuck')) return; stopping = true; setTimeout(() => process.exit(here('printed') ? 3 : 0), 1500) }
  http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1')
    if ((url.searchParams.get('k') ?? req.headers['x-key']) !== KEY) return void res.writeHead(403).end('forbidden')
    if (url.pathname === '/') {
      return void res.writeHead(200, { 'content-type': 'text/html' }).end(
        `<!doctype html><title>Call</title><p>A stand-in call page.</p><script>new EventSource('/events?k=${KEY}')</script>`)
    }
    if (url.pathname === '/events') {
      res.writeHead(200, { 'content-type': 'text/event-stream' })
      res.watch = url.searchParams.has('watch')
      streams.add(res)
      res.write(line(board)); res.write(line({ type: 'hello' }))
      res.write(line({ type: 'voice', state: 'listening', canMute: true })) // as the real server: the voice's state on connect, from a page that can mute
      for (const a of asks.values()) res.write(line(a))
      send({ type: 'pages', n: pages() })
      req.on('close', () => { streams.delete(res); send({ type: 'pages', n: pages() }) })
      return
    }
    if (url.pathname === '/_log') return void res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(log))
    let body = ''
    for await (const chunk of req) body += chunk
    const data = body ? JSON.parse(body) : {}
    if (url.pathname === '/_emit') {
      if (data.type === 'board') board = data
      if (data.type === 'ask') asks.set(data.id, data)
      if (data.type === 'asked') asks.delete(data.id)
      send(data)
      return void res.writeHead(204).end()
    }
    if (url.pathname === '/_drop') { for (const s of streams) if (s.watch) s.destroy(); return void res.writeHead(204).end() }
    if (url.pathname === '/_fail') { fail = true; return void res.writeHead(204).end() }
    if (url.pathname === '/_exit') { res.writeHead(204).end(); setTimeout(() => process.exit(1), 50); return }
    log.push({ path: url.pathname, body: data })
    if (fail && url.pathname !== '/hangup') { fail = false; return void res.writeHead(500).end() }
    res.writeHead(204).end()
    if (url.pathname === '/hangup') { send({ type: 'hangup' }); end() } // the page's End: the server ends the call itself
  }).listen(PORT, '127.0.0.1')
  for (const s of ['SIGINT', 'SIGTERM']) process.on(s, () => { log.push({ path: s }); end() })
}
