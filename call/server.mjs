#!/usr/bin/env node
// A voice call with Claude Code: a fast "talker" holds the conversation, a full Claude Code
// session (the "worker") does the work in the project, and a small board of facts joins them.
//   node server.mjs <project-folder>      then talk in the Chrome page it opens
import { query, renameSession } from '@anthropic-ai/claude-agent-sdk'
import http from 'node:http'
import os from 'node:os'
import path from 'node:path'
import readline from 'node:readline'
import { randomBytes } from 'node:crypto'
import { spawn } from 'node:child_process'
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, statSync, writeFileSync } from 'node:fs'
import { readFile, unlink } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { Splitter } from './speech.mjs'
import { claudeEnv, findClaude } from './claude-path.mjs'
import { TUNE, unfinished } from './ears.mjs'
import { folders, pickFolder, nameFor, pick, toStop, stopProblem, askAs, Approvals, boardLines, pageBoard } from './workers.mjs'
import { voiceOk, askLine, stepWords, answerAloud } from './approve.mjs'
import { limitLine, dueLines } from './limits.mjs'
import { handOverAll, lendTerminal, openOne } from './handover.mjs'
import { dataDir, openBrowser } from './platform.mjs'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const NAME = 'Oh Kevin' // the product's name (Product.swift)
const [, , PROJECT_ARG] = process.argv
const PROJECT = path.resolve(PROJECT_ARG ?? '')
// Without a folder the project would be wherever the command ran, even this tool's own folder: never guess.
const refusal = !PROJECT_ARG ? 'No project folder was given'
  : !(existsSync(PROJECT) && statSync(PROJECT).isDirectory()) ? `"${PROJECT_ARG}" is not a folder`
  : realpathSync(PROJECT) === realpathSync(HERE) ? "That is the call server's own folder"
  : ''
if (refusal) { console.error(`${refusal}. Start it with the folder Claude Code should work in:  node server.mjs <project-folder>`); process.exit(2) }
const PORT = Number(process.env.PORT ?? 4747)
const KEY = process.env.CALL_KEY ?? randomBytes(16).toString('hex') // the page must present this: other sites can reach localhost too
const BOOT = randomBytes(4).toString('hex') // this process's own mark: a page that reconnects can tell a restarted server (same key, same port) from the one it lost
const MODELS = ['opus', 'sonnet', 'haiku', 'fable'] // what "use <model>" may switch the worker to
const PROJECTS = path.resolve(process.env.PROJECTS_DIR ?? path.dirname(PROJECT)) // "open a worker on api" opens a folder directly in here: next to the project
const KOKORO_DIR = process.env.KOKORO_DIR ?? path.join(dataDir(), 'Kokoro')
const KOKORO_RUNNER = path.join(KOKORO_DIR, 'kokoro-runner') // the local voice, when it is installed
const JOIN = TUNE.joinMs > 0 // waiting through a pause to think; the switch is joinMs in ears.mjs, read at startup
const VOICE_APPROVE = process.env.VOICE_APPROVE !== '0' // a spoken yes may approve the safe steps in approve.mjs; VOICE_APPROVE=0 is click-only, exactly as before
const VOICE_ALL = process.env.VOICE_APPROVE === 'all' // the safe-step list is off: a spoken yes may approve any step
const SPEAK_FIRST = process.env.SPEAK_FIRST !== '0' // usage-limit warnings are said on their own, in a lull (limits.mjs); SPEAK_FIRST=0 is exactly as before
const OPEN_IN_APP = process.env.OPEN_IN_APP !== '0' // Ctrl-C hangs up and opens the call in the Claude app (handover.mjs); OPEN_IN_APP=0 quits at once, exactly as before
const LAUNCHER = process.env.CALL_LAUNCHER === '1' // started by the menu-bar app: no terminal, and its pipe on stdin closes if it dies
// The first call on this Mac (shared with the Mac app, which runs this same server): it opens on "Say hello.", Kevin's first reply is a
// fixed line, and the first finished worker card carries a one-time hint. Both are remembered here, so each happens once.
const FIRST_FILE = process.env.FIRST_CALL_FILE ?? path.join(dataDir(), 'first-call.json')
const first = (() => { try { return { greeted: false, hinted: false, ...JSON.parse(readFileSync(FIRST_FILE, 'utf8')) } } catch { return { greeted: false, hinted: false } } })()
const FIRST_LINE = 'Hello. I hear you clearly. What shall we do first?'
const remember = patch => { Object.assign(first, patch); try { mkdirSync(path.dirname(FIRST_FILE), { recursive: true }); writeFileSync(FIRST_FILE, JSON.stringify(first)) } catch {} }

const show = (label, text) => console.log(`${`${label}:`.padEnd(13)}${text}`) // the lines printed at start
const clip = (s, n) => (s.length > n ? s.slice(0, n - 1) + '…' : s)
const describe = (name, input = {}) =>
  clip(`${name} ${input.command ?? input.file_path ?? input.pattern ?? input.url ?? input.description ?? ''}`.replace(/\s+/g, ' ').trim(), 140)

// ── page connection (server-sent events) ─────────────────────────────────────
const pages = new Set() // every event stream: call pages, and the launcher's status feed (watch), which is no one on the call
const callPages = () => [...pages].filter(res => !res.watch).length
const send = (type, data = {}) => {
  const line = `data: ${JSON.stringify({ type, ...data })}\n\n`
  for (const res of pages) res.write(line)
}
// Why the call page cannot use the microphone ('chrome': its site permission; 'mac': macOS keeps it from Chrome), or ''.
// The page says it; the launcher shows it with the one button that fixes it.
let micBlocked = ''
const setMic = why => { if (why !== micBlocked) { micBlocked = why; send('mic', { blocked: why }) } }
// What the voice is doing, for the launcher: the page says who has the floor and whether the mic is muted (/live);
// the server knows when the talker is composing a reply. canMute: the page has reported a mute state, so it also acts on /mute.
let micOff = null
const voiceState = () => micOff ? 'muted' : floor.voice ? 'speaking' : talkerBusy ? 'thinking' : 'listening'
let voiceTold = ''
const tellVoice = (to = null) => {
  const state = voiceState(), line = { state, canMute: micOff !== null }
  if (to) return to(line)
  const key = JSON.stringify(line)
  if (key !== voiceTold) { voiceTold = key; send('voice', line) }
}

// ── the board: the only facts the talker may report about the work ───────────
// Every worker has its own board (state: idle | working | waiting); the talker and the page see them all (workers.mjs).
const workers = []
const setBoard = (w, patch) => { Object.assign(w.board, patch); send('board', pageBoard(workers)) }
// With two or more workers open, everything about one carries its name; with one, it all reads exactly as before.
const who = w => (workers.length > 1 ? ` "${w.name}"` : '')
const byName = (w, text) => (workers.length > 1 ? `${w.name}: ${text}` : text)

// A queue that feeds user messages into a long-lived SDK session.
function inbox() {
  const q = []
  let wake
  return {
    push(text, priority) {
      q.push({ type: 'user', message: { role: 'user', content: text }, parent_tool_use_id: null, session_id: '', ...(priority && { priority }) })
      wake?.()
    },
    async *[Symbol.asyncIterator]() {
      for (;;) {
        while (q.length) yield q.shift()
        await new Promise(r => (wake = r))
      }
    },
  }
}

// ── the mouth: Kokoro running locally, one sentence at a time ────────────────
// Without a Kokoro install the page falls back to the browser's built-in voice.
const voice = { names: [], queue: [], busy: null, cache: new Map(), child: null, n: 0 }
function startVoice() {
  if (!existsSync(KOKORO_RUNNER) || !(statSync(KOKORO_RUNNER).mode & 0o111)) return show('Voice', `the browser's built-in voice. For the local voice, install Kokoro in ${KOKORO_DIR}`)
  voice.child = spawn(KOKORO_RUNNER, [KOKORO_DIR], { stdio: ['pipe', 'pipe', 'inherit'] })
  readline.createInterface({ input: voice.child.stdout }).on('line', async line => {
    let msg
    try { msg = JSON.parse(line) } catch { return } // stray library output
    if (msg.ready) { voice.names = msg.voices; send('voices', { names: voice.names }); show('Voice', `Kokoro, on this Mac, ${msg.threads || 'all'} cores`); return }
    const job = voice.busy
    if (!job || job.id !== msg.id) return
    voice.busy = null
    try {
      if (msg.error) throw new Error(msg.error)
      const wav = await readFile(msg.path)
      unlink(msg.path).catch(() => {})
      job.resolve(wav)
    } catch (err) { job.reject(err) }
    pump()
  })
  // Kokoro died: the sentence it was making and those waiting fail now, so the page says them with the browser voice instead of waiting forever.
  voice.child.on('exit', () => { voice.names = []; voice.child = null; voice.busy?.reject(new Error('voice stopped')); voice.busy = null; hushVoice(); send('voices', { names: [] }) })
  voice.child.stdin.on('error', () => {}) // a write as it dies must not take the server down
}
function pump() {
  if (voice.busy || !voice.queue.length || !voice.child) return
  voice.busy = voice.queue.shift()
  voice.child.stdin.write(JSON.stringify({ id: voice.busy.id, text: voice.busy.text, voice: voice.busy.voice }) + '\n')
}
function speak(text, name) {
  const key = `${name}|${text}`
  if (!voice.cache.has(key)) {
    const made = new Promise((resolve, reject) => { voice.queue.push({ id: String(++voice.n), text, voice: name, resolve, reject }); pump() })
    made.catch(() => voice.cache.delete(key))
    voice.cache.set(key, made) // "On it." and friends are spoken often: the second time is instant
    if (voice.cache.size > 300) voice.cache.delete(voice.cache.keys().next().value)
  }
  return voice.cache.get(key)
}
// Interrupted: sentences still waiting to be synthesised will never be played, so drop them.
const hushVoice = () => { for (const job of voice.queue.splice(0)) job.reject(new Error('interrupted')) }

// ── the talker ───────────────────────────────────────────────────────────────
// shortcut: every folder name in PROJECTS goes in the prompt (63 folders, 776 characters); with hundreds, list them only when an open fails
const TALKER_PROMPT = `You are Kevin, the voice on a live call between a developer and Claude Code. Everything you write is spoken aloud and the developer cannot see it, so write the way people talk: plain words, no markdown, no lists, no code, and no file paths spelled out.

Keep every reply short. One sentence is the norm and two is the limit. Lead with the answer. Skip greetings, skip repeating what they said, skip offers of more help, and skip filler such as "Great question" or "Certainly". Sound like a sharp colleague on a call, relaxed and exact, never formal.

You have a partner: a full Claude Code session, "the worker", that can read, edit and run things in the developer's project at ${PROJECT}. You cannot see the project yourself. When the developer asks for anything that needs the project looked at or changed, or something you cannot answer from this call alone, hand it over by ending your reply with control lines, each on its own line:
>>> do
The developer's exact words are passed to the worker automatically, so never rewrite their request. Add a one-line note only when their words alone would be unclear, because they point at something said earlier in the call or because speech recognition clearly garbled a name:
>>> do: <the missing context, in one line>
Say two or three words before the control line, such as "On it." or "Checking." Never guess at what the worker will find. If the worker is already busy, a do line reaches it as a mid-task instruction, so use one when the developer redirects the work.

Other control lines:
>>> topic: <two to five words naming the subject of the work>   Send it with your first do line of the call, and again only if the subject changes completely.
>>> model: <opus | sonnet | haiku | fable>   When the developer asks to switch the worker's model.
>>> stop   When the developer wants the work stopped or cancelled.
>>> open: <folder>   When the developer wants another worker, for another project or a parallel task. Write the folder exactly as one of these, picking the one they plainly mean, or ask if none fits: ${folders(PROJECTS).join(', ')}. The new worker is named after its folder, or "<folder> two" if that name is taken.${JOIN ? `
>>> wait   Write only this line, with nothing before it, when the developer stopped in the middle of a thought and more is plainly coming: their words break off mid-sentence, or are a lone word or fragment that asks for nothing yet, such as "check" or "so the". Their next words reach you joined to these. Never wait on a complete question or request, however short; when unsure, answer.` : ''}

With two or more workers open, every line about a worker names it, and so must yours: write its name after the command word, as in ">>> do web", ">>> do web: <note>", ">>> topic web: <words>", ">>> model web: sonnet" or ">>> stop web". A stop line without a name stops them all. When the developer asks for work without naming a worker, ask which one in a few words, such as "api or web?", and send nothing; once they answer, hand it to that worker with a note saying what the request was. Say a worker's name whenever you speak about one.

Lines in square brackets come from the system, not from the developer:
[board] says which model the worker runs on and what it is doing right now. Use it to answer questions like "how's it going" or "which model is this". Report only what it says and never invent progress.
[worker finished] carries the worker's full written answer. Give the gist in one or two short sentences: what was found or done, and anything it needs from them. The details are on their screen, so never read code or long lists aloud.
${VOICE_APPROVE ? '[worker needs approval] means the worker is paused on a step until the developer answers. It gives the sentence to say about it: say that sentence word for word. Only the system approves a step, so never say it is going ahead and never hand an approval to the worker with a do line, unless a [system] line says it was approved.' : '[worker needs approval] means the worker is paused until the developer clicks Approve or Deny on screen. Say in a few words what it wants to do.'}
${JOIN ? `[unfinished] means their words end on a word such as "and" or "the": wait, unless what they said is already complete.
[still waiting] means you waited and they have said nothing more for a few seconds. Do not wait again: answer what you can, or ask in a few words what they want.
` : ''}[interrupted] means the developer talked over you. It quotes what they actually heard; everything you said after that went unheard. Answer what they say now, and if something they missed still matters, say it again in a few words.${SPEAK_FIRST ? '\n[announced] is a sentence you already said aloud on your own, about their usage limits. Treat it as your own words: do not repeat it, mention it or comment on it unless they ask about it.' : ''}

For chat, opinions and brainstorming that do not need the project, just talk: be direct and ask one question at a time. Their words reach you through speech recognition and may contain mistakes, so if a request is unclear, ask a short question before handing it over.`

const talkerIn = inbox()
const talker = query({
  prompt: talkerIn,
  options: {
    model: process.env.TALKER_MODEL ?? 'haiku',
    systemPrompt: TALKER_PROMPT,
    tools: [], // it only talks; work goes through the control lines
    settingSources: [], // no user hooks, plugins or CLAUDE.md: keep it small and fast
    persistSession: false,
    thinking: { type: 'disabled' },
    effort: 'low',
    includePartialMessages: true,
    cwd: os.tmpdir(),
    pathToClaudeCodeExecutable: findClaude(), // the user's own Claude Code (claude-path.mjs)
    env: claudeEnv(), // without the call's own settings (claude-path.mjs)
  },
})

// What the developer said that the worker has not been given yet, word for word.
let unsent = []
let turnStartedAt = 0
// When the talker's current turn took its input: inputs that arrive while a turn runs are batched into the next one
// (measured), so a turn has answered only what came before turnFrom.
let turnFrom = 0, talkerBusy = false, queuedNext = false
let turnNo = 0, saidAny = false // which talker turn is taking input now, and whether the running one has sent words to be spoken
let waited = false // this turn was only ">>> wait": it answered nothing
// What the developer heard of the voice before talking over it; told to the talker with its next input.
let cutOff = null
// Set when they talk over a reply that is still being written: the rest of that reply is not spoken.
let muted = false
// Speaking first (limits.mjs): who has the floor as the page reports it, when the call last had any talk or input, limit lines
// waiting for a lull, what has been said of each limit, and lines said that the talker has not been told about yet.
const floor = { you: false, voice: false }
let quietFrom = Date.now()
const stir = () => { quietFrom = Date.now() }
const held = new Map(), limitsSaid = new Map()
let announced = []
let greeting = '' // the first call's hello and Kevin's fixed answer, told to the talker with its first input
const toTalker = text => {
  const note = cutOff == null ? ''
    : cutOff ? `[interrupted] The developer talked over you and heard only: "${cutOff}". Everything you said after that went unheard.\n`
    : '[interrupted] The developer talked over you before hearing anything of your last reply.\n'
  cutOff = null
  const told = announced.length ? `[announced] "${announced.splice(0).join(' ')}"\n` : '' // said before anything below
  const hi = greeting; greeting = ''
  stir()
  if (talkerBusy) queuedNext = true; else { talkerBusy = true; turnFrom = Date.now(); turnNo++ }
  talkerIn.push(hi + told + note + text)
  tellVoice()
}

async function runTalker() {
  let split = new Splitter()
  const act = items => {
    for (const it of items) {
      if (it.say) { if (!muted) { send('say', { text: it.say }); saidAny = true } }
      else if (it.cmd === 'do') delegate(it.arg)
      else if (it.cmd === 'stop') stopWork(it.arg)
      else if (it.cmd === 'model') setModel(it.arg)
      else if (it.cmd === 'topic') setTopic(it.arg)
      else if (it.cmd === 'open') open(it.arg)
      else if (it.cmd === 'wait') { waited = true; if (!queuedNext) send('wait') } // more words are already queued behind this turn: nothing to wait for
    }
  }
  for await (const m of talker) {
    if (m.type === 'stream_event') {
      turnStartedAt ||= Date.now()
      if (m.event.type === 'content_block_delta' && m.event.delta.type === 'text_delta') act(split.feed(m.event.delta.text))
    } else if (m.type === 'result') {
      act(split.flush())
      split = new Splitter()
      const ended = turnNo, aloud = saidAny && !muted // this turn's words all reached the page
      if (m.is_error) send('error', { text: `The voice could not answer${m.api_error_status ? ` (error ${m.api_error_status})` : ''}. Say it again in a moment.` }) // nothing was spoken: say why
      else if (!waited) unsent = unsent.filter(u => u.at > (JOIN ? turnFrom : turnStartedAt)) // words this turn answered as plain chat are not work requests
      if (queuedNext) { queuedNext = false; turnFrom = Date.now(); turnNo++ } else talkerBusy = false
      tellVoice()
      turnStartedAt = 0; muted = false; waited = false; saidAny = false
      const ask = aloud ? [...spoken].find(([, s]) => s.turn === ended)?.[0] : undefined // it said the question about this approval
      send('turn_end', ask ? { ask } : {})
      stir()
    } else if (m.type === 'rate_limit_event') heardLimit(m.rate_limit_info)
  }
}

// ── the worker: Claude Code itself, with the user's normal settings ──────────
const WORKER_NOTE = `The developer is talking to you through a voice call. Their requests arrive as speech-to-text transcripts of exactly what they said, so expect spoken phrasing and the odd misheard word; the voice on the call may add a short note for context. It speaks a brief summary of your final message back to them, and they also see your full message on a screen. End each turn with a plain one or two sentence summary of what you found or did and anything you need from them. If you need a decision, ask it as a plain question at the end of your message.`

const asks = new Map() // approval id -> resolver
// The worker may hand a job to a background agent and end its own turn while that agent keeps going, so
// "working" lasts while a turn runs or any background task is live.
const settle = w => { if (!w.turn && !approvals.of(w).length) setBoard(w, { state: w.bg.length ? 'working' : 'idle', ...(!w.bg.length && { step: '' }) }) }
// Open approvals the voice was told about: id -> { voice: may a spoken yes approve it, line: what the voice says, turn: the talker turn that says it }
const spoken = new Map()
// Every open approval, asked aloud one at a time (workers.mjs), so a plain yes or no always answers the one just asked.
const approvals = new Approvals()
// The real path of p through symlinks, for a file that may not exist yet: the deepest folder that exists is resolved.
function real(p) { try { return realpathSync(p) } catch { const up = path.dirname(p); return up === p ? p : path.join(real(up), path.basename(p)) } }
const AT = dir => ({ project: real(dir), real, exists: p => { try { lstatSync(p); return true } catch { return false } } }) // the worker gives real paths (/private/var, not /var)
// The talker input just sent asks the question about approval id: it is said in the running turn's successor if that turn was busy.
const askedIn = id => { spoken.get(id).turn = queuedNext ? turnNo + 1 : turnNo }
// What the talker is told about an approval when its turn to be asked comes.
function askText(a) {
  const line = askAs(a.line, workers.length > 1 && a.w.name)
  if (VOICE_APPROVE) spoken.set(a.id, { voice: a.voice, line })
  return `[worker${who(a.w)} needs approval] It wants to use: ${a.detail}${VOICE_APPROVE ? `\nSay exactly: "${line}"` : ''}`
}
// Asks the next approval in line, unless one is still being asked.
function sayNext() {
  const a = approvals.next()
  if (!a) return
  toTalker(askText(a))
  if (VOICE_APPROVE) askedIn(a.id)
}

// A worker is a Claude Code session of its own in one folder, with its own board. The first opens at startup in PROJECT.
function openWorker(dir) {
  const name = nameFor(path.basename(dir), workers.map(x => x.name))
  const w = { name, dir, in: inbox(), sessionId: null, turn: false, bg: [], halted: false, titled: '',
    board: { state: 'idle', task: '', step: '', model: process.env.WORKER_MODEL ?? 'opus', title: `Voice call / ${name}` } }
  w.q = startWorker(w)
  workers.push(w)
  send('board', pageBoard(workers))
  runWorker(w).catch(err => w.closing || fail(workers.length > 1 ? `Claude Code (${w.name})` : 'Claude Code')(err))
  return w
}
const startWorker = w => query({
  prompt: w.in,
  options: {
    cwd: w.dir,
    pathToClaudeCodeExecutable: findClaude(),
    env: claudeEnv(),
    model: w.board.model,
    permissionMode: 'auto', // no prompts for routine reads and edits; anything it still escalates lands on the page
    systemPrompt: { type: 'preset', preset: 'claude_code', append: WORKER_NOTE },
    disallowedTools: ['AskUserQuestion'], // questions come back as text so the voice can relay them
    canUseTool(tool, input, { signal }) {
      const id = randomBytes(6).toString('hex')
      const detail = describe(tool, input)
      setBoard(w, { state: 'waiting' })
      const voice = VOICE_APPROVE && (VOICE_ALL || voiceOk(tool, input, AT(w.dir)))
      const step = stepWords(tool, input) // the same words the voice says: "edit a.js", "run git commit"
      const full = clip(String(input.command ?? input.file_path ?? JSON.stringify(input)), 4000) // the card shows all of what is being approved, not the 140 characters of detail
      send('ask', { id, detail: byName(w, detail), worker: w.name, voice, full, step })
      approvals.add({ id, w, detail, voice, full, step, line: askLine(tool, input, voice) })
      sayNext() // now, or once the approvals before it are answered
      return new Promise(resolve => {
        const done = (allow, by) => {
          if (!asks.delete(id)) return
          spoken.delete(id)
          approvals.drop(id); setImmediate(sayNext) // the next in line, unless the words that answered this one already asked it
          setBoard(w, { state: 'working' })
          send('asked', { id, allow, ...(by && { by }) })
          resolve(allow ? { behavior: 'allow', updatedInput: input } : { behavior: 'deny', message: 'The developer declined this on the call.' })
        }
        asks.set(id, done)
        signal.addEventListener('abort', () => done(false), { once: true })
      })
    },
  },
})

async function runWorker(w) {
  let lastText = ''
  for await (const m of w.q) {
    if (m.type === 'system' && m.subtype === 'init') {
      w.sessionId = m.session_id
      send('session', { id: w.sessionId, worker: w.name, dir: w.dir })
    } else if (m.type === 'system' && m.subtype === 'background_tasks_changed') {
      w.bg = m.tasks.filter(t => !t.ambient).map(t => t.task_id)
      settle(w)
    } else if (m.type === 'rate_limit_event') {
      heardLimit(m.rate_limit_info)
    } else if (m.type === 'assistant' && !m.parent_tool_use_id) {
      if (!w.turn && w.board.state === 'idle') setBoard(w, { state: 'working' }) // a turn it started on its own, e.g. after a background task ended: Stop must work
      w.turn = true
      for (const b of m.message.content) {
        if (b.type === 'tool_use') { setBoard(w, { step: describe(b.name, b.input) }); send('step', { text: byName(w, w.board.step) }) }
        else if (b.type === 'text' && b.text.trim()) { lastText = b.text; send('worktext', { text: byName(w, b.text) }) }
      }
    } else if (m.type === 'result') {
      w.turn = false
      settle(w)
      applyTitle(w)
      if (w.halted) w.halted = false
      else toTalker(m.subtype === 'success' ? `[worker${who(w)} finished]\n${clip(m.result || lastText, 6000)}` : `[worker${who(w)} stopped before finishing] Reason: ${m.subtype}. Tell them it stopped early and ask whether to carry on.`)
      lastText = ''
    }
  }
}

// Acts on a spoken answer to the open approvals (approve.mjs decides) and returns what the talker is told before the words.
function byVoice(r) {
  if (r.act === 'deny') { for (const id of r.ids) asks.get(id)?.(false, 'voice'); return '[system] The developer said no by voice, so that step is declined. Confirm in two or three words.\n' }
  if (r.act === 'allow') { asks.get(r.id)?.(true, 'voice'); return '[system] The developer approved the step by voice. Confirm in two or three words.\n' }
  if (r.act === 'click') return '[system] A spoken yes cannot approve this step: it needs a click on screen. Say so in a few words.\n'
  if (r.act === 'again') return `[system] That yes did not count: it has to come right after the question has finished playing. Ask again with exactly: "${spoken.get(r.id).line}"\n`
  if (spoken.size) {
    const how = spoken.size === 1 && spoken.values().next().value.voice ? 'say just "yes" or click Approve' : 'click Approve on screen, since a spoken yes cannot approve it'
    return `[system] A step is still waiting for approval and these words did not answer it. If they seemed to mean yes, tell them in a few words to ${how}; otherwise answer as usual.\n`
  }
  return ''
}

// A usage-limit event from either session: a line worth saying waits for the next lull (limits.mjs), the newest per limit.
function heardLimit(info) {
  if (!SPEAK_FIRST) return
  const it = limitLine(info, limitsSaid, Date.now())
  if (it) held.set(it.type, it)
}
// Says the waiting limit lines once the call is in a lull. The talker hears what was said with its next input.
function announce() {
  const lines = dueLines(held, { pages: callPages(), ...floor, talking: talkerBusy, asking: asks.size > 0, quietFrom }, Date.now())
  if (!lines.length) return
  for (const text of lines) send('say', { text })
  send('turn_end') // the page closes this bubble, so the next reply gets its own
  announced.push(...lines)
  stir()
}
// The worker a control line is for, and the rest of the line. With two or more open, a line without a known name is for none.
function target(arg, reopen = false) {
  const { name, rest } = pick(arg, [...workers, ...closed].map(w => w.name))
  let w = workers.find(x => x.name === name)
  if (!w && reopen) { // work for a worker that was closed, or with none open: a fresh worker in that folder, not the old session
    const c = closed.find(x => x.name === name) ?? (!name && !workers.length ? closed.at(-1) ?? { dir: PROJECT } : null)
    if (c) { closed = closed.filter(x => x !== c); w = openWorker(c.dir) }
  }
  return { w: w ?? (workers.length === 1 ? workers[0] : null), rest }
}
let closed = [] // workers closed from their card: { name, dir }. Asked for again, they start fresh.
// Close on a card: the worker stops, its session ends (its work stays saved) and it leaves the call.
function closeWorker(w) {
  w.closing = true; halt(w); w.q.close()
  workers.splice(workers.indexOf(w), 1); closed.push({ name: w.name, dir: w.dir })
  if (lastTo === w) lastTo = null
  send('board', pageBoard(workers))
}
const names = () => workers.map(w => w.name).join(', ')
let lastTo = null // the worker the latest task went to: the page marks that task when its worker is stopped

// The developer's own words go first, exactly as spoken; the talker's note, if any, follows.
function delegate(arg) {
  const { w, rest: note } = target(arg, true)
  if (!w) { waited = true; return toTalker(`[system] Nothing was sent: with several workers open, a do line needs one of their names: ${names()}. Ask which one they mean, in a few words.`) } // their words wait for the answer
  const said = unsent.splice(0).slice(-8).map(u => u.text).join('\n')
  const extra = note ? `(Note from the voice on the call: ${note})` : ''
  const message = [said, extra].filter(Boolean).join('\n\n')
  if (!said) return // work starts only on the developer's own words, never on a note alone: text the worker read must not start more work
  const busy = w.board.state !== 'idle'
  w.turn = true; lastTo = w
  setBoard(w, { state: 'working', task: clip(said || note, 200), step: '' })
  send('task', { said: byName(w, said), note, steer: busy })
  const self = workers.length > 1 ? `\n\n(Several Claude Code sessions are on this call, each in its own folder. You are "${w.name}": do only what is meant for ${w.name}.)` : ''
  w.in.push(message + self, busy ? 'next' : undefined) // 'next': read after the current step, without cancelling it
}

// A stop line stops the worker it names; without a name, every worker.
function stopWork(arg) { const { w } = target(arg); for (const x of w ? [w] : workers) halt(x) }
// Stops one worker and denies its open approvals; true when it was busy.
function halt(w) {
  for (const a of approvals.of(w)) asks.get(a.id)?.(false)
  if (w.board.state === 'idle') return false
  if (w === lastTo) send('stopped')
  const failed = err => { const text = stopProblem(w, err); if (text) send('error', { text }) }
  if (w.turn) { w.halted = true; w.q.interrupt().catch(failed) }
  for (const id of w.bg) w.q.stopTask(id).catch(failed) // an interrupt leaves background agents running
  return true
}

function setModel(arg) {
  const { w, rest: name } = target(arg)
  if (!w) return toTalker(`[system] Nothing was switched: say which worker, by name: ${names()}. Ask which one they mean.`)
  const model = MODELS.find(m => name.toLowerCase().includes(m))
  if (!model) return toTalker(`[system] "${name}" is not a model the worker can use. The choices are ${MODELS.join(', ')}.`)
  w.q.setModel(model).then(() => setBoard(w, { model }), err => toTalker(`[system] Switching the worker to ${model} failed: ${err.message}`))
}

function setTopic(arg) {
  const { w, rest: topic } = target(arg)
  if (!w) return // shortcut: a topic line without a name, with several workers open, is dropped; ask for names if titles go missing
  const title = clip(`Voice call / ${w.name} / ${topic.replace(/\s+/g, ' ').trim()}`, 80) // the app shows 80 characters
  setBoard(w, { title })
  applyTitle(w)
}

// The session is named "Voice call / <worker> / <topic>" so it is easy to find, and api and api two in one folder differ.
// Renaming only works once the session file exists, so a failed attempt is retried after the next turn.
function applyTitle(w) {
  if (!w.sessionId || w.titled === w.board.title) return
  w.titled = w.board.title
  renameSession(w.sessionId, w.board.title, { dir: w.dir }).catch(() => { w.titled = '' })
}

// ">>> open: api" opens another worker, only in a folder that is exactly on the list in PROJECTS: a misheard word opens nothing.
function open(arg) {
  const list = folders(PROJECTS), folder = pickFolder(arg, list)
  if (!folder) return toTalker(`[system] No worker was opened: there is no folder called "${arg}". If one of these is plainly what they meant, open it; otherwise ask: ${list.join(', ')}.`)
  const w = openWorker(path.join(PROJECTS, folder))
  if (w.name !== folder) toTalker(`[system] The new worker in the ${folder} folder is named "${w.name}". Tell them in a few words.`)
}

// ── http ─────────────────────────────────────────────────────────────────────
const body = async req => {
  let raw = ''
  for await (const chunk of req) { raw += chunk; if (raw.length > 65536) throw new Error('too large') }
  return JSON.parse(raw || '{}')
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://127.0.0.1:${PORT}`)
    const hostOk = [`127.0.0.1:${PORT}`, `localhost:${PORT}`].includes(req.headers.host)
    const keyOk = (url.searchParams.get('k') ?? req.headers['x-key']) === KEY
    if (!hostOk || !keyOk) {
      if (!req.headers.accept?.includes('text/html')) return void res.writeHead(403).end('forbidden') // a script or the event stream: a short word will do
      return void res.writeHead(403, { 'content-type': 'text/html; charset=utf-8' }).end( // someone opened an old link
        `<!doctype html><meta charset="utf-8"><title>${NAME}</title><body style="font:17px/1.5 system-ui;max-width:30em;margin:20vh auto;padding:0 1em"><p>This link belongs to an earlier call. ${LAUNCHER ? 'Start a new call from the menu bar.' : 'Use the link the call server printed.'}</p>`)
    }

    if (req.method === 'GET' && url.pathname === '/') {
      return void res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' }).end(await readFile(path.join(HERE, 'index.html')))
    }
    if (req.method === 'GET' && ['/voice.mjs', '/ears.mjs', '/stats.mjs'].includes(url.pathname)) {
      return void res.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8', 'cache-control': 'no-store' }).end(await readFile(path.join(HERE, url.pathname)))
    }
    if (req.method === 'GET' && url.pathname === '/problem.mp3') { // the page plays it when the server reports a problem
      return void res.writeHead(200, { 'content-type': 'audio/mpeg', 'cache-control': 'max-age=3600' }).end(await readFile(path.join(HERE, 'problem.mp3')))
    }
    if (req.method === 'GET' && url.pathname === '/events') {
      res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store', connection: 'keep-alive' })
      res.watch = url.searchParams.has('watch')
      pages.add(res)
      send('pages', { n: callPages() }) // how many call pages are open, for the launcher
      const tell = (type, data) => res.write(`data: ${JSON.stringify({ type, ...data })}\n\n`)
      tell('board', pageBoard(workers))
      tell('hello', { boot: BOOT, project: PROJECT, projects: PROJECTS, voices: voice.names, spokenYes: VOICE_ALL ? 'all' : VOICE_APPROVE ? 'safe' : 'none', os: process.platform, first: !first.greeted, hint: !first.hinted })
      if (micBlocked) tell('mic', { blocked: micBlocked })
      tellVoice(line => tell('voice', line))
      for (const w of workers) { // a page that reloads mid-call gets its sessions and open approval cards back
        if (w.sessionId) tell('session', { id: w.sessionId, worker: w.name })
        for (const a of approvals.of(w)) tell('ask', { id: a.id, detail: byName(w, a.detail), worker: w.name, voice: a.voice, full: a.full, step: a.step })
      }
      req.on('close', () => { pages.delete(res); if (!callPages()) { floor.you = floor.voice = false; micOff = null; setMic(''); tellVoice() } send('pages', { n: callPages() }) }) // a closed page cannot say the voice stopped, nor that its microphone still fails
      return
    }
    if (req.method === 'GET' && url.pathname === '/tts') {
      const text = clip(url.searchParams.get('text') ?? '', 600).trim()
      const name = url.searchParams.get('voice') ?? ''
      if (!text || !voice.names.includes(name)) return void res.writeHead(503).end('no local voice')
      const wav = await speak(text, name)
      return void res.writeHead(200, { 'content-type': 'audio/wav', 'cache-control': 'no-store' }).end(wav)
    }
    if (req.method === 'POST') {
      const data = await body(req)
      if (url.pathname === '/say' && typeof data.text === 'string' && data.text.trim()) {
        const text = clip(data.text.trim(), 4000)
        if (!first.greeted) { // the first call's hello: a few words get the fixed reply; a real task on the first words goes on as usual
          remember({ greeted: true })
          if (text.split(/\s+/).length <= 4) {
            send('say', { text: FIRST_LINE }); send('turn_end'); stir()
            greeting = `[first call] The developer said "${text}" and you answered aloud: "${FIRST_LINE}"\n`
            return void res.writeHead(204).end()
          }
        }
        if (JOIN) unsent = unsent.filter(u => !text.startsWith(u.text)) // the page sends a thought you added to whole: it replaces the first part
        unsent.push({ text, at: Date.now() })
        const tag = !JOIN ? '' : data.done ? '[still waiting]\n' : unfinished(text) ? '[unfinished]\n' : ''
        const heard = VOICE_APPROVE ? answerAloud(text, [...spoken].map(([id, s]) => ({ id, voice: s.voice })), typeof data.ask === 'string' ? data.ask : '') : { act: 'none' }
        const sys = byVoice(heard), next = approvals.next() // a step answered by voice just now: the next question in line rides on these words
        toTalker(`${sys}${next ? `${askText(next)}\n` : ''}${tag}${boardLines(workers)}\n${text}`)
        if (heard.act === 'again') askedIn(heard.id) // this turn asks the question again, so its end re-arms the page
        if (next && VOICE_APPROVE) askedIn(next.id)
      } else if (url.pathname === '/permit') asks.get(data.id)?.(data.allow === true)
      else if (url.pathname === '/stop') { // {name}: that worker only; no name: every worker
        const which = toStop(workers, data.name)
        if (which.map(halt).includes(true)) toTalker(typeof data.name === 'string'
          ? `[system] The developer pressed Stop on ${data.name} and its work has been stopped; the other workers go on. Confirm in two or three words, naming ${data.name}.`
          : '[system] The developer pressed the Stop button and the work has been stopped. Confirm in two or three words.')
      }
      else if (url.pathname === '/hangup') { send('hangup'); if (LAUNCHER) setImmediate(() => hangUp('SIGINT')) } // End call on the launcher's page ends the call, as Ctrl-C does
      else if (url.pathname === '/mic') { if (['', 'chrome', 'mac'].includes(data.blocked)) setMic(data.blocked) } // the page's microphone failed, or works again
      else if (url.pathname === '/live') { for (const k of ['you', 'voice']) if (typeof data[k] === 'boolean') floor[k] = data[k]; if (typeof data.muted === 'boolean') micOff = data.muted; stir(); tellVoice() } // you or the voice started or stopped; the mic was muted or not
      else if (url.pathname === '/hinted') remember({ hinted: true }) // the page showed the first card's one-time hint
      else if (url.pathname === '/close') { const w = workers.find(x => x.name === data.name); if (w) closeWorker(w) } // {name}: Close on a finished worker's card
      else if (url.pathname === '/open') { // Open in Claude on a card, {name}: that worker leaves the call for the Claude app
        const w = workers.find(x => x.name === data.name)
        if (w?.sessionId) {
          const { name, sessionId: id, dir, board: { title } } = w
          closeWorker(w) // as Close: stopped, its session ended, gone from the board; asked again, a fresh one starts
          openOne({ id, cwd: dir, rename: () => renameSession(id, title, { dir }) }).then(r => r.ok
            ? toTalker(`[system] The worker ${name} is open in the Claude app now and no longer on this call. Tell the developer in a few words that ${name} is in the Claude app.`)
            : send('error', { text: `Could not open ${name} in the Claude app: ${r.why || 'the Claude Code command failed'}. It has left this call; its work is saved in Claude Code.` }))
        }
      }
      else if (url.pathname === '/mute') { if (typeof data.on === 'boolean') send('mute', { on: data.on }) } // the launcher asks; the page mutes and says so on /live
      else if (url.pathname === '/hush') {
        hushVoice()
        if (typeof data.heard === 'string') { cutOff = clip(data.heard.trim(), 1000); muted = turnStartedAt > 0 } // only sent when something was cut
      }
      else return void res.writeHead(404).end()
      return void res.writeHead(204).end()
    }
    res.writeHead(404).end()
  } catch (err) {
    if (!res.headersSent) res.writeHead(err.message === 'interrupted' ? 410 : 400)
    res.end(String(err.message))
  }
})

setInterval(() => { for (const res of pages) res.write(': keep-alive\n\n') }, 20000).unref()
if (SPEAK_FIRST) setInterval(announce, 500).unref()
let stopping = false // hanging up: the worker, the talker and the voice are being closed on purpose
const fail = who => err => { if (stopping) return; console.error(`${who} stopped:`, err); send('error', { text: `${who} stopped (${err.message}). ${LAUNCHER ? 'Start a new call' : 'Restart the call server'} to carry on; the work so far is saved.` }) }
runTalker().catch(fail('The voice'))
openWorker(PROJECT)
startVoice()
process.on('exit', () => voice.child?.kill())
// Hanging up. After a call with work, every worker is closed and each session handed to the Claude app in turn (handover.mjs):
// Ctrl-C in a terminal opens it there, a kill prints the command that does. A second Ctrl-C quits at once.
async function hangUp(signal) {
  if (stopping && LAUNCHER) return // the launcher's second word during a hand-over: finish it, so the exit code stays true
  if (stopping || !OPEN_IN_APP || !workers.some(w => w.sessionId)) return process.exit(0)
  stopping = true
  for (const w of workers) w.q.close()
  talker.close(); voice.child?.kill()
  const results = await handOverAll(workers.map(w => ({ id: w.sessionId, cwd: w.dir, rename: () => renameSession(w.sessionId, w.board.title, { dir: w.dir }) })),
    { open: signal === 'SIGINT', tty: LAUNCHER || !!(process.stdin.isTTY && process.stdout.isTTY), ...(LAUNCHER && { run: lendTerminal }) })
  process.exit(LAUNCHER && results.includes('printed') ? 3 : 0) // 3 tells the launcher the work did not open in the Claude app
}
process.on('SIGINT', hangUp)
process.on('SIGTERM', hangUp)
if (LAUNCHER) process.stdin.on('end', () => hangUp('SIGTERM')).resume() // the launcher died or was force-quit: never outlive it

server.on('error', err => {
  if (err.code !== 'EADDRINUSE') throw err
  console.error(`Port ${PORT} is in use, probably by another call. End that call with Ctrl-C, or start this one with PORT=${PORT + 1}.`)
  process.exit(1)
})
server.listen(PORT, '127.0.0.1', () => {
  const link = `http://127.0.0.1:${PORT}/?k=${KEY}`
  show('Project', PROJECT)
  show('Claude Code', `${workers[0].board.model}, auto mode (edits, commands and network run without asking; its safety checks refuse what is dangerous)`)
  show('Projects', `${PROJECTS} (say "open a worker on <folder>")`)
  if (VOICE_ALL) show('Approvals', 'a spoken yes approves any step')
  else if (VOICE_APPROVE) show('Approvals', 'a spoken yes approves edits, new files and git add, commit or new branch in the project; the rest need a click')
  if (SPEAK_FIRST) show('Limits', 'the voice warns you when a usage limit is near')
  if (!LAUNCHER && OPEN_IN_APP) show('Hang up', 'Ctrl-C ends the call and opens its work in the Claude app')
  show('Call page', link)
  if (!LAUNCHER) console.log('Open it in Chrome. Other browsers lack the speech recognition it uses.')
  if (!process.env.NO_OPEN) openBrowser(link) // Chrome, else the default browser (platform.mjs). NO_OPEN=1 skips this.
})
