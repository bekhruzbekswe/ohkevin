import test from 'node:test'
import assert from 'node:assert/strict'
import { record, summary, line } from './stats.mjs'

test('empty list gives zeros and no median', () => {
  assert.deepEqual(summary([]), { turns: 0, medianDelay: null, slowest: 0, joined: 0, waited: 0, pausedForNothing: 0, cutOffs: 0 })
})

test('median of odd and even counts, and the counters', () => {
  const list = []
  for (const e of [{ kind: 'reply', delay: 5.1 }, { kind: 'reply', delay: 1 }, { kind: 'joined' }, { kind: 'nothing' }, { kind: 'nothing' }, { kind: 'cut' }, { kind: 'waited' }]) record(list, e)
  assert.deepEqual(summary(list), { turns: 2, medianDelay: 3.05, slowest: 5.1, joined: 1, waited: 1, pausedForNothing: 2, cutOffs: 1 })
  record(list, { kind: 'reply', delay: 2.4 })
  assert.equal(summary(list).medianDelay, 2.4)
})

test('line reads as one sentence', () => {
  const list = [{ kind: 'reply', delay: 2.4 }, { kind: 'reply', delay: 1 }, { kind: 'reply', delay: 5.1 }, { kind: 'nothing' }, { kind: 'nothing' }, { kind: 'cut' }, { kind: 'joined' }]
  assert.equal(line(summary(list)), '3 replies, median 2.4 s, slowest 5.1 s, joined 1, waited 0, paused for nothing 2, cut off 1')
  assert.match(line(summary([])), /^0 replies, median -/)
})
