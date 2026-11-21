import { test } from 'node:test'
import assert from 'node:assert/strict'
import path from 'node:path'
import { words, voiceOk, askLine, spokenAnswer, answerAloud } from './approve.mjs'

// A pretend project at /p: /p/link is a symlink to /elsewhere, and /p/README.md and /p/dangling exist.
const AT = {
  path: path.posix, // the pretend project's paths are POSIX on every system
  project: '/p',
  real: p => (p === '/p/link' || p.startsWith('/p/link/') ? p.replace('/p/link', '/elsewhere') : p),
  exists: p => ['/p/README.md', '/p/dangling', '/p/src'].includes(p),
}
const ok = (tool, input) => voiceOk(tool, input, AT)
const bash = command => ok('Bash', { command })

test('words splits plain commands and keeps quoted text whole', () => {
  assert.deepEqual(words('git commit -m "fix the tests"'), ['git', 'commit', '-m', 'fix the tests'])
  assert.deepEqual(words("touch 'a b.txt'"), ['touch', 'a b.txt'])
  assert.deepEqual(words("grep 'a|b;c $x' f"), ['grep', 'a|b;c $x', 'f']) // nothing expands in single quotes
  assert.deepEqual(words('  mkdir   -p  src/lib '), ['mkdir', '-p', 'src/lib'])
  assert.deepEqual(words('git commit -m ""'), ['git', 'commit', '-m', ''])
})

test('words refuses anything but plain words', () => {
  for (const c of ['ls; rm -rf x', 'a && b', 'a || b', 'a | b', 'echo hi > f', 'echo hi >> f', 'cat < f', 'echo $(whoami)', 'echo `id`',
    'echo $HOME', 'touch ${X}', 'ls *.js', 'ls ?', 'ls [ab]', 'ls ~', 'cat ~/.ssh/id_rsa', 'cat a\\ b', 'echo "$HOME"', 'echo "a\\"b"',
    'echo "`id`"', 'echo "hi!"', 'sleep 1 &', '(cd x)', '{ ls; }', 'echo hi # c', 'ls\nrm x', 'echo "open', "echo 'open", 'echo !!',
    'touch é.txt', '', '   '])
    assert.equal(words(c), null, c)
  for (const c of [undefined, null, 42, {}]) assert.equal(words(c), null)
})

test('voice may approve edits and new files inside the project', () => {
  for (const [tool, input] of [
    ['Edit', { file_path: '/p/src/a.js' }], ['Edit', { file_path: 'src/a.js' }], ['Edit', { file_path: '/p/notes.md' }],
    ['NotebookEdit', { notebook_path: '/p/n.ipynb' }], ['Write', { file_path: '/p/new.txt' }], ['Write', { file_path: '/p/src/new/deep.js' }],
  ]) assert.ok(ok(tool, input), `${tool} ${JSON.stringify(input)}`)
})

test('edits and writes that need the click', () => {
  for (const [tool, input] of [
    ['Edit', { file_path: '/etc/hosts' }], ['Edit', { file_path: '/p/../x' }], ['Edit', { file_path: '../x' }], ['Edit', { file_path: '/pother/a.js' }],
    ['Edit', { file_path: '/p/.env' }], ['Edit', { file_path: '/p/.env.local' }], ['Edit', { file_path: '/p/.git/config' }],
    ['Edit', { file_path: '/p/.github/workflows/ci.yml' }], ['Edit', { file_path: '/p/src/.hidden' }], ['Edit', { file_path: '/p/.claude/settings.json' }],
    ['Edit', { file_path: '/p/config/secrets.json' }], ['Edit', { file_path: '/p/certs/server.pem' }], ['Edit', { file_path: '/p/server.key' }],
    ['Edit', { file_path: '/p/id_rsa' }], ['Edit', { file_path: '/p/api_token.txt' }], ['Edit', { file_path: '/p/credentials.yml' }],
    ['Edit', { file_path: '/p/passwords.txt' }], ['Edit', { file_path: '/p/link/a.js' }], ['Edit', { file_path: '/p/link' }],
    ['Edit', {}], ['Edit', { file_path: 42 }], ['Edit', { file_path: '' }], ['Edit', null], ['NotebookEdit', { file_path: '/p/n.ipynb' }],
    ['Write', { file_path: '/p/README.md' }], ['Write', { file_path: '/p/dangling' }], ['Write', { file_path: '/tmp/x.txt' }],
    ['Write', { file_path: '/p/.zshrc' }], ['Write', { file_path: '/p/link/new.txt' }], ['Write', {}],
  ]) assert.ok(!ok(tool, input), `${tool} ${JSON.stringify(input)}`)
})

test('voice may approve the short list of shell commands', () => {
  for (const c of ['mkdir docs', 'mkdir -p src/lib', 'mkdir -p a b', 'touch notes.txt', 'touch a.txt src/b.txt', "touch 'my notes.txt'",
    'git add .', 'git add -A', 'git add --all', 'git add -u', 'git add src/a.js README.md', 'git add ./src',
    'git commit -m "fix: tests"', 'git commit -am wip', 'git commit -a -m x', 'git commit --all -m "x y"', 'git commit -m ""',
    'git switch -c feat/x', 'git checkout -b fix-1'])
    assert.ok(bash(c), c)
})

test('every other shell command needs the click', () => {
  for (const c of ['rm a.txt', 'rm -rf build', 'rmdir docs', 'mv a b', 'cp a b', 'ln -s /etc x', 'chmod +x a', 'sed -i s/a/b/ f',
    'echo hi > a.txt', 'touch a; rm b', 'cd src && touch a', 'touch $(whoami)', 'touch *.txt', 'sudo touch a', 'FOO=1 touch a',
    'mkdir', 'mkdir -p', 'mkdir /tmp/x', 'mkdir ../x', 'mkdir -m 777 x', 'mkdir .github', 'touch', 'touch -t 202001010000 a',
    'touch .bashrc', 'touch ../x', 'touch /tmp/x', 'touch link/x', 'touch secrets.txt',
    'git push', 'git push --force origin main', 'git push -f', 'git reset --hard', 'git reset --soft HEAD~1', 'git rebase -i main',
    'git commit', 'git commit -m', 'git commit -a', 'git commit --amend -m x', 'git commit --no-verify -m x', 'git commit -m x --amend',
    'git checkout file.txt', 'git checkout -- .', 'git checkout main', 'git checkout -b a b', 'git checkout -b', 'git switch main',
    'git switch -c', 'git switch -c -x', 'git switch -c "a b"', 'git restore .', 'git clean -fd', 'git branch -D x', 'git stash drop',
    'git -C /tmp add .', 'git -c core.hooksPath=/tmp commit -m x', 'git add', 'git add ../x', 'git add /etc/passwd', 'git add .env',
    'git add -p', 'git add -f x', 'git status', 'git', 'npm install', 'npm i left-pad', 'npm test', 'npm run test', 'node --test',
    'pip install x', 'npx something', 'curl https://example.com', 'wget x', 'ssh host', 'scp a host:', 'make', 'unknown-cmd', 'ls', ''])
    assert.ok(!bash(c), c)
  assert.ok(!ok('Bash', {}))
  assert.ok(!ok('Bash', { command: 42 }))
})

test('every other tool needs the click', () => {
  for (const tool of ['Read', 'Glob', 'Grep', 'WebFetch', 'WebSearch', 'Agent', 'Task', 'Skill', 'ExitPlanMode', 'MultiEdit',
    'mcp__linear__save_issue', 'mcp__fs__write_file', '', undefined])
    assert.ok(!ok(tool, { file_path: '/p/a.js', command: 'touch a' }), String(tool))
})

test('askLine: one short sentence, a question only when a spoken yes counts', () => {
  assert.equal(askLine('Edit', { file_path: '/p/src/a.js' }, true), 'It wants to edit a.js. Should it go ahead?')
  assert.equal(askLine('Write', { file_path: '/p/new.txt' }, true), 'It wants to write new.txt. Should it go ahead?')
  assert.equal(askLine('Bash', { command: 'git commit -m "x"' }, true), 'It wants to run git commit. Should it go ahead?')
  assert.equal(askLine('Bash', { command: 'git push --force origin main' }, false), 'It wants to run git push, and that needs a click on screen.')
  assert.equal(askLine('Bash', { command: 'git -C /x push' }, false), 'It wants to run git, and that needs a click on screen.')
  assert.equal(askLine('Bash', { command: 'rm -rf build' }, false), 'It wants to run rm, and that needs a click on screen.')
  assert.equal(askLine('Bash', { command: '/usr/bin/curl -s x' }, false), 'It wants to run curl, and that needs a click on screen.')
  assert.equal(askLine('Bash', { command: 'cd x && rm -rf y' }, false), 'It wants to run a shell command, and that needs a click on screen.')
  assert.equal(askLine('Edit', {}, false), 'It wants to edit a file, and that needs a click on screen.')
  assert.equal(askLine('mcp__linear__save_issue', {}, false), 'It wants to use linear save issue, and that needs a click on screen.')
  assert.equal(askLine('WebFetch', { url: 'https://x' }, false), 'It wants to fetch a web page, and that needs a click on screen.')
  assert.equal(askLine('WebSearch', { query: 'x' }, false), 'It wants to search the web, and that needs a click on screen.')
  for (const voice of [true, false]) assert.equal(spokenAnswer(askLine('Bash', { command: 'git push' }, voice)), null) // its own echo is no answer
})

test('spokenAnswer: a short direct yes', () => {
  for (const t of ['yes', 'Yes.', 'yeah', 'Yep!', 'yup', 'sure', 'go ahead', 'Go ahead.', 'do it', 'go for it', 'approve', 'approve it',
    'approved', 'allow it', 'yes please', 'Yes, go ahead.', 'yeah go ahead please', 'okay go ahead', 'OK, do it.', 'sure, approve it', 'YES',
    'Just go ahead', 'please go ahead', 'just do it', 'go ahead then', 'Yes, just do it please.', 'do it now', 'proceed', 'go on', 'alright, do that', 'okay thanks go ahead'])
    assert.equal(spokenAnswer(t), 'yes', t)
})

test('spokenAnswer: no, don\'t and stop always refuse, even next to a yes', () => {
  for (const t of ['no', 'No.', 'nope', 'nah', "don't", 'dont', 'do not', 'Don’t do that.', 'stop', 'Stop!', 'please stop', 'cancel',
    'cancel that', 'deny', 'decline', 'yes no', 'yeah no', 'no yes', 'no problem, go ahead', 'I said no', "Don't, wait.",
    'why does it need to stop the server']) // a refusal word anywhere refuses: the safe side
    assert.equal(spokenAnswer(t), 'no', t)
})

test('spokenAnswer: anything longer or unclear is no answer', () => {
  for (const t of ['okay', 'ok', 'fine', 'alright', 'mhm', 'uh huh', 'yes yes', 'yes sir', 'sure thing', 'yes and also run the tests',
    'I think so', 'maybe', 'what does it want', 'yesterday', 'know', 'nobody', 'nothing', 'stopwatch', 'wait', 'hold on', 'not now',
    'just', 'please', 'now', 'thanks', 'just wait', 'go', 'go ahead and run the tests', '', '   ', '...'])
    assert.equal(spokenAnswer(t), null, t)
})

test('answerAloud', () => {
  const a = { id: 'a', voice: true }, b = { id: 'b', voice: true }, c = { id: 'c', voice: false }
  assert.deepEqual(answerAloud('yes', [], 'a'), { act: 'none' })
  assert.deepEqual(answerAloud('no', [], ''), { act: 'none' })
  assert.deepEqual(answerAloud('what is it', [a], 'a'), { act: 'none' })
  assert.deepEqual(answerAloud('yes but wait', [a], 'a'), { act: 'none' })
  assert.deepEqual(answerAloud('yes', [a], 'a'), { act: 'allow', id: 'a' })
  assert.deepEqual(answerAloud('Go ahead.', [a], 'a'), { act: 'allow', id: 'a' })
  assert.deepEqual(answerAloud('yes', [a], ''), { act: 'again', id: 'a' }) // before the question finished, over the voice, or typed
  assert.deepEqual(answerAloud('yes', [a], 'old'), { act: 'again', id: 'a' })
  assert.deepEqual(answerAloud('yes', [c], 'c'), { act: 'click' })
  assert.deepEqual(answerAloud('yes', [a, b], 'a'), { act: 'click' })
  assert.deepEqual(answerAloud('no', [a, c], ''), { act: 'deny', ids: ['a', 'c'] })
  assert.deepEqual(answerAloud('stop', [c], 'c'), { act: 'deny', ids: ['c'] })
})
