# Oh Kevin, in the browser

A voice call with [Claude Code](https://claude.com/claude-code). Tell Kevin what you need, and he runs Claude Code jobs in
your project while you keep talking.

```sh
npx ohkevin              # a call about the folder you are in
npx ohkevin ~/code/api   # or about another one
```

It opens the call in Chrome. Allow the microphone, and say hello.

## What it needs

- **Node 18.14** or later.
- **Claude Code**, installed and signed in. Kevin works through your own account.
- **Google Chrome** (Chromium on Linux). The call uses its speech recognition.

If something is missing, `npx ohkevin` says what and how to fix it before it starts.

## What leaves your computer

| What | Where it goes |
|---|---|
| Your speech | Google, through Chrome's speech recognition, to become text. |
| Your words, and the files Claude Code reads | Anthropic, under your own Claude Code account. |

The call runs on your computer, at `127.0.0.1`. There is no account and no server of ours. On a Mac, the
[Mac app](https://github.com/bekhruzbekswe/ohkevin#readme) keeps your speech on the Mac instead.

Claude Code works in auto mode: it edits files, runs commands and uses the network without asking; its own safety checks
refuse what they judge dangerous. A spoken "yes" approves only safe steps; everything else needs a click.

---

Source, issues and the Mac app: [github.com/bekhruzbekswe/ohkevin](https://github.com/bekhruzbekswe/ohkevin). Apache 2.0.
Oh Kevin is an independent project that works with Claude Code. It is not made by or affiliated with Anthropic.
