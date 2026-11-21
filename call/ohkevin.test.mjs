// `npx ohkevin` (ohkevin.mjs): the SDK pin matches package-lock.json, and sdk.mjs is taken only when its sha512 is the pinned one.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { SDK, ensureSDK, prepare } from './ohkevin.mjs'

const HERE = path.dirname(fileURLToPath(import.meta.url))

test('the pinned Agent SDK is package-lock.json\'s own', () => {
  const lock = JSON.parse(readFileSync(path.join(HERE, 'package-lock.json'), 'utf8')).packages['node_modules/@anthropic-ai/claude-agent-sdk']
  assert.deepEqual([lock.version, lock.integrity, lock.resolved], [SDK.version, SDK.integrity, SDK.url])
})

test('sdk.mjs and its package files come from the tarball only when its sha512 is the pinned one', async t => {
  const root = mkdtempSync(path.join(tmpdir(), 'ohkevin-test-')); t.after(() => rmSync(root, { recursive: true, force: true }))
  const pkg = path.join(root, 'src/package'); mkdirSync(pkg, { recursive: true })
  for (const [name, text] of [['sdk.mjs', 'export const query = 1'], ['package.json', '{}'], ['LICENSE.md', 'terms'], ['README.md', 'readme'], ['cli.js', 'not taken']]) writeFileSync(path.join(pkg, name), text)
  execFileSync('tar', ['-czf', path.join(root, 'sdk.tgz'), '-C', path.join(root, 'src'), 'package'])
  const tgz = readFileSync(path.join(root, 'sdk.tgz')), get = async () => tgz
  const pin = { ...SDK, integrity: 'sha512-' + createHash('sha512').update(tgz).digest('base64') }
  const folder = path.join(root, 'call'), sdk = path.join(folder, 'node_modules/@anthropic-ai/claude-agent-sdk')

  await assert.rejects(ensureSDK(folder, { ...pin, integrity: 'sha512-wrong' }, get), /not the expected file/)
  assert.equal(existsSync(sdk), false)
  assert.equal(await ensureSDK(folder, pin, get), 'fetched')
  assert.equal(readFileSync(path.join(sdk, 'sdk.mjs'), 'utf8'), 'export const query = 1')
  assert.equal(existsSync(path.join(sdk, 'cli.js')), false) // only what the server needs, and the terms
  assert.equal(await ensureSDK(folder, pin, async () => { throw new Error('no second download') }), 'there')
})

test('the call runs from its own folder, or from a copy in Oh Kevin\'s folder when its own cannot be written', { skip: process.platform === 'win32' && 'Windows ignores a folder\'s read-only mode' }, async t => {
  const root = mkdtempSync(path.join(tmpdir(), 'ohkevin-prepare-')); t.after(() => { chmodSync(path.join(root, 'locked'), 0o755); rmSync(root, { recursive: true, force: true }) })
  const pkg = path.join(root, 'src/package'); mkdirSync(pkg, { recursive: true })
  for (const name of ['sdk.mjs', 'package.json', 'LICENSE.md', 'README.md']) writeFileSync(path.join(pkg, name), name)
  execFileSync('tar', ['-czf', path.join(root, 'sdk.tgz'), '-C', path.join(root, 'src'), 'package'])
  const tgz = readFileSync(path.join(root, 'sdk.tgz')), get = async () => tgz
  const pin = { ...SDK, integrity: 'sha512-' + createHash('sha512').update(tgz).digest('base64') }
  const open = path.join(root, 'open'), locked = path.join(root, 'locked'), data = path.join(root, 'data')
  for (const dir of [open, locked]) { mkdirSync(dir); writeFileSync(path.join(dir, 'server.mjs'), '// the server') }
  chmodSync(locked, 0o555)
  assert.equal(await prepare({ here: open, data, pin, get }), open)
  assert.equal(await prepare({ here: locked, data, pin, get }), data)
  assert.ok(existsSync(path.join(data, 'server.mjs')) && existsSync(path.join(data, 'node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs')))
})
