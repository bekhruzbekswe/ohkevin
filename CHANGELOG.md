# Changelog

What changed for people using Oh Kevin, newest first. Each release's section is its tag message and its release notes
(AGENTS.md, Releases).

## Unreleased

### Added
- Settings has what a call needs: what a spoken "yes" approves, opening the work in Claude afterwards, opening at login, and a
  Privacy page that says what leaves your Mac.
- The menu bar shows a starting call too: "Connecting… The voice is warming up.", as the window does.

### Changed
- Settings is one card in two groups, Calls and This Mac, each choice on its own row.
- Oh Kevin's folders are called "Oh Kevin" now; the old ones move there by themselves.
- The Agent SDK is downloaded at first run (1.6 MB, checked against a pinned hash) instead of coming inside the app.
- The older Python voice is no longer used: Oh Kevin downloads its own voice once (381 MB).
- The sound for a problem in a call is Oh Kevin's own.
- Updates and the download come from the latest release on GitHub, which lists SHA256SUMS for its files.

## Browser 0.1 — 2026-11-22

### Added
- `npx ohkevin` starts a voice call with Claude Code about the folder you are in (or the one you name), in Chrome.
- Before the call starts it checks Node, Claude Code (installed, recent enough, signed in) and Chrome, and says how to fix
  what is missing.
- It runs on macOS, Linux and Windows, with your own Claude Code and account; the call stays on your computer.
- It downloads one file of Anthropic's Agent SDK once, checked against a pinned hash, never a copy of Claude Code.
- Your speech becomes text through Chrome's speech recognition, which sends it to Google.

## Launcher 0.6 — 2026-11-21

### Added
- One setup window on first launch: sign in to Claude, allow the microphone, choose a project, in any order.
- The first call opens on "Say hello." and Kevin answers that it hears you.
- The first finished worker card shows, once, that pressing a card opens its work in Claude.

### Changed
- The local voice runs without Python: the same voice, a smaller download (381 MB) and a faster start.
- Node and the call's parts download by themselves at launch, with no button to press.

## Mac app 0.3 — 2026-11-21

### Added
- Works on any Mac: the app carries its own call server and keeps its own copy of it, so it no longer needs the folder it was
  built from.
- One setup window on first launch, the same as the launcher's: sign in to Claude, allow the microphone and speech recognition
  (asked together, so the first call asks nothing), choose a project, in any order.
- What a call needs downloads by itself at launch, behind one bar: Node, the local voice and, if it is missing, Apple's English
  speech model.
- The first call opens on "Say hello." and Kevin answers that it hears you; the first finished worker card shows, once, that
  pressing a card opens its work in Claude.

### Changed
- The local voice runs without Python: the app carries the voice's runner and downloads only its model and voices (381 MB).
- A smaller first download: only Node's program (27.5 MB); the call server's parts come inside the app.
- When the voice, Node or the speech model is missing, the message says what to do in plain words.
