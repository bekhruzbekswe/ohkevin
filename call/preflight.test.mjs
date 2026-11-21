// What a computer needs before a call (preflight.mjs): each problem, and its fix.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { atLeast, problems } from './preflight.mjs'

const ready = { node: 'v22.12.0', claude: '/usr/local/bin/claude', version: '2.1.330 (Claude Code)', signedIn: true, chrome: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' }

test('versions compare part by part', () => {
  assert.ok(atLeast('v18.14.0', '18.14.0') && atLeast('v24.1.0', '18.14.0') && !atLeast('v18.9.1', '18.14.0'))
  assert.ok(atLeast('2.1.323 (Claude Code)', '2.1.323') && !atLeast('2.1.99', '2.1.323') && atLeast('2.2', '2.1.323'))
})

test('a ready computer has no problems', () => assert.deepEqual(problems(ready), []))

test('each missing piece says what is wrong and how to fix it', () => {
  const what = c => problems({ ...ready, ...c }).map(p => [p.what, p.fix])
  assert.deepEqual(what({ node: 'v16.20.0' }), [['Node v16.20.0 is too old: a call needs 18.14.0 or later.', 'Install the current Node from https://nodejs.org, then run npx ohkevin again.']])
  assert.match(what({ claude: undefined, version: null, signedIn: null })[0][0], /Claude Code is not installed/)
  assert.deepEqual(what({ version: '2.0.5 (Claude Code)' }), [['Claude Code 2.0.5 is too old: a call needs 2.1.323 or later.', 'Run: claude update']])
  assert.deepEqual(what({ signedIn: false }), [['Claude Code is not signed in.', 'Run: claude auth login']])
  assert.match(what({ chrome: null })[0][1], /google.com\/chrome/)
  assert.equal(problems({ ...ready, version: null, signedIn: null }).length, 0) // a Claude Code that cannot say is given the benefit of the doubt
  assert.equal(problems({ node: 'v16.0.0', claude: undefined, version: null, signedIn: null, chrome: null }).length, 3) // all at once, in order
})
