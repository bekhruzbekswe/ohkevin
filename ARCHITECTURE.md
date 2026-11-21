# Architecture

## Bird's-eye view

Oh Kevin is a voice call with Claude Code. You talk; a fast voice (Claude Code on Haiku) answers and hands real work to
Claude Code workers in your project; they run while you keep talking.

One call is one Node process, the call server (`call/server.mjs`). Everything else is a client of it:

```
launcher (menu bar, Swift) ──starts──▶ call server (Node) ──Agent SDK──▶ the user's own claude (voice + workers)
      │  /events?watch=1                    ▲  /events, /say, /permit, /stop, /mic …
      └──opens──▶ call page (call/index.html in its own Chrome): ears and mouth
Mac app (Swift) ──starts──▶ the same call server, with its own native ears and mouth instead of the page
```

The server knows nothing about who listens: the page and the Mac app both speak its HTTP routes and server-sent
events. The local voice (Kokoro) is a separate program the server starts, `kokoro-runner`; without it the page uses
Chrome's voice.

## Code map

### `call/`: the call server and the call page

- `server.mjs`: one call. The voice turn by turn, workers, approvals, usage-limit warnings, the hand-over to the Claude
  app. Routes and events are listed in its request handler.
- Small modules beside it, each with its test: `approve.mjs` (what a spoken yes may approve), `workers.mjs`,
  `limits.mjs`, `handover.mjs`, `speech.mjs` (splitting replies into sentences), `ears.mjs` (when a turn ends),
  `claude-path.mjs` (which `claude` runs).
- `voice.mjs`: listening and speaking for the page, given the browser's objects and a clock; no DOM.
- `index.html`: the call page, built on `voice.mjs`.
- `tts.py`: the older Python voice, used only when a voice folder has no `kokoro-runner`.

### `launcher/`: the menu-bar app (Swift package)

- `Sources/VoiceCore`: everything with no screen: settings, health checks, installs, the setup screen's model, the
  server's events in plain words, updates' state. Shared with the Mac app.
- `Sources/CallViews`: SwiftUI views in the design (panel, setup screen, Settings pieces). Shared.
- `Sources/Updating`: Sparkle and Move to Applications. Shared.
- `Sources/LauncherKit`: the menu-bar item, windows and wiring. `Sources/OhKevin`: its `main`.
- `Sources/kokoro-runner`: the local voice without Python (onnxruntime and espeak-ng loaded at run time). Both apps
  carry it in `Contents/Helpers`.
- `Sources/LauncherChecks`: checks that drive the real app and draw every state; never shipped.
- `build.sh`, `pack-call.sh` (puts `call/` inside an app), `release.sh`, `publish.sh`, `make-dmg.sh`.

### `app/`: the Mac app (Swift package)

- `Sources/Ears`: the page's turn-taking, ported one for one, with no audio in it.
- `Sources/CallKit`: what the call window shows, with no screen in it.
- `Sources/VoiceApp`: the app: Apple's recogniser, one audio engine, the call window.
- `Sources/VoiceCore`, `Sources/CallViews`, `Sources/Updating`: links to the launcher's folders, compiled again here.

### `design/`

The approved look: `system.css` (tokens), `final.html`, `onboarding.html`, `updates.html`, the logo and disk image art.

## Invariants

- The server's routes and events only grow. Nothing is renamed or removed: two clients depend on them.
- `call/voice.mjs` changes only to fix a real defect, never for speed, and every change passes
  `call/voice.replay.test.mjs`, which replays recorded calls on a handed clock. The Mac app's `Ears` is checked against it.
- `VoiceCore` has no screen: no AppKit or SwiftUI. What can be tested without a window lives there.
- Shared sources are edited in `launcher/` only; `app/` links to them.
- A test never reaches a model with a real task, never plays sound, and leaves nothing running.

## Cross-cutting concerns

- **Contract:** the page and the Mac app are two clients of one server; `./check.sh` builds and tests both.
- **Privacy:** speech becomes text in Chrome (Google) or Apple's recogniser; words go to Anthropic under the user's own
  Claude Code. Nothing passes through us. Logs are written only when asked.
- **Installs:** everything downloaded at run time is pinned by URL and sha256 (`VoiceCore/Install.swift`,
  `InstallRunner.swift`); a failed install leaves nothing half done.
- **Signing and updates:** apps are signed with the "Oh Kevin" certificate; Sparkle checks each update with the owner's
  EdDSA key. Release steps are in `AGENTS.md`.
- **Licences:** what ships and what is fetched at install is listed in `NOTICE`.
