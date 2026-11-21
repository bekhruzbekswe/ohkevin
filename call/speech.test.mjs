import { test } from 'node:test'
import assert from 'node:assert/strict'
import { Splitter } from './speech.mjs'

const whole = text => { const s = new Splitter(); return [...s.feed(text), ...s.flush()] }
const byChar = text => { const s = new Splitter(); return [...[...text].flatMap(c => s.feed(c)), ...s.flush()] }

test('speech then a task line', () => {
  const want = [{ say: 'On it.' }, { cmd: 'do', arg: 'check why the login test is flaky' }]
  const text = 'On it.\n>>> do: check why the login test is flaky\n'
  assert.deepEqual(whole(text), want)
  assert.deepEqual(byChar(text), want) // same result however the stream is chopped
})

test('sentences come out one at a time, last one on flush', () => {
  const s = new Splitter()
  assert.deepEqual(s.feed('Hello there. How are'), [{ say: 'Hello there.' }])
  assert.deepEqual(s.feed(' you'), [])
  assert.deepEqual(s.flush(), [{ say: 'How are you' }])
})

test('stop line with no trailing newline', () => {
  assert.deepEqual(byChar('Stopping now.\n>>> stop'), [{ say: 'Stopping now.' }, { cmd: 'stop', arg: '' }])
})

test('markdown is not spoken', () => {
  assert.deepEqual(whole('**Sure** thing, `auth.ts` it is.'), [{ say: 'Sure thing, auth.ts it is.' }])
})

test('>>> in the middle of a line is just speech', () => {
  assert.deepEqual(whole('Use >>> to shift bits.\n'), [{ say: 'Use >>> to shift bits.' }])
})

test('decimals do not split a sentence', () => {
  assert.deepEqual(whole('It took 3.5 seconds.'), [{ say: 'It took 3.5 seconds.' }])
})

test('do without a note, plus topic and model lines', () => {
  assert.deepEqual(whole('On it.\n>>> topic: Flaky login test\n>>> do\n'), [{ say: 'On it.' }, { cmd: 'topic', arg: 'Flaky login test' }, { cmd: 'do', arg: '' }])
  assert.deepEqual(byChar('Switching.\n>>> model: fable'), [{ say: 'Switching.' }, { cmd: 'model', arg: 'fable' }])
})

test('a control line on the same line as speech still counts', () => {
  const want = [{ say: 'Making the file now.' }, { cmd: 'do', arg: '' }]
  assert.deepEqual(whole('Making the file now. >>> do '), want)
  assert.deepEqual(byChar('Making the file now. >>> do '), want)
  assert.deepEqual(byChar('On it >>> topic: Notes file\n>>> do: the file is notes.txt'), [{ say: 'On it' }, { cmd: 'topic', arg: 'Notes file' }, { cmd: 'do', arg: 'the file is notes.txt' }])
})

test('a wait line alone, or after a word or two', () => {
  assert.deepEqual(whole('>>> wait'), [{ cmd: 'wait', arg: '' }])
  assert.deepEqual(byChar('>>> wait\n'), [{ cmd: 'wait', arg: '' }])
  assert.deepEqual(byChar('Go on. >>> wait'), [{ say: 'Go on.' }, { cmd: 'wait', arg: '' }])
})

test('two control lines written on one line are both acted on', () => {
  assert.deepEqual(whole('Checking.\n>>> topic: Flaky login test >>> do\n'), [{ say: 'Checking.' }, { cmd: 'topic', arg: 'Flaky login test' }, { cmd: 'do', arg: '' }])
  assert.deepEqual(byChar('>>> topic: Notes >>> do: the file is notes.txt'), [{ cmd: 'topic', arg: 'Notes' }, { cmd: 'do', arg: 'the file is notes.txt' }])
  assert.deepEqual(whole('>>> do: fix the test >>> topic: Fix the test >>> model: opus\nOn it.'), [{ cmd: 'do', arg: 'fix the test' }, { cmd: 'topic', arg: 'Fix the test' }, { cmd: 'model', arg: 'opus' }, { say: 'On it.' }])
})

test('open lines, and a worker named on do, stop, model and topic lines', () => {
  assert.deepEqual(byChar('Opening web.\n>>> open: web\n'), [{ say: 'Opening web.' }, { cmd: 'open', arg: 'web' }])
  assert.deepEqual(whole('On it.\n>>> topic web: Login page >>> do web: the login page\n>>> stop api\n>>> model api two: sonnet'),
    [{ say: 'On it.' }, { cmd: 'topic', arg: 'web: Login page' }, { cmd: 'do', arg: 'web: the login page' }, { cmd: 'stop', arg: 'api' }, { cmd: 'model', arg: 'api two: sonnet' }])
  assert.deepEqual(whole('Asking web. >>> do web'), [{ say: 'Asking web.' }, { cmd: 'do', arg: 'web' }])
  assert.deepEqual(whole('I will open it later.'), [{ say: 'I will open it later.' }])
})
