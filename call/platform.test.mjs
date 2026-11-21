// What differs between macOS, Windows and Linux (platform.mjs), every case on any machine.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { browsers, children, dataDir, findBrowser, resumeLine, withTerminal } from './platform.mjs'

test('Oh Kevin keeps its files where each platform expects them', () => {
  assert.equal(dataDir('darwin', {}, '/Users/me'), '/Users/me/Library/Application Support/Oh Kevin') // the Mac app's own folder
  assert.equal(dataDir('win32', { APPDATA: 'C:\\Users\\me\\AppData\\Roaming' }, 'C:\\Users\\me'), 'C:\\Users\\me\\AppData\\Roaming\\Oh Kevin')
  assert.equal(dataDir('linux', {}, '/home/me'), '/home/me/.local/share/oh-kevin')
  assert.equal(dataDir('linux', { XDG_DATA_HOME: '/data' }, '/home/me'), '/data/oh-kevin')
})

test('Chrome, found where each platform installs it', () => {
  const win = { ProgramFiles: 'C:\\Program Files', 'ProgramFiles(x86)': 'C:\\Program Files (x86)', LOCALAPPDATA: 'C:\\Users\\me\\AppData\\Local' }
  const at = file => f => f === file
  assert.equal(findBrowser('win32', win, '', at('C:\\Users\\me\\AppData\\Local\\Google\\Chrome\\Application\\chrome.exe'))?.name, 'Google Chrome')
  assert.equal(findBrowser('linux', { PATH: '/usr/bin:/snap/bin' }, '/home/me', at('/snap/bin/chromium'))?.file, '/snap/bin/chromium')
  assert.equal(findBrowser('darwin', {}, '/Users/me', at('/Users/me/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'))?.name, 'Google Chrome')
  assert.equal(findBrowser('linux', { PATH: '/usr/bin' }, '/home/me', () => false), undefined)
  assert.ok(browsers('darwin', {}, '/Users/me')[0].file.startsWith('/Applications/Google Chrome.app'))
})

test('the CLI gets a terminal of its own: script on macOS and Linux, none needed on Windows', () => {
  assert.deepEqual(withTerminal('claude', ['--desktop', '--resume', 'x'], 'darwin'), ['/usr/bin/script', ['-q', '/dev/null', 'claude', '--desktop', '--resume', 'x']])
  assert.deepEqual(withTerminal('/opt/my claude', ['--resume', "it's"], 'linux'), ['script', ['-q', '-e', '-c', `'/opt/my claude' '--resume' 'it'\\''s'`, '/dev/null']])
  assert.deepEqual(withTerminal('claude.cmd', ['--resume', 'x'], 'win32'), ['claude.cmd', ['--resume', 'x']])
})

test('the line that reopens a session, for each shell', () => {
  assert.equal(resumeLine('abc', "/Users/me/it's here", 'darwin'), `cd '/Users/me/it'\\''s here' && claude --desktop --resume abc`)
  assert.equal(resumeLine('abc', 'C:\\Code\\shop', 'win32'), 'cd /d "C:\\Code\\shop" && claude --desktop --resume abc')
  assert.equal(resumeLine('abc', undefined, 'linux'), 'claude --desktop --resume abc')
})

test('a process\'s children are listed on this machine', async () => {
  const kid = spawn(process.execPath, ['-e', 'setTimeout(() => {}, 3000)'])
  try { assert.ok((await children(process.pid)).includes(String(kid.pid))) } finally { kid.kill() }
})
