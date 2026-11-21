// AppChecks, the program that drives the app's code for the checks (--replay, --file), where `swift build` puts it. build.sh builds it
// just before it runs check.mjs; a missing build fails loudly here, never against a stale copy.
import { execFileSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '../..')
export const APP = path.join(execFileSync('swift', ['build', '--show-bin-path'], { cwd: ROOT, encoding: 'utf8' }).trim(), 'AppChecks')
export function built() { if (!existsSync(APP)) throw new Error(`No AppChecks at ${APP}: run ./build.sh (or swift build --product AppChecks) first`); return APP }
