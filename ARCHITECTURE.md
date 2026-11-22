# Architecture

## Bird's-eye view

Oh Kevin is a voice call with Claude Code. You talk; a fast voice (Claude Code on Haiku) answers and hands real work to
Claude Code workers in your project; they run while you keep talking.

One call is one Node process, the call server (`call/server.mjs`). Everything else is a client of it:

```
Mac app (Swift) ──starts──▶ call server (Node) ──Agent SDK──▶ the user's own claude (voice + workers)
   ears and mouth: Apple's recogniser,   ▲  /events, /say, /permit, /stop, /mic …
   one audio engine, the call window     │
call page (call/index.html, a browser) ──┘  the same routes: the reference the Mac app is checked against
```

The server knows nothing about who listens: the Mac app and the page both speak its HTTP routes and server-sent
events. The local voice (Kokoro) is a separate program the server starts, `kokoro-runner`; without it the page uses
the browser's voice.

## Code map

### `call/`: the call server and the call page

- `server.mjs`: one call. The voice turn by turn, workers, approvals, usage-limit warnings, the hand-over to the Claude
  app. Routes and events are listed in its request handler.
- Small modules beside it, each with its test: `approve.mjs` (what a spoken yes may approve), `workers.mjs`,
  `limits.mjs`, `handover.mjs`, `speech.mjs` (splitting replies into sentences), `ears.mjs` (when a turn ends),
  `claude-path.mjs` (which `claude` runs).
- `voice.mjs`: listening and speaking for the page, given the browser's objects and a clock; no DOM.
- `index.html`: the call page, built on `voice.mjs`.

### `app/`: the Mac app (Swift package)

- `Sources/VoiceCore`: everything with no screen: settings, health checks, installs, the setup screen's model, the
  server's events in plain words, updates' state.
- `Sources/CallViews`: SwiftUI views in the design (panel, setup screen, Settings pieces).
- `Sources/Updating`: Sparkle and Move to Applications.
- `Sources/kokoro-runner`: the local voice without Python (onnxruntime and espeak-ng loaded at run time), carried in
  `Contents/Helpers`.
- `Sources/Ears`: the page's turn-taking, ported one for one, with no audio in it.
- `Sources/CallKit`: what the call window shows, with no screen in it.
- `Sources/OhKevinKit`: the app's code: Apple's recogniser, one audio engine, the call window, the menu-bar panel.
- `Sources/OhKevin`: the app, all that ships. `Sources/AppChecks`: checks that drive the app's code; never shipped.
- `build.sh`, `pack-call.sh` (puts `call/` inside the app), `release.sh`, `publish.sh`, `make-dmg.sh`.

### `design/`

The approved look: `system.css` (tokens), `final.html`, `onboarding.html`, `updates.html`, the logo and disk image art.
The old launcher's every state, as pictures, is in the history: `git show c60690d --stat`.

## Invariants

- The server's routes and events only grow. Nothing is renamed or removed: the Mac app and the page depend on them.
- `call/voice.mjs` changes only to fix a real defect, never for speed, and every change passes
  `call/voice.replay.test.mjs`, which replays recorded calls on a handed clock. The Mac app's `Ears` is checked against it.
- `VoiceCore` has no screen: no AppKit or SwiftUI. What can be tested without a window lives there.
- A test never reaches a model with a real task, never plays sound, and leaves nothing running.

## Cross-cutting concerns

- **Contract:** the Mac app and the page are two clients of one server; `./check.sh` tests both.
- **Privacy:** speech becomes text in Chrome (Google) or Apple's recogniser; words go to Anthropic under the user's own
  Claude Code. Nothing passes through us. Logs are written only when asked.
- **Installs:** everything downloaded at run time is pinned by URL and sha256 (`VoiceCore/Install.swift`,
  `InstallRunner.swift`); a failed install leaves nothing half done.
- **Signing and updates:** apps are signed with the "Oh Kevin" certificate; Sparkle checks each update with the owner's
  EdDSA key. Release steps are in `AGENTS.md`.
- **Licences:** what ships and what is fetched at install is listed in `NOTICE`.
