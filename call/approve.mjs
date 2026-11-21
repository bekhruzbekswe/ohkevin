// Approving by voice: which steps a spoken yes may approve, and what a spoken answer means.
// Pure: the server passes in the project's real path and two small file-system lookups. Tested by approve.test.mjs.
import path from 'node:path'

// The words of a plain shell command, or null when it holds anything else: operators, redirection, substitution,
// variables, globs, ~, escapes. Quotes are fine when nothing in them expands.
export function words(command) {
  if (typeof command !== 'string') return null
  const out = []
  let word = null
  for (let i = 0; i < command.length; i++) {
    const c = command[i]
    if (c === ' ' || c === '\t') { if (word !== null) out.push(word); word = null }
    else if (c === "'" || c === '"') {
      const end = command.indexOf(c, i + 1)
      if (end < 0) return null
      const inner = command.slice(i + 1, end)
      if (c === '"' && /[$`\\!]/.test(inner)) return null
      word = (word ?? '') + inner; i = end
    }
    else if (/[\w.,/:@%+=-]/.test(c)) word = (word ?? '') + c
    else return null
  }
  if (word !== null) out.push(word)
  return out.length ? out : null
}

const SECRET = /secret|credential|passw|token|\.pem$|\.key$|\.p12$|\.pfx$|^id_(rsa|dsa|ecdsa|ed25519)/i
// Inside the project after symlinks, with no hidden part (.git, .env, .github, ..) and nothing that looks like a secret.
function inside(p, { project, real }) {
  if (typeof p !== 'string' || !p) return false
  const rel = path.relative(project, real(path.resolve(project, p)))
  return !path.isAbsolute(rel) && rel.split(path.sep).every(part => !part.startsWith('.') && !SECRET.test(part))
}

const BRANCH = /^[\w./-]+$/
function bashOk(w, at) {
  if (!w) return false
  const [cmd, sub, ...rest] = w
  const paths = list => list.length > 0 && list.every(a => !a.startsWith('-') && inside(a, at))
  if (cmd === 'touch') return paths(w.slice(1))
  if (cmd === 'mkdir') return paths(w.slice(1).filter(a => a !== '-p'))
  if (cmd !== 'git') return false
  if (sub === 'add') return rest.length > 0 && rest.every(a => ['-A', '--all', '-u', '--update'].includes(a) || paths([a]))
  if (sub === 'commit') {
    let message = false
    for (let i = 0; i < rest.length; i++) {
      if (rest[i] === '-m' || rest[i] === '-am') { if (++i >= rest.length) return false; message = true }
      else if (rest[i] !== '-a' && rest[i] !== '--all') return false
    }
    return message // without one, git opens an editor and waits
  }
  if ((sub === 'switch' && rest[0] === '-c') || (sub === 'checkout' && rest[0] === '-b')) return rest.length === 2 && BRANCH.test(rest[1]) && !rest[1].startsWith('-')
  return false
}

// May a spoken yes approve this step? Only the short list of recoverable steps inside the project; anything else needs the click.
// at: { project: the project's real path, real(p): p's real path through symlinks, exists(p): is anything at p (lstat) }
export function voiceOk(tool, input, at) {
  if (!input || typeof input !== 'object') return false
  if (tool === 'Edit') return inside(input.file_path, at)
  if (tool === 'NotebookEdit') return inside(input.notebook_path, at)
  if (tool === 'Write') return inside(input.file_path, at) && !at.exists(path.resolve(at.project, input.file_path)) // a new file only: overwriting may not be undoable
  if (tool === 'Bash') return bashOk(words(input.command), at)
  return false
}

const base = p => (typeof p === 'string' && p.split('/').filter(Boolean).at(-1)) || 'a file'
const NAMED = new Set(['git', 'npm', 'pnpm', 'yarn', 'npx', 'pip', 'brew', 'docker', 'kubectl', 'gh', 'cargo', 'go'])
export function stepWords(tool, input = {}) {
  if (tool === 'Edit') return `edit ${base(input.file_path)}`
  if (tool === 'NotebookEdit') return `edit ${base(input.notebook_path)}`
  if (tool === 'Write') return `write ${base(input.file_path)}`
  if (tool === 'Bash') {
    const w = words(input.command)
    if (!w) return 'run a shell command'
    const cmd = base(w[0])
    return `run ${cmd}${NAMED.has(cmd) && w[1] && !w[1].startsWith('-') ? ` ${w[1]}` : ''}`
  }
  if (tool === 'WebFetch') return 'fetch a web page'
  if (tool === 'WebSearch') return 'search the web'
  return `use ${String(tool).replace(/^mcp__/, '').replace(/__|_/g, ' ')}`
}
// The one sentence the voice says about a step. It holds no "no": an echo of the voice must not read as an answer.
export const askLine = (tool, input, voice) =>
  voice ? `It wants to ${stepWords(tool, input)}. Should it go ahead?` : `It wants to ${stepWords(tool, input)}, and that needs a click on screen.`

const DENY = new Set(['no', 'nope', 'nah', "don't", 'dont', 'stop', 'cancel', 'deny', 'decline'])
const LEAD = ['yes', 'yeah', 'yep', 'yup', 'sure', 'okay', 'ok', 'alright'] // a lone okay, ok or alright is not a yes
const GO = ['go ahead', 'do it', 'do that', 'go for it', 'go on', 'proceed', 'carry on', 'approve', 'approve it', 'approved', 'allow it']
const YES = new Set([...LEAD.slice(0, 5), ...GO, ...LEAD.flatMap(l => GO.map(g => `${l} ${g}`))])
const FILLER = new Set(['just', 'please', 'then', 'now', 'thanks']) // "just go ahead", "do it then, thanks"
const tokens = text => String(text).toLowerCase().replace(/[‘’]/g, "'").split(/\s+/).map(w => w.replace(/[^\p{L}\p{N}']/gu, '')).filter(Boolean)

// 'no' when any refusal word is in it, 'yes' only for a short direct yes, otherwise null.
export function spokenAnswer(text) {
  const w = tokens(text)
  if (w.some((x, i) => DENY.has(x) || (x === 'do' && w[i + 1] === 'not'))) return 'no'
  return YES.has(w.filter(x => !FILLER.has(x)).join(' ')) ? 'yes' : null
}

// What a spoken answer does to the open approvals.
// open: [{ id, voice }]; heard: the approval whose question had finished playing before these words began, else ''.
export function answerAloud(text, open, heard) {
  const said = open.length ? spokenAnswer(text) : null
  if (said === 'no') return { act: 'deny', ids: open.map(a => a.id) }
  if (said !== 'yes') return { act: 'none' }
  const [only] = open
  if (open.length > 1 || !only.voice) return { act: 'click' }
  return heard === only.id ? { act: 'allow', id: only.id } : { act: 'again', id: only.id }
}
