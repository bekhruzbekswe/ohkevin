// The owner's live trial of today's call: the real Chrome (headed, real microphone and speakers, a throwaway profile),
// the call page watched by hook.js, every event logged as run.mjs logs a headless run. Leaves nothing behind.
//   node Tests/measure/live.mjs [--mute]      → Tests/recordings/trial-chrome-<time>.jsonl (+ .server.log); read it: node Tests/measure/trial.mjs <file>
// Talk until you close the window (or press Ctrl-C). --mute (for tests only) adds --mute-audio.
import { appendFileSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { openCall, startServer } from './rig.mjs'

const RESULTS = path.join(path.dirname(fileURLToPath(import.meta.url)), '../recordings')
const scratch = mkdtempSync(path.join(tmpdir(), 'live-')), stamp = new Date().toISOString().slice(0, 19).replace(/[-:]/g, '')
const file = path.join(RESULTS, `trial-chrome-${stamp}.jsonl`)
let stopNow
const asked = new Promise(r => (stopNow = r))
for (const sig of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(sig, stopNow)
let srv, page
try {
  console.log('Starting the call server (the voice takes a moment to warm up)...')
  srv = await startServer(scratch)
  writeFileSync(file, '')
  // --use-fake-ui-for-media-stream only skips the microphone question a fresh profile would ask; the microphone is the real one
  page = await openCall(path.join(scratch, 'chrome'), ['--use-fake-ui-for-media-stream', ...(process.argv.includes('--mute') ? ['--mute-audio'] : [])], o => appendFileSync(file, JSON.stringify(o).replaceAll(scratch, '<scratch>') + '\n'))
  console.log('Chrome is open: press Start call, talk, then close the window (or press Ctrl-C here).')
  await Promise.race([page.closed, asked])
} finally {
  await page?.kill()
  await srv?.stop(file.replace(/\.jsonl$/, '.server.log'))
  rmSync(scratch, { recursive: true, force: true })
  console.log(`Done. Log: ${file}`)
  process.exit() // a closed debugging socket can keep node waiting
}
