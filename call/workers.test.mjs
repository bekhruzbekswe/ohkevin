import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, writeFileSync, symlinkSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { folders, pickFolder, nameFor, pick, toStop, stopProblem, askAs, Approvals, boardLines, pageBoard } from './workers.mjs'
import { askLine, spokenAnswer } from './approve.mjs'

test('folders: the visible folders directly in the root, sorted; nothing when the root is missing', () => {
  const root = mkdtempSync(path.join(tmpdir(), 'workers-'))
  for (const d of ['web', 'api', '.hidden', 'claude-voice', 'api/deeper']) mkdirSync(path.join(root, d))
  writeFileSync(path.join(root, 'notes.txt'), '')
  symlinkSync(path.join(root, 'web'), path.join(root, 'web-link'))
  assert.deepEqual(folders(root), ['api', 'claude-voice', 'web'])
  assert.deepEqual(folders(path.join(root, 'missing')), [])
  rmSync(root, { recursive: true })
})

test('pickFolder: only a folder on the list, exactly or differing in case', () => {
  const list = ['api', 'claude-voice', 'Gymo', 'web']
  assert.equal(pickFolder('api', list), 'api')
  assert.equal(pickFolder(' claude-voice ', list), 'claude-voice')
  assert.equal(pickFolder('gymo', list), 'Gymo')
  assert.equal(pickFolder('API', list), 'api')
  assert.equal(pickFolder('"web".', list), 'web') // quoted or with a full stop, as a model may write it
  for (const s of ['claude voice', 'cloud-voice', 'ap', 'apis', 'the api', '../api', 'api/..', '/Users/x/Lab/api', '', '.', 'web two'])
    assert.equal(pickFolder(s, list), null, s)
  assert.equal(pickFolder('readme', ['README', 'readme']), 'readme') // an exact match wins
  assert.equal(pickFolder('ReadMe', ['README', 'readme']), null) // two that differ only in case: no guess
  assert.equal(pickFolder('api', []), null)
})

test('nameFor: the folder name, then "two", "three"…; a name that sounds like a no is "worker"', () => {
  assert.equal(nameFor('api', []), 'api')
  assert.equal(nameFor('api', ['web']), 'api')
  assert.equal(nameFor('api', ['api']), 'api two')
  assert.equal(nameFor('api', ['api', 'api two']), 'api three')
  assert.equal(nameFor('API', ['api']), 'API two') // names match ignoring case
  assert.equal(nameFor('claude-voice', ['claude voice']), 'claude-voice two')
  const many = ['x']; for (let i = 0; i < 11; i++) many.push(nameFor('x', many))
  assert.deepEqual(many.slice(-3), ['x ten', 'x 11', 'x 12'])
  for (const f of ['stop', 'Stop', 'no', 'nope', 'cancel', 'deny', 'decline', 'dont', 'no-limits', 'stop_it', 'do-not-disturb', 'nah.app'])
    assert.equal(nameFor(f, []), 'worker', f)
  assert.equal(nameFor('stop', ['worker']), 'worker two')
  for (const f of ['stopwatch', 'nobody', 'notes', 'go', 'yes', 'sure', 'donut', 'cancellation'])
    assert.equal(nameFor(f, []), f, f)
})

test('a named question never sounds like an answer, whatever the folder is called', () => {
  for (const f of ['api', 'stop', 'no', 'cancel', 'no-limits', 'do-not-disturb', 'yes', 'go', 'sure', 'approve', 'go ahead', 'claude-voice']) {
    const name = nameFor(f, [])
    for (const voice of [true, false]) {
      const line = askAs(askLine('Write', { file_path: '/p/a.txt' }, voice), name)
      assert.ok(line.startsWith(`${name} wants to write a.txt`), line)
      assert.equal(spokenAnswer(line), null, line) // its own echo is no answer
      assert.equal(spokenAnswer(line.replace(/[-_.]+/g, ' ')), null, line) // nor as the voice says it
    }
  }
  assert.equal(askAs('It wants to edit a.js. Should it go ahead?', 'web'), 'web wants to edit a.js. Should it go ahead?')
  assert.equal(askAs('It wants to edit a.js. Should it go ahead?', false), 'It wants to edit a.js. Should it go ahead?')
})

test('pick: a known name before the colon or alone; anything else names no worker', () => {
  const names = ['api', 'web', 'api two', 'claude-voice']
  assert.deepEqual(pick('web', names), { name: 'web', rest: '' })
  assert.deepEqual(pick('web: the login page', names), { name: 'web', rest: 'the login page' })
  assert.deepEqual(pick('Web:check it', names), { name: 'web', rest: 'check it' })
  assert.deepEqual(pick('api two: sonnet', names), { name: 'api two', rest: 'sonnet' })
  assert.deepEqual(pick('api two', names), { name: 'api two', rest: '' })
  assert.deepEqual(pick('"web"', names), { name: 'web', rest: '' })
  assert.deepEqual(pick('claude voice: x', names), { name: 'claude-voice', rest: 'x' })
  assert.deepEqual(pick('', names), { name: null, rest: '' })
  assert.deepEqual(pick('opus', names), { name: null, rest: 'opus' })
  assert.deepEqual(pick('the file is notes.txt', names), { name: null, rest: 'the file is notes.txt' })
  assert.deepEqual(pick('wbe: fix it', names), { name: null, rest: 'wbe: fix it' })
  assert.deepEqual(pick('note: web', names), { name: null, rest: 'note: web' })
  assert.deepEqual(pick('web two', names), { name: null, rest: 'web two' })
  assert.deepEqual(pick('all', names), { name: null, rest: 'all' })
})

test('Approvals: one asked at a time, oldest first; answering any of them moves the line on', () => {
  const q = new Approvals(), api = { name: 'api' }, web = { name: 'web' }
  assert.equal(q.next(), null)
  q.add({ id: 'a', w: api })
  assert.equal(q.next().id, 'a')
  q.add({ id: 'b', w: web }); q.add({ id: 'c', w: api })
  assert.equal(q.next(), null) // a is still being asked
  assert.deepEqual(q.of(api).map(a => a.id), ['a', 'c'])
  q.drop('c') // clicked while waiting: never asked
  assert.equal(q.next(), null)
  q.drop('a')
  assert.equal(q.next().id, 'b')
  assert.equal(q.next(), null)
  q.drop('zzz') // unknown: nothing changes
  assert.equal(q.next(), null)
  q.drop('b')
  assert.equal(q.next(), null)
  assert.deepEqual(q.of(api), [])
  q.add({ id: 'd', w: web })
  assert.equal(q.next().id, 'd')
})

const board = (state, task = '', step = '', model = 'opus', title = 'Voice call') => ({ state, task, step, model, title })
test('boardLines: one worker reads exactly as before; several get a named line each', () => {
  assert.equal(boardLines([{ name: 'api', board: board('idle') }]), '[board] the worker runs on the opus model and is idle')
  assert.equal(boardLines([{ name: 'api', board: board('working', 'fix the test', 'Bash npm test') }]),
    '[board] the worker runs on the opus model and is working on: fix the test; its latest step: Bash npm test')
  assert.equal(boardLines([{ name: 'api', board: board('waiting', 'fix the test', 'Bash npm test') }]),
    '[board] the worker runs on the opus model and is waiting for an on-screen approval while working on: fix the test')
  assert.equal(boardLines([{ name: 'api', board: board('working', 'fix it') }, { name: 'web', board: board('idle', '', '', 'haiku') }]),
    '[board] the worker "api" runs on the opus model and is working on: fix it\n[board] the worker "web" runs on the haiku model and is idle')
})

test('pageBoard: one worker is its own board; several show the busiest state and every model and title', () => {
  const one = board('working', 't', 's')
  assert.deepEqual(pageBoard([{ name: 'api', board: one }]), { ...one, workers: [{ name: 'api', ...one }] })
  const api = { name: 'api', board: board('idle', '', '', 'opus', 'Voice call / api / Login bug') }, web = { name: 'web', board: board('working', '', '', 'haiku', 'Voice call / web') }
  assert.deepEqual(pageBoard([api, web]), { state: 'working', model: 'api opus · web haiku', title: 'api / Login bug · web',
    workers: [{ name: 'api', ...api.board }, { name: 'web', ...web.board }] })
  web.board.state = 'waiting'
  assert.equal(pageBoard([api, web]).state, 'waiting')
  web.board.state = 'idle'
  assert.equal(pageBoard([api, web]).state, 'idle')
})

test('the Stop button stops the worker it names, every worker when it names none, and nothing for a name no worker has', () => {
  const api = { name: 'api' }, web = { name: 'web' }
  assert.deepEqual(toStop([api, web], 'web'), [web])
  assert.deepEqual(toStop([api, web], undefined), [api, web])
  assert.deepEqual(toStop([api, web], 'docs'), [])
})

test('with every worker closed, the voice is told that new work starts a fresh one', () => {
  assert.match(boardLines([]), /no worker is open: work you send starts a fresh one/)
})

test('a stop cut short by Close or Open in Claude is no problem; a failed Stop button still says so', () => {
  const err = new Error('Query closed before response received')
  assert.equal(stopProblem({ closing: true }, err), null)
  assert.equal(stopProblem({}, err), 'Could not stop the work: Query closed before response received')
})
