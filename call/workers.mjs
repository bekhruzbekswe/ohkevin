// Several workers on one call: the folders a worker may be opened in, its name, which worker a control line means,
// the order approvals are asked aloud, and the board lines. Pure, apart from listing the projects folder.
// Tested by workers.test.mjs.
import { readdirSync } from 'node:fs'
import { spokenAnswer } from './approve.mjs'

// The folders a worker may be opened in by voice: the visible folders directly in root (not files, links or .hidden).
export function folders(root) {
  try { return readdirSync(root, { withFileTypes: true }).filter(d => d.isDirectory() && !d.name.startsWith('.')).map(d => d.name).sort() }
  catch { return [] }
}

// The folder the talker named, from that list: exactly, or the only one that differs in case. Never a guess.
export function pickFolder(said, list) {
  const s = String(said).trim().replace(/^["“]+|["”.]+$/g, '')
  const hits = list.filter(f => f.toLowerCase() === s.toLowerCase())
  return hits.includes(s) ? s : hits.length === 1 ? hits[0] : null
}

const key = name => String(name).toLowerCase().replace(/["“”]/g, '').replace(/[\s_-]+/g, ' ').trim()
const NTH = ['two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten']
// A worker is named after its folder; a second one there is "<folder> two", then "three". A name that sounds like a no
// ("stop", "no-limits") would decline the step being asked whenever the voice says it, so that worker is called "worker".
export function nameFor(folder, taken) {
  const base = spokenAnswer(folder.replace(/[-_.]+/g, ' ')) === 'no' ? 'worker' : folder
  const used = new Set(taken.map(key))
  for (let n = 1; ; n++) {
    const name = n === 1 ? base : `${base} ${NTH[n - 2] ?? n}`
    if (!used.has(key(name))) return name
  }
}

// Which worker a control line names, and the rest of it: "web: check the logs" gives web and "check the logs".
// A line without an open worker's name gives null and the whole line, so a misheard name never picks a worker.
export function pick(arg, names) {
  const named = s => names.find(n => key(n) === key(s)) ?? null
  const i = arg.indexOf(':'), head = i < 0 ? null : named(arg.slice(0, i))
  if (head) return { name: head, rest: arg.slice(i + 1).trim() }
  return named(arg) ? { name: named(arg), rest: '' } : { name: null, rest: arg }
}

// The question about a step, with the worker's name in place of "It" when one is given.
// The Stop button's workers: the one it names, or every worker when it names none. A name no worker has stops nothing.
export const toStop = (list, name) => (typeof name === 'string' ? list.filter(w => w.name === name) : list)

// What a failed stop says, if anything: a worker being closed or handed over ends anyway, so its cut-short interrupt is no problem.
export const stopProblem = (w, err) => (w.closing ? null : `Could not stop the work: ${err.message}`)

export const askAs = (line, name) => (name ? line.replace(/^It\b/, name) : line)

// Approvals are asked aloud one at a time, oldest first; the others wait, their cards still clickable, until it is answered.
export class Approvals {
  #open = [] // in the order they came; the first is the one being asked once next() has returned it
  #asked = false
  add(a) { this.#open.push(a) }
  // The approval to ask aloud now, or null while one is being asked or none is open.
  next() {
    if (this.#asked || !this.#open.length) return null
    this.#asked = true
    return this.#open[0]
  }
  drop(id) {
    const i = this.#open.findIndex(a => a.id === id)
    if (i < 0) return
    this.#open.splice(i, 1)
    if (i === 0) this.#asked = false
  }
  of(w) { return this.#open.filter(a => a.w === w) }
}

const doing = b => b.state === 'idle' ? 'is idle'
  : b.state === 'waiting' ? `is waiting for an on-screen approval while working on: ${b.task}`
  : `is working on: ${b.task}${b.step ? `; its latest step: ${b.step}` : ''}`
// What the talker gets with every utterance: one worker reads exactly as before; several get one named line each.
export const boardLines = list => !list.length ? '[board] no worker is open: work you send starts a fresh one'
  : list.length === 1
  ? `[board] the worker runs on the ${list[0].board.model} model and ${doing(list[0].board)}`
  : list.map(w => `[board] the worker "${w.name}" runs on the ${w.board.model} model and ${doing(w.board)}`).join('\n')

// The one board event the page shows. One worker: its board as before. Several: the busiest state, every model and title.
export function pageBoard(list) {
  const workers = list.map(w => ({ name: w.name, ...w.board })) // each worker's own board, so the page never reads names out of text
  if (list.length === 1) return { ...list[0].board, workers }
  const states = list.map(w => w.board.state)
  return {
    state: ['waiting', 'working'].find(s => states.includes(s)) ?? 'idle',
    model: list.map(w => `${w.name} ${w.board.model}`).join(' · '),
    title: list.map(w => w.board.title.replace('Voice call / ', '')).join(' · '),
    workers,
  }
}
