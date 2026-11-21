// Every repository path cited in a Markdown file or a code comment must exist: from the repository root, from the
// citing file's folder, or from its package (the nearest folder above it with a Package.swift or package.json) and its
// Sources, or from the shared launcher/Sources. A path whose first folder is none of these is not this repository's.
//   node check-paths.mjs        (check.sh runs it; prints each miss and exits 1)
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import path from 'node:path'

const files = execFileSync('git', ['ls-files'], { encoding: 'utf8' }).split('\n').filter(Boolean)
const code = /\.(swift|mjs|js|sh|py|html|css)$/
const ext = 'md|mjs|js|swift|sh|html|css|json|py|txt|plist|entitlements|png|mp3|icns|tiff'
// a cited path: at least one slash, made of path characters, ending in a known extension or a slash
const cite = new RegExp(`(?<![\\w./~$:@-])((?:\\.{1,2}/)?[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_. -]*[A-Za-z0-9_-])*?/[A-Za-z0-9_.-]+\\.(?:${ext})|(?:\\.{1,2}/)?[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+/)(?![\\w/])`, 'g')
const comment = { swift: /\/\/(.*)$/, mjs: /\/\/(.*)$/, js: /\/\/(.*)$/, css: /\/\*(.*?)(\*\/|$)/, sh: /(?:^|\s)#(.*)$/, py: /(?:^|\s)#(.*)$/, html: /<!--(.*?)(-->|$)|\/\/(.*)$/ }

function pkg(dir) {
  for (let d = dir; d && d !== '.'; d = path.dirname(d)) if (existsSync(path.join(d, 'Package.swift')) || existsSync(path.join(d, 'package.json'))) return d
  return null
}
const found = p => existsSync(p) || existsSync(p.replace(/\/$/, ''))
const misses = []
for (const file of files) {
  const kind = file.endsWith('.md') ? 'md' : code.test(file) ? file.split('.').pop() : null
  if (!kind || file.includes('node_modules/') || !existsSync(file)) continue
  const dir = path.dirname(file), base = pkg(dir)
  readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
    let text = line
    if (kind !== 'md') { const m = line.match(comment[kind]); if (!m) return; text = m.slice(1).filter(Boolean).join(' ') }
    for (const [, p] of text.matchAll(cite)) {
      if (/^(https?|www)\b|\.(com|org|io|net)\//.test(p) || /[<>*{}$]/.test(p)) continue
      if (p.length > 120 || /^\.?\.\/[^/]+$|^\.\.\.\//.test(p)) continue // data, or a file beside a `cd` in the text
      if (p.split('/').some(s => ['build', 'releases', 'results', '.build', '.background'].includes(s))) continue // made by a build
      const bases = ['.', dir, base, base && path.join(base, 'Sources'), 'launcher/Sources'].filter(Boolean)
      const head = p.replace(/^(\.\.?\/)+/, '').split('/')[0]
      if (!/^\.\.?\//.test(p) && !bases.some(b => existsSync(path.join(b, head)))) continue // not a path in this repository
      if (bases.some(b => found(path.join(b, p)))) continue
      misses.push(`${file}:${i + 1}: ${p}`)
    }
  })
}
if (misses.length) { console.error(`Paths cited that do not exist (${misses.length}):\n${misses.join('\n')}`); process.exit(1) }
console.log('Every cited path exists.')
