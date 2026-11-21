import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { command, childrenGone, handOver, handOverAll, lendTerminal, openOne } from './handover.mjs'

const ID = '0b5a2c9e-1f4d-4c1e-9a7b-3c2d1e0f9a8b'
const PRINT = `log To open this call in the Claude app:  ${command(ID, '/p')}` // in this system's shell (platform.test.mjs has each)
// A pretend hang-up that records each step instead of starting the CLI or the app.
async function hangUp({ open = true, tty = true, free = true, code = 0, renameFails = false, ...o } = {}) {
  const steps = []
  const result = await handOver({
    id: 'id' in o ? o.id : ID, cwd: '/p', open, tty,
    rename: async () => { steps.push('rename'); if (renameFails) throw new Error('no transcript') },
    run: async (args, cwd) => { steps.push(`run ${args.join(' ')} in ${cwd}`); return code },
    gone: async () => { steps.push('gone'); return free },
    log: line => steps.push(`log ${line}`),
  })
  return { result, steps }
}

test('command is the CLI hand-over line', () => {
  assert.equal(command(ID), `claude --desktop --resume ${ID}`)
  assert.equal(command(ID, "/Users/me/it's here", 'darwin'), `cd '/Users/me/it'\\''s here' && claude --desktop --resume ${ID}`) // from its own folder, quoted for the shell
})

test('a call with no work hands nothing over', async () => {
  for (const id of [null, undefined, '']) assert.deepEqual(await hangUp({ id }), { result: 'none', steps: [] })
})

test('Ctrl-C in a terminal opens the call in the app once the worker is gone and the title is written', async () => {
  assert.deepEqual(await hangUp(), { result: 'opened', steps: ['gone', 'rename', `run --desktop --resume ${ID} in /p`] })
})

test('a kill, no terminal, or a worker still running only prints the command', async () => {
  for (const o of [{ open: false }, { tty: false }, { free: false }])
    assert.deepEqual(await hangUp(o), { result: 'printed', steps: ['gone', 'rename', PRINT] }, JSON.stringify(o))
})

test('a refused or failed hand-over prints the command', async () => {
  for (const code of [1, -1, null])
    assert.deepEqual(await hangUp({ code }), { result: 'printed', steps: ['gone', 'rename', `run --desktop --resume ${ID} in /p`, PRINT] }, String(code))
})

test('a title that cannot be written does not stop the hand-over', async () => {
  assert.equal((await hangUp({ renameFails: true })).result, 'opened')
})

test('childrenGone waits until the server has no child processes, and gives up in time', async () => {
  const seen = [['11', '12'], ['12'], []], waits = []
  assert.equal(await childrenGone({ pid: 7, list: async pid => { assert.equal(pid, 7); return seen.shift() }, wait: async ms => { waits.push(ms) } }), true)
  assert.deepEqual(waits, [150, 150])
  waits.length = 0
  assert.equal(await childrenGone({ list: async () => ['11'], wait: async ms => { waits.push(ms) }, tries: 4 }), false)
  assert.equal(waits.length, 4)
})

test('childrenGone sees a real child process', async () => {
  const kid = spawn(process.execPath, ['-e', 'setTimeout(() => {}, 60000)']) // long enough for PowerShell, which takes seconds to start on Windows
  assert.equal(await childrenGone({ tries: 1, wait: async () => {} }), false)
  kid.kill()
  await new Promise(r => kid.once('exit', r))
  assert.equal(await childrenGone({ tries: 1, wait: async () => {} }), true)
})

test('handOverAll hands every worker with a session over in turn, each from its own folder, and skips the rest', async () => {
  const steps = [], A = 'aaaa-1', B = 'bbbb-2', C = 'cccc-3'
  const s = (id, cwd) => ({ id, cwd, rename: async () => steps.push(`rename ${id}`) })
  const codes = { [A]: 0, [B]: 1, [C]: 0 } // B's hand-over is refused: it prints, and the next one still goes
  const results = await handOverAll([s(A, '/api'), s(null, '/web'), s(B, '/api'), s(C, '/docs')], {
    open: true, tty: true,
    run: async (args, cwd) => { steps.push(`run ${args.at(-1)} in ${cwd}`); return codes[args.at(-1)] },
    gone: async () => { steps.push('gone'); return true },
    log: line => steps.push(`log ${line}`),
  })
  assert.deepEqual(results, ['opened', 'none', 'printed', 'opened'])
  assert.deepEqual(steps, [
    'gone', `rename ${A}`, `run ${A} in /api`,
    'gone', `rename ${B}`, `run ${B} in /api`, `log To open this call in the Claude app:  ${command(B, '/api')}`,
    'gone', `rename ${C}`, `run ${C} in /docs`,
  ])
  assert.deepEqual(await handOverAll([], { open: true, tty: true }), [])
})

test('lendTerminal gives the CLI a terminal when the server has none, and passes its exit code back', { skip: process.platform === 'win32' && 'Windows has no script: the CLI runs as it is' }, async () => {
  assert.equal(await lendTerminal(['-c', 'test -t 0 && test -t 1'], '/', '/bin/sh'), 0)
  assert.equal(await lendTerminal(['-c', 'exit 3'], '/', '/bin/sh'), 3)
})

test('Open in Claude: the title first, then the session opens once the worker\'s process lets go of it', async () => {
  const steps = [], said = ['\x1b[2mSession abc is open in another terminal. Run /desktop there instead.\x1b[0m\r\n', 'Session abc is open in another terminal.', 'Opening session abc in Claude Desktop']
  const r = await openOne({ id: 'abc', cwd: '/w', rename: async () => { steps.push('rename') }, wait: async () => steps.push('wait'),
    run: async (args, cwd) => { steps.push(`run ${args.join(' ')} in ${cwd}`); const out = said.shift(); return { code: said.length ? 1 : 0, out } } })
  assert.deepEqual(r, { ok: true })
  assert.deepEqual(steps, ['rename', 'run --desktop --resume abc in /w', 'wait', 'run --desktop --resume abc in /w', 'wait', 'run --desktop --resume abc in /w'])
})

test('Open in Claude: any other refusal is final and says why in the CLI\'s own words; a session held too long gives up', async () => {
  const once = await openOne({ id: 'abc', cwd: '/w', rename: async () => { throw new Error('no') }, wait: async () => {}, run: async () => ({ code: 1, out: 'some text\nNo conversation found with session ID: abc\n' }) })
  assert.deepEqual(once, { ok: false, why: 'No conversation found with session ID: abc' })
  let n = 0
  const held = await openOne({ id: 'abc', cwd: '/w', rename: async () => {}, wait: async () => {}, tries: 3, run: async () => (n++, { code: 1, out: 'Session abc is open in another terminal.' }) })
  assert.deepEqual([held.ok, n], [false, 3])
})
