<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="design/logo/lockup-dark.png">
    <img alt="Oh Kevin" src="design/logo/lockup-light.png" height="64">
  </picture>
</p>

Talk to Claude Code. A voice call from your Mac's menu bar: you speak, a fast voice answers, and Claude Code does the
work in your project.

*Oh Kevin is an independent project that works with Claude Code. It is not made by or affiliated with Anthropic.*

## What you need

- A Mac with Apple silicon, macOS 14 or later
- [Claude Code](https://claude.com/claude-code), installed and signed in (the app helps with both)
- Google Chrome: the call listens through Chrome's speech recognition

The app fetches everything else it needs on first run.

## Install

1. [Download the app](https://github.com/bekhruzbekswe/ohkevin/releases/latest/download/Oh-Kevin-Launcher.dmg) and move it to Applications.
2. Open it. The app is signed with Oh Kevin's own certificate, not notarized by Apple, so macOS blocks the first open:
   go to **System Settings › Privacy & Security**, find the line about Oh Kevin and click **Open Anyway**.
3. One setup window opens with three rows, in any order: **Claude** (sign in, in your browser), **Microphone** (allow it)
   and **Project** (the folder Claude Code works in). Meanwhile Node downloads by itself, checked against pinned
   checksums.
4. **Start the first call**.

To build it yourself instead: `cd launcher && ./build.sh --open` (needs only the Command Line Tools,
`xcode-select --install`).

## Your first call

1. The call window opens on "Say hello." Say it; Kevin answers, and asks what to do first.
2. Talk. Pause when you are done; the voice answers. Ask for real work ("fix the failing login test") and Claude Code
   starts on it while you keep talking. Say "how's it going?" any time.
3. Each piece of work shows as a card at the side of the call window. Press a card to open it: **Open in Claude**
   moves that worker to the Claude app, **Stop** stops it, and a finished one has **Close**; asked again, a fresh worker
   starts. If Claude Code asks about a step (rare in auto mode, see below), say "yes" or press Approve on its card;
   "no" always denies.
4. **End** in the call window, or the red button in the menu-bar panel. The call's work can open in the Claude app
   afterwards.

## A better voice (optional)

Calls speak with Chrome's built-in voice, a British male one when Chrome has it. For a natural voice that runs on
your Mac: **Settings › Speaks with › Download** in the menu-bar app (a 381 MB download, 365 MB on disk, a few
minutes). Nothing to install by hand. It speaks as Fable, a British male voice; the three dots at the top right of the
call window choose another.

## What leaves your Mac, and what runs without asking

- Chrome sends your speech to Google to become text.
- Your words, and the files Claude Code reads, go to Anthropic, under your own Claude Code account.
- Claude Code works in auto mode: it edits files, runs commands and uses the network without asking. Its own safety
  checks refuse what they judge dangerous; they don't ask you. You are asked only when your own Claude Code settings
  say so (an "ask" rule, or a tool that needs approval).
- A spoken "yes" can approve edits, new files, and git add, commit and new branches in the project. Everything else
  needs a click. Settings changes this to "any step" or "nothing".

## Settings

| Setting | What it does |
|---|---|
| Claude Code model | Opus, Sonnet, Haiku or Fable for the work. The voice itself always runs on Haiku. |
| A spoken "yes" approves | Safe steps (default), any step, or nothing. |
| Open the work in the Claude app afterwards | When a call ends, its Claude Code sessions open in the Claude app. |
| Speaks with | Which voice speaks. **Download** gets the voice on this Mac. |
| Open at login | Starts the menu-bar app when you log in. |

## When something goes wrong

- **You can't see its icon in the menu bar.** On a full menu bar macOS hides icons behind the notch, and
  System Settings › Menu Bar can switch them off. Open the app again (Spotlight works): its panel opens at the right
  end of the menu bar.
- **The call can't hear you.** The panel says why: its window was closed (**Show the call**), or the microphone is
  blocked by macOS or by Chrome (**Allow microphone** opens the right setting).
- **The call broke.** Oh Kevin starts it again by itself, once, and the same window comes back ("Reconnecting", then
  listening). The voice starts fresh and the workers stopped; their work so far is saved in Claude Code. If it breaks
  again, the panel says "Call lost": press **Call again** there.
- **Anything else.** When a call fails, the panel says so in one line; **Show Details** opens the log
  (`~/Library/Logs/Claude Voice/call.log`).

## Uninstall

Quit it from the ⋯ menu, delete the app, then remove `~/Library/Application Support/Claude Voice` (Node, the packages,
the voice and the call window's Chrome profile), `~/Library/Logs/Claude Voice`, and the app's settings in
`~/Library/Preferences` (the file named after the app's bundle id).

## Without the menu-bar app

The call server also runs from a terminal, with Node 18.14 or later and npm:

```sh
cd call && npm ci
node server.mjs ~/path/to/your/project
```

It prints a link and opens it in Chrome. Ctrl-C ends the call.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
