// The equality checks, run by build.sh on every build: the Swift turn-taking must do what call/ears.mjs and the page do.
// 1. swift test (ears.test.mjs case for case, ears.mjs's numbers read from the file, 305 inputs through both languages);
// 2. every recorded call in Tests/recordings/ replayed through the Swift rules: the same /say and /hush, in order, within 50 ms;
// 3. the differential check (differ.mjs): voice.mjs and the Swift rules on the same events, every output the same.
//   node Tests/measure/check.mjs        (after ./build.sh; exits 1 on any difference)
import { execFileSync } from 'node:child_process'
import { readdirSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { replay } from './measure.mjs'
import { differ, report } from './differ.mjs'
import { built } from './app.mjs'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '../..'), RESULTS = path.join(ROOT, 'Tests/recordings')
const APP = built()
const DRIFT_MS = 50 // timers in virtual time against a real call's; measured drift so far is 20 ms
let bad = 0
if (!process.argv.includes('--no-unit')) {
  try { execFileSync('swift', ['test'], { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] }); console.log('swift test: passed') }
  catch (e) { bad++; console.log('swift test: FAILED\n' + e.stdout + e.stderr) }
}
// the recorded lines (chrome-*, native-*) and the recorded calls: the page's or the app's own rules made these posts
const logs = readdirSync(RESULTS).filter(f => /^(chrome|native|native-own|recorded-call)-.*\.jsonl$/.test(f) && !f.includes('.silent.')).sort()
for (const f of logs) {
  const r = replay(path.join(RESULTS, f), APP), ok = r.same && r.drift <= DRIFT_MS
  if (!ok) bad++
  console.log(`${ok ? 'same' : 'DIFFERENT'}  ${f}  ${r.posts} posts${r.same ? `, ±${r.drift} ms` : `\n  want ${r.want.join('\n       ')}\n  got  ${r.got.join('\n       ')}`}`)
}
console.log(bad ? `${bad} check(s) failed` : `all ${logs.length} replays the same`)
if (!report(await differ(APP))) bad++
process.exit(bad ? 1 : 0)
