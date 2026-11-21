import { test } from 'node:test'
import assert from 'node:assert/strict'
import { userPart, cutText, isStopOnly, levelDb, Gate, stillOpen, joinTurn, unfinished, TUNE } from './ears.mjs'

const AIRED = 'Sure. I will run the login tests now, then report back.'

test('userPart drops the voice\'s own echo and keeps the developer\'s words', () => {
  assert.equal(userPart('run the login tests', AIRED), '')
  assert.equal(userPart('Run the login tests.', AIRED), '') // case and punctuation do not matter
  assert.equal(userPart('tests', AIRED), '')
  assert.equal(userPart('the login tests no wait use the other file', AIRED), 'no wait use the other file')
  assert.equal(userPart('the plan is wrong', AIRED), 'the plan is wrong') // one shared word is chance
  assert.equal(userPart('actually tell me a joke', AIRED), 'actually tell me a joke')
  assert.equal(userPart('stop', AIRED), 'stop')
  assert.equal(userPart('hello there', ''), 'hello there')
  assert.equal(userPart('', AIRED), '')
})

test('cutText keeps the played share of the words', () => {
  const s = 'one two three four'
  assert.equal(cutText(s, 0.5), 'one two')
  assert.equal(cutText(s, 0.74), 'one two')
  assert.equal(cutText(s, 1), s)
  assert.equal(cutText(s, 0), '')
  assert.equal(cutText(s, NaN), '')
  assert.equal(cutText(s, 3), s)
  assert.equal(cutText(s, -1), '')
})

test('isStopOnly', () => {
  for (const t of ['stop', 'Stop.', 'stop stop', 'hold on', 'Wait a second.', 'okay stop', 'quiet please', 'stop it']) assert.ok(isStopOnly(t), t)
  for (const t of ['stop the tests', 'wait, use the other file', 'okay', 'please', '', 'that is enough for today']) assert.ok(!isStopOnly(t), t)
})

test('levelDb', () => {
  assert.ok(levelDb(new Float32Array(1024)) <= -100)
  const sine = a => Float32Array.from({ length: 4800 }, (_, i) => a * Math.sin(2 * Math.PI * 440 * i / 48000))
  assert.ok(Math.abs(levelDb(sine(1)) - -3.01) < 0.1)
  assert.ok(Math.abs(levelDb(sine(0.1)) - -23.01) < 0.1)
})

test('Gate fires on a sustained level only, honours quiet windows, and learns from misses', () => {
  let g = new Gate()
  for (let t = 0; t <= 2000; t += 20) assert.equal(g.feed(-60, t), false) // a quiet room never fires
  g = new Gate()
  assert.equal(g.feed(-20, 0), false); assert.equal(g.feed(-20, 100), false); assert.equal(g.feed(-20, 120), true)
  g = new Gate() // a dip starts the count again
  g.feed(-20, 0); g.feed(-20, 60); g.feed(-60, 80); g.feed(-20, 100)
  assert.equal(g.feed(-20, 200), false); assert.equal(g.feed(-20, 220), true)
  g = new Gate()
  g.quiet(0, 300)
  for (let t = 0; t < 300; t += 20) assert.equal(g.feed(-20, t), false)
  assert.equal(g.feed(-20, 300), false); assert.equal(g.feed(-20, 420), true)
  g = new Gate()
  g.miss(); assert.equal(g.bar, TUNE.barDb + TUNE.stepDb)
  g.feed(-40, 0); assert.equal(g.feed(-40, 500), false)
  for (let i = 0; i < 10; i++) g.miss()
  assert.equal(g.bar, TUNE.capDb)
})

test('stillOpen: a turn takes more words until its answer starts playing', () => {
  assert.equal(stillOpen('', 0), false) // nothing said yet, or a typed turn
  assert.equal(stillOpen('sent', 0), true) // its answer has not started
  assert.equal(stillOpen('sent', TUNE.joinMs - 1), true)
  assert.equal(stillOpen('sent', TUNE.joinMs), false) // too long ago: a new turn, as before
  assert.equal(stillOpen('answering', 1000), false) // talking over its answer starts a new turn
  assert.equal(stillOpen('waiting', 60000), true) // the voice is waiting for the rest
})

test('joinTurn keeps every word, in order, except a bare stop', () => {
  assert.equal(joinTurn('check', 'the files in this project'), 'check the files in this project')
  assert.equal(joinTurn('tell me about closures and', 'how they use memory'), 'tell me about closures and how they use memory')
  assert.equal(joinTurn('what is a closure', 'stop'), '')
  assert.equal(joinTurn('what is a closure', 'stop using var'), 'what is a closure stop using var')
})

test('unfinished: only words that never end a finished sentence', () => {
  for (const t of ['tell me about closures and', 'check the', 'um', 'I want my', 'use this or']) assert.ok(unfinished(t), t)
  for (const t of ['check', 'what are you up to', 'I think so', 'what is that', 'tell me about closures', '']) assert.ok(!unfinished(t), t)
})

test('joinMs 0 switches joining off, but a waiting voice is still answered', () => {
  const was = TUNE.joinMs
  TUNE.joinMs = 0
  try {
    assert.equal(stillOpen('sent', 0), false)
    assert.equal(stillOpen('waiting', 0), true)
  } finally { TUNE.joinMs = was }
})
