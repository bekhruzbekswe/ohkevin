# Oh Kevin, the Mac app (Track B)

The call as a native Mac app: a window of its own (SwiftUI in AppKit), Apple's speech recogniser for the ears, one audio
engine with voice processing for the microphone and the voice, and the same call server as today's page. The design is in
`design/` (`spec.md`, `mockups.html`). Needs macOS 26 and the Command Line Tools; no Xcode.

## Build and run

```sh
cd call && npm ci                 # once: the call server's packages
cd ../app && ./build.sh           # "build/Oh Kevin.app", ad-hoc signed; ends with the equality checks
open "build/Oh Kevin.app"           # Start Call: it starts its own call server, then listens
open "build/Oh Kevin.app" --args --log /abs/path/call.jsonl   # also write the call's log (below)
```

- The app is called **Oh Kevin** (short form Kevin; `Product.name` in VoiceCore's `Product.swift`, read by `build.sh`).
  Licensed under the Apache License 2.0 (`LICENSE`, `NOTICE` at the repository's root). It finds the call server in the repository it was built from (`build.sh` writes the folder
  into Info.plist), so build it again if the repository moves.
- macOS asks for the microphone and speech recognition on first use, and again after each rebuild (ad-hoc signing).
- Nothing is written about a call unless asked: `--log <file>` writes every word heard, sent and said (JSON lines, the
  shape `Tests/measure/hook.js` records from the page). Its own server's output goes to
  `~/Library/Logs/Claude Voice/native-<time>.log` (owner-only; the last three are kept).
- `--call <link>` uses a running call server instead of starting one.

## Updates

The app updates itself the way the launcher does (Sparkle 2, the launcher's own updater code linked into `Sources/Updating`), only when built
with a feed: `FEED_URL=<appcast> ./build.sh`. It checks daily, downloads by itself unless "Update automatically" is off in Settings, and
installs by relaunching only when no call is on and nothing is in use; "Check for Updates…" is in the app menu. Its feed and files are its
own (`appcast-app.xml`, `Oh-Kevin-App-<version>.zip`), never the launcher's.

```sh
SIGN_ID="Oh Kevin" ./release.sh 0.2          # builds, signs, zips into releases/v0.2/ with appcast-app.xml; publishes nothing
SIGN_ID="Oh Kevin" ./rehearse-update.sh      # 0.1 → 0.2 on this Mac, and whether the microphone permission survives (with the owner)
```

## Layout

| Target | What it is |
|---|---|
| `Ears` | the page's listening and speaking code, ported one for one (`Turns.swift` is `call/voice.mjs`, `Ears.swift` is `call/ears.mjs`; same names). No Apple audio: `Replay` runs it on any recorded call. |
| `CallKit` | what the window shows (approvals, workers, banners, hand-over), no screen in it, on the same `Turns`. |
| `VoiceApp` | the app: window and views, `Call` (the call's wiring and log), `Sound` (the engine), `Recognizer`, `Server`. |
| `VoiceCore` | the launcher's shared core, linked from `launcher/`. |

Everything runs on the main queue; the audio thread only copies samples into a ring.

## Test and measure

```sh
swift test                                   # ears.test.mjs case for case, every helper against the JavaScript, the call window's model
node Tests/measure/check.mjs                       # every recorded call replayed through the Swift rules: the same /say and /hush (build.sh runs it)
node Tests/measure/differ.mjs [seeds]              # call/voice.mjs and the Swift rules on the same events: logs, the hand-written cases, 300 generated calls (check.mjs runs it)
node Tests/measure/trial.mjs Tests/recordings/<log>.jsonl   # a live call's log, measured as the recorded ones are
node Tests/measure/live.mjs                        # the Chrome side of a trial: today's page, logged in the same shape
"build/Oh Kevin.app/Contents/MacOS/Oh Kevin" --check <folder>          # draws every state of the design, light and dark, to PNGs
"build/Oh Kevin.app/Contents/MacOS/Oh Kevin" --engine-check <file>     # the audio engine, output muted: formats, samples, mute, stop, close
"build/Oh Kevin.app/Contents/MacOS/Oh Kevin" --replay <log.jsonl>      # what the turn-taking would post and play on a recorded call (- : calls on stdin)
VoiceApp --file <wav> --call <link> --log <out>                      # a measurement: a WAV in place of the microphone, nothing played
node Tests/measure/run.mjs                       # ~10 min: today's page against the app on seven lines, raw logs in Tests/recordings/
```

`Tests/recordings/` holds the recordings and one whole recorded call (`recorded-call-1.jsonl`; the words said in it are made up).
`Tests/measure/differ.mjs` lists, in one place, what the differential check leaves out and why,
and the real differences it found (each with its smallest case in `Tests/measure/diff-cases/`).

## Not known

- Echo cancelling, hearing you over the voice and false pauses can only be judged in a room (the owner's trial).
- Whether the menu-bar microphone indicator goes off on mute (the engine stays on, voice processing sends silence).
- `SpeechTranscriber`'s English model is not installed by default: the window offers the download, or
  `VoiceApp --install-model`. Without it the app uses `DictationTranscriber`.
- No Settings window yet: the voice is remembered, nothing else is configurable.
