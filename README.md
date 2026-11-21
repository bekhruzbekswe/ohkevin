<picture><source media="(prefers-color-scheme: dark)" srcset="media/lockup-dark.png"><img alt="Oh Kevin" src="media/lockup-light.png" height="64"></picture>

**Kevin is a voice you call on your Mac.** Tell him what you need, and he runs several Claude Code jobs at once while you keep working.

<a href="https://github.com/bekhruzbekswe/ohkevin/releases/download/app-feed/Oh-Kevin-App.dmg"><img alt="Download Oh Kevin for Mac" src="media/download.png" width="264"></a>

<br>

<picture><source media="(prefers-color-scheme: dark)" srcset="media/oh-kevin-loop-dark.webp"><img alt="A silent loop of one call in the Oh Kevin window: you ask for the tests to be run, Kevin opens a worker, two more workers start, one asks to push your commits, you say yes, and all three finish" src="media/oh-kevin-loop-light.webp"></picture>

## How it works

### 1. Say what you want done

Start a call and talk. Kevin answers at once and gives the job to its own Claude Code session, shown as a card.

<picture><source media="(prefers-color-scheme: dark)" srcset="media/mac-say-dark.png"><img alt="The Oh Kevin window at the start of a call: you asked for the tests to be run, Kevin said On it, and a worker card, api, is running the tests" src="media/mac-say-light.png"></picture>

### 2. Hand out more, and keep working

Each job gets its own worker. Ask how one is doing, open it in Claude, or stop it.

<picture><source media="(prefers-color-scheme: dark)" srcset="media/mac-work-dark.png"><img alt="The Oh Kevin window with the conversation on the left and three worker cards on the right, api, web and docs, all working; web is open and shows Open in Claude and Stop" src="media/mac-work-light.png"></picture>

### 3. Answer when Kevin needs you

Say "yes" for safe steps, or click **Approve**.

<picture><source media="(prefers-color-scheme: dark)" srcset="media/mac-ask-dark.png"><img alt="The Oh Kevin window: the worker web asks to push your commits, with Deny and Approve buttons, while api and docs keep working" src="media/mac-ask-light.png"></picture>

## Install

### macOS (Apple silicon, macOS 26)

1. **Open it, and click Open Anyway.** [Download](https://github.com/bekhruzbekswe/ohkevin/releases/download/app-feed/Oh-Kevin-App.dmg), drag Oh Kevin to Applications and open it. macOS blocks the first open because Oh Kevin is not signed by Apple; the code is open, here. Go to **System Settings › Privacy & Security**, scroll to Security and click **Open Anyway**. Only once; updates install by themselves.

   <picture><source media="(prefers-color-scheme: dark)" srcset="media/open-anyway-dark.png"><img alt="System Settings, Privacy and Security: Oh Kevin was blocked to protect your Mac, with an Open Anyway button" src="media/open-anyway-light.png" width="560"></picture>
2. **Set up.** One window, three things: sign in to **Claude**, allow the **Microphone**, choose a **Project**. Kevin works through [Claude Code](https://claude.com/claude-code); if you don't have it yet, Oh Kevin helps you get it. It then downloads what a call needs, about 410 MB, most of it the voice (381 MB), and Apple's speech model if your Mac doesn't have it yet.
3. **Start the first call** and say hello. Kevin understands English for now.

### Other computers

A browser page for every other computer is coming soon.

## What leaves your Mac

No account, no server of ours, no tracking.

| What | Where it goes |
|---|---|
| Your speech | Nowhere. Apple's speech recognition turns it into text on your Mac. |
| Your words, and the files Claude Code reads | Anthropic, under your own Claude Code account |
| An update check | GitHub, where the releases are |

### What Claude Code may do

- **It works in auto mode:** it edits files, runs commands and uses the network without asking.
- **Its own safety checks** refuse what they judge dangerous.
- **A spoken "yes"** approves only edits, new files and git add, commit or new branch in the project. Everything else needs a click.

## When something goes wrong

- **You can't see its icon in the menu bar.** A full menu bar hides icons behind the notch. You don't need it: everything is in the Oh Kevin window.
- **The call can't hear you.** Oh Kevin says why; **Allow microphone** opens the right setting.
- **The call broke.** Oh Kevin reconnects by itself. If it can't, it says "Call lost": press **Call again**. Work so far is saved in Claude Code.
- **Anything else.** Oh Kevin says what failed in one line; **Show Log** in the ⋯ menu opens the log.

<details>
<summary>Voice</summary>

Kevin's voice is made on your Mac. It speaks as Fable, a British male voice; the three dots at the top right of the window choose another.
</details>

<details>
<summary>Settings</summary>

The three dots at the top right of the window:

| Setting | What it does |
|---|---|
| Project folder | The folder Claude Code works in. |
| Model | Opus, Sonnet, Haiku or Fable for the work. Kevin itself always runs on Haiku. |
| Voice | Which voice speaks. |
</details>

<details>
<summary>Uninstall</summary>

Quit Oh Kevin and delete the app. Then remove `~/Library/Application Support/Oh Kevin`, `~/Library/Logs/Oh Kevin`, and the app's file in `~/Library/Preferences`.
</details>

---

Build from source: [CONTRIBUTING.md](CONTRIBUTING.md) and [ARCHITECTURE.md](ARCHITECTURE.md). Licence: Apache 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE).

*Oh Kevin is an independent project that works with Claude Code. It is not made by or affiliated with Anthropic. It runs your own, unmodified Claude Code under your own account, and never sees or handles your sign-in.*
