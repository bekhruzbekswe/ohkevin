#!/usr/bin/env node
// `npx ohkevin`: a voice call with Claude Code about the folder you are in (or the one named), in Chrome.
//   npx ohkevin [project-folder]
// The call server needs one file of Anthropic's Agent SDK, sdk.mjs. A checkout has it from `npm ci`; otherwise it is fetched
// once from npm (the pinned version, its sha512 checked) into this package's own node_modules: never the SDK's 331 MB copy of
// Claude Code, because the call uses yours. Where that folder cannot be written (a read-only npx cache), the call's files are
// copied to Oh Kevin's own folder (platform.mjs, dataDir) and run from there. Tested by ohkevin.test.mjs.
import { createHash } from 'node:crypto'
import { accessSync, constants, cpSync, existsSync, mkdirSync, readdirSync, realpathSync, renameSync, rmSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { gunzipSync } from 'node:zlib'
import { dataDir } from './platform.mjs'
import { look, problems } from './preflight.mjs'

const HERE = path.dirname(fileURLToPath(import.meta.url))
// The pin: package-lock.json's own entry for the SDK (a test keeps them equal).
export const SDK = {
  version: '0.3.325',
  integrity: 'sha512-MhSm2Fhk3DA/hhjdCKXDZWlnykpPWJjX42SogllAHMplY9ZKT+Ltb8QPtQxpe225Imfs4A8IKaNE4biivA+fHg==',
  url: 'https://registry.npmjs.org/@anthropic-ai/claude-agent-sdk/-/claude-agent-sdk-0.3.325.tgz',
}
const SDK_FILE = 'node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs'
const KEEP = ['package/sdk.mjs', 'package/package.json', 'package/LICENSE.md', 'package/README.md'] // the code, how Node finds it, the terms

/// The named files of a .tgz, as { name: Buffer }. A tar file is 512-byte blocks: a header (name, octal size), then the data.
export function untar(tgz, names) {
  const tar = gunzipSync(tgz), out = {}
  for (let at = 0; at + 512 <= tar.length;) {
    const field = (from, len) => tar.subarray(at + from, at + from + len).toString('utf8').replace(/\0.*$/s, '')
    const name = field(0, 100); if (!name) break
    const size = parseInt(field(124, 12).trim() || '0', 8), full = (field(345, 155) ? field(345, 155) + '/' : '') + name
    if (names.includes(full)) out[full] = tar.subarray(at + 512, at + 512 + size)
    at += 512 + Math.ceil(size / 512) * 512
  }
  return out
}

/// Puts sdk.mjs and its package.json, licence and readme into folder's node_modules, unless they are there. Throws, in plain
/// words, when the download fails or is not the pinned one.
export async function ensureSDK(folder = HERE, pin = SDK, get = url => fetch(url).then(r => { if (!r.ok) throw new Error(`npm answered ${r.status}`); return r.arrayBuffer() })) {
  const to = path.join(folder, 'node_modules/@anthropic-ai/claude-agent-sdk')
  if (existsSync(path.join(folder, SDK_FILE))) return 'there'
  const tgz = Buffer.from(await get(pin.url))
  if ('sha512-' + createHash('sha512').update(tgz).digest('base64') !== pin.integrity) throw new Error('the Agent SDK downloaded from npm is not the expected file')
  const files = untar(tgz, KEEP), fresh = to + '.new'
  if (Object.keys(files).length !== KEEP.length) throw new Error('the Agent SDK package is missing files')
  rmSync(fresh, { recursive: true, force: true }); mkdirSync(fresh, { recursive: true })
  for (const [name, data] of Object.entries(files)) writeFileSync(path.join(fresh, path.basename(name)), data)
  rmSync(to, { recursive: true, force: true }); renameSync(fresh, to) // in place whole, never half
  return 'fetched'
}

/// The folder the call runs from: this package's own, or, when it cannot be written (a read-only npx cache), a copy of its files
/// in Oh Kevin's folder. Either way with the SDK in place.
export async function prepare({ here = HERE, data = path.join(dataDir(), 'npx', SDK.version), pin = SDK, get } = {}) {
  const writable = dir => { try { accessSync(dir, constants.W_OK); return true } catch { return false } }
  if (existsSync(path.join(here, SDK_FILE)) || writable(here)) { await ensureSDK(here, pin, get); return here }
  mkdirSync(data, { recursive: true })
  for (const name of readdirSync(here)) if (name !== 'node_modules') cpSync(path.join(here, name), path.join(data, name), { recursive: true })
  await ensureSDK(data, pin, get)
  return data
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) { // run (npx runs it through a link), not imported by a test
  const missing = problems(look()) // first what this computer still needs (preflight.mjs)
  if (missing.length) {
    console.error(`Before a call, ${missing.length === 1 ? 'one thing' : `${missing.length} things`} to fix:\n` + missing.map(m => `  ${m.what}\n    ${m.fix}`).join('\n'))
    process.exit(1)
  }
  let from
  try { from = await prepare() }
  catch (e) { console.error(`Could not get Anthropic's Agent SDK: ${e.message}. Check the internet connection and try again.`); process.exit(1) }
  process.argv[2] = path.resolve(process.argv[2] ?? process.cwd()) // the folder you are in, unless you named one
  await import(pathToFileURL(path.join(from, 'server.mjs')).href)
}
