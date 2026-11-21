# Oh Kevin, the Mac app

The call as a native Mac app: a window of its own (SwiftUI in AppKit), Apple's speech recogniser for the ears, one audio
engine with voice processing for the microphone and the voice, and the same call server as the call page. The design
is in `design/` (`spec.md`, `mockups.html`). Needs macOS 26 and the Command Line Tools; no Xcode.

## Build and run

```sh
./build.sh                          # "build/Oh Kevin.app", ad-hoc signed; ends with the equality checks
open "build/Oh Kevin.app"           # the setup screen on first run, then Start call
open "build/Oh Kevin.app" --args --log /abs/path/call.jsonl   # also write the call's log (below)
```

- The app is called **Oh Kevin** (`Product.name` in VoiceCore's `Product.swift`, read by `build.sh`). Licensed under the
  Apache License 2.0 (`LICENSE`, `NOTICE` at the repository's root).
- It carries the call server's files (`Contents/Resources/call`, packed by `pack-call.sh`) and the voice runner
  (`Contents/Helpers/kokoro-runner`). At first run it copies the server to `~/Library/Application Support/Oh Kevin/Call-App`
  and downloads what a call needs behind one bar: Node, the Agent SDK, the local voice, Apple's speech model. `OH_KEVIN_CALL_FOLDER` (or the
  `DeveloperCallFolder` default) points it at a repository's `call/` instead; off unless set.
- macOS asks for the microphone and speech recognition on first use; an ad-hoc build asks again after each rebuild.
- Nothing is written about a call unless asked: `--log <file>` writes every word heard, sent and said (JSON lines, the shape
  `Tests/measure/hook.js` records from the page). The server's own output goes to `~/Library/Logs/Oh Kevin/native-<time>.log`
  (owner-only; the last three are kept). `--call <link>` uses a running call server instead of starting one.

## Updates and releases

The app updates itself (Sparkle 2, `Sources/Updating`), from its own fixed feed `app-feed` (`appcast-app.xml`). Releases
follow the repository's `AGENTS.md`: `release.sh` builds, signs, zips and writes
the feed from the main checkout; `publish.sh` uploads, only on the owner's go. `rehearse-update.sh` tries an update on this Mac and
asks the installed app `--permissions` before and after.

## Layout

| Target | What it is |
|---|---|
| `Ears` | the page's listening and speaking code, ported one for one (`Turns.swift` is `call/voice.mjs`, `Ears.swift` is `call/ears.mjs`). No Apple audio: `Replay` runs it on any recorded call. |
| `CallKit` | what the window shows (approvals, workers, banners, hand-over), no screen in it, on the same `Turns`. |
| `OhKevinKit` | the app's code: window and views, setup and download, `Call` (the call's wiring and log), `Sound` (the engine), `Recognizer`, `Server`. |
| `OhKevin` | the app itself: one line, `runApp()`. All that ships. |
| `AppChecks` | the checks and measurements that drive the app's code; never shipped (below). |
| `VoiceCore` | everything with no screen: settings, health, installs, the setup model, the server's events in plain words. |
| `CallViews`, `Updating` | the panel, setup and Settings views; Sparkle updates and Move to Applications. |
| `kokoro-runner` | the local voice without Python, carried in `Contents/Helpers`. |

Everything runs on the main queue; the audio thread only copies samples into a ring.

## Test and measure

```sh
swift test                                        # ears.test.mjs case for case, every helper against the JavaScript, the window's model
node Tests/measure/check.mjs                      # every recording replayed through the Swift rules, then the differential (build.sh runs it)
node Tests/measure/differ.mjs [seeds]             # call/voice.mjs and the Swift rules on the same events: recordings, hand-written cases, generated calls
node Tests/measure/trial.mjs <log.jsonl>          # a live call's log, measured as the recordings are
node Tests/measure/live.mjs                       # the Chrome side of a trial: the page, logged in the same shape
node Tests/measure/run.mjs                        # ~10 min: the page against the app on seven spoken lines, new recordings in Tests/recordings
```

AppChecks (`swift build --product AppChecks`, then `"$(swift build --show-bin-path)/AppChecks" …`):

```sh
--check <folder> [--scene <link>]                 # every state of the design, light and dark, drawn offscreen to PNGs
--replay <log.jsonl>                              # what the turn-taking would post and play on a recorded call (- : calls on stdin)
--file <wav> --call <link> --log <out>            # a measurement: a WAV in place of the microphone, nothing played
--engine-check <file>                             # the live audio engine, output muted: formats, samples, mute, stop, close
--check-call <project> --app "build/Oh Kevin.app" # a built app's setup and call server, headless (--no-spotlight, --wav <file>)
--install-model                                   # Apple's newer English speech model
```

`Tests/recordings/` holds the recorded lines and one whole recorded call (`recorded-call-1.jsonl`; the words said in it are made
up). Live trials written there stay out of git. `Tests/measure/differ.mjs` lists, in one place, what the differential check
leaves out and why, and the real differences it found (each with its smallest case in `Tests/measure/diff-cases/`).

## Not known

- Echo cancelling, hearing you over the voice and false pauses can only be judged in a room.
- Whether the menu-bar microphone indicator goes off on mute (the engine stays on, voice processing sends silence).
