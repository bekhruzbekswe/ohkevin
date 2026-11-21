// The built app's program, where build.sh puts it: build/<name>.app/Contents/MacOS/<name>, the name read from the one place it
// lives (VoiceCore's Product.swift), as build.sh reads it. A missing build fails loudly here, never against a stale copy.
import { existsSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '../..')
const name = /static let name = "(.*)"/.exec(readFileSync(path.join(ROOT, 'Sources/VoiceCore/Product.swift'), 'utf8'))?.[1]
if (!name) throw new Error('No Product.name in Sources/VoiceCore/Product.swift')
export const APP = path.join(ROOT, 'build', `${name}.app`, 'Contents', 'MacOS', name)
export function built() { if (!existsSync(APP)) throw new Error(`No built app at ${APP}: run ./build.sh first`); return APP }
