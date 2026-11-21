// A headless Chrome for the page tests, ready when Chrome says so: it prints "DevTools listening on ws://…" once its debugging
// port is open, so the tests wait for that line, not for a file to appear within some deadline. A Chrome that exits first fails at
// once, with what it said. Then a page of the tests' own is opened through that port. Used by server.test.mjs and voice.replay.test.mjs.
import { spawn } from 'node:child_process'
import { findBrowser } from '../platform.mjs'

export const CHROME = process.env.CHROME_PATH ?? findBrowser()?.file ?? '' // Chrome, wherever this platform installs it (CHROME_PATH: another)

/// Starts Chrome with args (a profile, flags). Resolves { chrome, page }: the process and a new page's debugging WebSocket URL.
export function openChrome(args) {
  const chrome = spawn(CHROME, ['--headless=new', '--remote-debugging-port=0', '--no-first-run', ...args, 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] })
  return new Promise((resolve, reject) => {
    let said = '', found = false
    const exited = code => { chrome.stderr.unref(); reject(new Error(`Chrome exited (${code}) before opening its debugging port:\n${said}`)) }
    chrome.once('exit', exited)
    chrome.stderr.on('data', async d => {
      if (found) return // still read (unref'd), so Chrome never blocks on a full pipe
      said += d
      const port = said.match(/DevTools listening on ws:\/\/[^:]+:(\d+)\//)?.[1]
      if (!port) return
      found = true; chrome.off('exit', exited)
      chrome.stderr.unref() // Chrome's crash reporter and updater inherit this pipe and outlive Chrome: they must not keep the test alive
      try {
        const page = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json()
        resolve({ chrome, page: page.webSocketDebuggerUrl })
      } catch (e) { reject(e) }
    })
  })
}
