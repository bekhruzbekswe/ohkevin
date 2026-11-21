# Launcher

The menu-bar app from which calls are started, followed, answered and ended, with no terminal. It runs the same call
server (`call/server.mjs`) and the same call page; the page opens in a Chrome window of its own. The design it follows
is `design/final.html` (section "The launcher", tokens in `system.css`); `design/spec.md` is the build specification.

## Build and run

Needs macOS 14 or later and the Command Line Tools (`xcode-select --install`); Xcode is not needed.

```sh
cd launcher
./build.sh               # → build/Oh Kevin Launcher.app, ad-hoc signed
./build.sh --open        # build and open it
```

The app carries only our own code: the Swift binary and a copy of `call/` (no packages, no tests). On first run the
panel counts "N steps to go" and its marigold door is the next one; for the download it is "Install", which fetches a pinned Node from nodejs.org (sha256 checked) into
`~/Library/Application Support/Claude Voice/Runtime`, copies `call/` to `…/Call` and runs `npm ci --omit=optional` there;
the Agent SDK then runs the user's own Claude Code (`CLAUDE_PATH`), so Anthropic's 347 MB binary is never fetched or
shipped. The files are copied again at every check, and the packages reinstalled only when `package-lock.json` changed.
Settings holds a second, optional download: the local voice (uv, Python 3.12, hashed packages, the model files; about
about 425 MB to download, 600 MB on disk), deleted whole if any part fails.
Run from the repository instead (`swift run`, or the checks), the app uses the repository's `call/` (`repoCallFolder`),
and still needs the Runtime: the same Install fetches it. Its log is `~/Library/Logs/Claude Voice/call.log`; the call window's Chrome profile is
`~/Library/Application Support/Claude Voice/Chrome`, kept so Chrome remembers the microphone.

## Updates

The app updates itself with Sparkle 2 when it was built with a feed (FEED_URL); otherwise it has no updater and no menu item. It
trusts only updates signed by the key whose public half is in `launcher/SPARKLE_PUBLIC_KEY` (the owner's).

```sh
# once: make your update-signing key (it goes in your Keychain; the tool prints the public key to build into the app)
.build/artifacts/launcher/Sparkle/bin/generate_keys          # after one `swift build`
# every release: build, sign, zip into releases/, write releases/appcast.xml (publishes nothing)
FEED_URL=https://example.org/oh-kevin/appcast.xml \
DOWNLOAD_URL_PREFIX=https://example.org/oh-kevin/ SIGN_ID="Oh Kevin" ./release.sh 0.2
# GitHub: each release is published with its own feed (releases/v<version>/), apps read releases/latest/download/appcast.xml
./publish.sh 0.2                                              # gh release create v0.2 with the zip and appcast.xml; nothing else
```

- `launcher/VERSION` is the number people see (`release.sh <version>` writes it); the build number (the commit count, or `./release.sh 0.2 <build>`)
  is what Sparkle compares and must rise with every release; `release.sh` refuses one that does not.
- The app checks daily and from "Check for Updates…" in the three-dot menu. An update replaces the app; the support folder (Node, packages, voice,
  Chrome profile, logs, settings) is the user's and is never touched. At the next start the app's call/ is copied over the support folder's
  copy, and if its package-lock.json changed the packages are installed again by themselves (once, only when Node is already there).
- Signing: `SIGN_ID="Oh Kevin"` signs with a self-made code-signing identity from your keychain (Sparkle's helpers inside the app are signed
  with it first, then the framework, then the app), so macOS keeps one identity across updates. Without it the build is ad-hoc.
  A self-made identity gets no hardened runtime or timestamp (those are for notarization).
- The update line: inside the panel card, under the last button, after a hairline, one row (the card is 53 taller with it: 281). A sentence on
  the left; at most one word on the right (marigold when it is your move: Update, Try again, Move; ink for an offer: What’s new), or a thin
  progress line while updating. Checking, up to date and couldn’t check are gone after four seconds; "Updated to …" is said once; the new
  version and its progress appear only with "Update automatically" off; nothing during a call. "Move to Applications?" (on by default, only for
  a real app outside Applications) asks again at every start when ignored. `LineView` in CallViews draws it for both apps.
- The disk image: `release.sh` also makes `releases/v<version>/Oh-Kevin-Launcher-<version>.dmg` (`make-dmg.sh`: volume "Oh Kevin", the approved 640 × 400
  picture, the app and a link to Applications, signed with SIGN_ID) with Finder itself laying it out (AppleScript: a window opens briefly and macOS asks once to control Finder; `DMG_LAYOUT=dmgbuild` skips Finder, but dmgbuild's
  layout shows no background here). `publish.sh` uploads it under its version and as `Oh-Kevin-Launcher.dmg`.
- Rehearsal, on this Mac only: `./rehearse-update.sh` builds 0.1 and 0.2 against a feed on 127.0.0.1 and prints the
  three steps (serve the folder, open 0.1, choose "Check for Updates…").

## Test

```sh
swift test                                                     # the core: plain words (every row), the event stream,
                                                               # approvals, reconnects, port, local voice, sign-in, processes
swift build --product LauncherChecks                           # the checks: never shipped in the app
CHECKS="$(swift build --show-bin-path)/LauncherChecks"
"$CHECKS" --snapshots build/snapshots                          # every state, light and dark, drawn offscreen: nothing opens
"$CHECKS" --settings-live "$(mktemp -d)"                       # the real Settings window on screen, real events, photographed (opens a
                                                               # window and moves the pointer; needs Accessibility permission)
"$CHECKS" --first-run "$(mktemp -d)"                           # a Mac from zero, in a temp folder: Node and packages for real,
                                                               # the voice only offered, a stand-in call; pictures and timings
"$CHECKS" --ui-test build/snapshots                            # the real app against a stub server: no model, no sound
"$CHECKS" --self-test "$(mktemp -d)"                           # a real call, the real call window, then a crash (on a borrowed Node)
"$CHECKS" --clean-install "$S"                                 # a Mac with nothing: Install and Download for real (below)
"$CHECKS" --hand-over "$(mktemp -d)"                           # rarely: one line to Claude Code (Haiku), End Call, the
                                                               # hand-over for real; leaves a session in the Claude app
```

- **UI test.** The launcher runs its real code against `Tests/stub-server.mjs` (the call server's event stream and
  routes, and a stand-in call page that only connects) and a stand-in login shell whose PATH puts a stand-in Claude Code
  CLI first. The real call window opens in a throwaway Chrome profile. The test works the app the way VoiceOver does:
  through its accessibility tree it finds controls by what they say, presses them and reads what the panel says; one
  first click is a real mouse event on a panel that opened by itself. It installs the packages for real (`npm ci`) in a
  scratch copy (on a borrowed Node: the pinned one is the clean install's), signs in through a lent terminal, cancels starts, breaks servers at start and mid-call, drops the feed,
  ends calls both ways, takes over a call window left behind, and draws every state, light and dark, into
  `build/snapshots`. Pictures are the app's own views on its live state, drawn afresh.
- **Snapshots.** `--snapshots <folder>` draws every state of the panel and the menu-bar item, light and dark, at 2x, offscreen
  (no window shown, nothing launched), from the same `PanelInput` the app fills, and runs the design's size check on the drawing.
- **Clean install.** `S=$(mktemp -d /private/tmp/cm.XXXX)` (keep the path short: espeak cannot read its data from a long one),
  put a copy of the built app in it (`ditto "build/Oh Kevin Launcher.app" "$S/Oh Kevin Launcher.app"`, then
  `xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" "$S/Oh Kevin Launcher.app"`), run the check, `rm -rf "$S"`.
  It takes the call files from that copy and keeps support folder, Chrome profile and preferences inside `$S`; its PATH holds
  no Node, only your Claude Code. Through the panel's accessibility tree it presses Install, then asserts the pinned Node, the
  SDK without its native binary, the lock mark, that a second Install fetches nothing, and downloads the voice (tts.py must
  say ready). About 460 MB of real downloads (Node 27.5, packages 9.5, voice 425), and no call: nothing reaches Claude.
- **Self-test.** A real call server and the real call window (silent fake microphone, throwaway profile): ready, the
  page starts by itself with talking over the voice on, Stop, End Call, the window closes as the ending begins, nothing
  is left running; then a helper holding a call is killed with SIGKILL and its server must follow. It never sends Claude
  Code a task, and a stand-in for the local voice keeps the real one from starting. Everything stays in the folder given.
- The checks reach into the app only through `LauncherKit`'s `Setup` (the call folder, ports, Chrome profile and extra
  Chrome arguments), whose standard values are the app's own.
- The tests use Swift Testing: XCTest does not come with the Command Line Tools. Package.swift names the Swift Testing
  macro plugin itself, because the Command Line Tools' compiler often loses it after an edit. The views avoid `@State`
  (its macro plugin is not in the Command Line Tools), so view state lives in the model.
- The call tests stay where they were: `cd call && node --test`.

## Layout

```
build.sh                  the one build script: compiles, writes Info.plist and the icon, signs
design/                   spec.md: the build specification of the panel and the menu-bar item (the drawings are in design)
Sources/VoiceCore/        everything testable without a screen (ships)
  Product.swift           the product name and the app's file name ("Oh Kevin Launcher", so it never replaces the Mac app "Oh Kevin.app"), in one place (build.sh reads it too)
  CallSettings.swift      settings and the server's environment built from them
  PlainWords.swift        Claude Code's steps in plain words (used by Track B; the panel no longer shows steps)
  PanelState.swift        the panel as plain data: PanelInput in, PanelData and intents out; tested
  CallStatus.swift        the event stream: workers, requests, answers; phases, failures, the timer
  Health.swift            what is missing and its fix; sign-in; finding the local voice
  Install.swift           the pinned Node, the packages and the local voice: download, check, install
  Shell.swift             reads the login shell's environment, so Claude Code is found from Finder
  CallServer.swift        starts and ends the server process, the log, the port and process-tree helpers
  Disclosure.swift        what leaves the Mac and what runs unasked
Sources/CallViews/        the panel's SwiftUI views, as a library any Mac app can host (ships): plain data in, intents out
  Panel.swift             PanelView(data:active:still:send:), its rows and controls, fittedName
  Palette.swift           the design's colours, light and dark
  Wave.swift              the mark's chevron geometry and the wave's shapes and motion
Sources/LauncherKit/      the app's windows and model (ships)
  AppDelegate.swift       the status item and its dot, the panel window (PanelHost), keys, Settings; runApp()
  Launcher.swift          the one model: settings, the call, the call window, what is missing; Launcher.panel builds the data
  MenuBarItem.swift       the 52 × 22 menu-bar item's art
  Style.swift             Settings' small button
  SettingsView.swift      the settings window
Sources/ClaudeVoice/      main.swift: runApp(). The only binary in the app
Sources/LauncherChecks/   UITest.swift, Snapshots.swift, SelfTest.swift, CleanInstall.swift, AppIcon.swift (never shipped)
Tests/VoiceCoreTests/     unit tests
Tests/stub-server.mjs     the UI test's stand-in for the call server
```

## How it works with the server

- The launcher starts `node server.mjs <project>` with `CALL_LAUNCHER=1` and every setting as an environment variable,
  on port 4747 or the next free one up to 4757. It makes the call's key, so it can open the page already connected.
- It reads `GET /events?watch=1`, the page's own event stream; `watch` keeps it from counting as a call page.
  Requests are answered in the call page (`POST /permit`, and `POST /stop {name}` for one worker or `POST /stop` for all, are the page's). The `voice` event says what the voice
  is doing (listening, speaking, thinking, muted) and whether the page can mute; Mute is `POST /mute {on}`, which the server
  relays to the page as the `mute` event, and the page says it did on `/live {muted}`. End Call sends SIGINT when the call's work should open in
  the Claude app (as Ctrl-C does) and SIGTERM when not.
- The call page opens with `go=1`: it starts listening by itself, and its End call posts `/hangup`; the server, started
  by the launcher, ends the call itself as Ctrl-C does, so the end does not depend on the launcher's feed. A hang-up
  whose hand-over did not open the Claude app exits with 3, so the launcher's last line is true.
- A blocked microphone: the page posts `/mic` (`chrome` or `mac`), the server sends it on as the `mic` event, and the
  pill says "Mic blocked" and its door is "Allow microphone", which opens the right settings (Chrome's site settings in
  the call window's Chrome, or macOS's Privacy & Security › Microphone).
- A server that breaks mid-call is started again once (same port, same `CALL_KEY`, same log) while the call window is open; the
  page's event stream reconnects by itself (a launcher page keeps reconnecting in the background, and after 15 s says "Call lost / Press Call again in the menu bar" while it does) and
  the call goes on in the same window. It is a new call: the voice has no memory of the old one and the workers are new.
  A second break leaves "Call lost" with the window open; "Call again" starts the same server once more and that window
  reconnects. Without an open window it is a fresh start. A page not started by the launcher keeps its own reload.
- The call window is a Chrome of the launcher's own (`--user-data-dir`, app mode). It closes as the ending begins. If
  the launcher crashed and left one running, the launcher closes it when it starts again. It finds it through its
  profile's SingletonLock, and touches it only if that process's command line carries this profile.
- The server's stdin is a pipe the launcher holds. If the launcher crashes or is force-quit, the pipe closes and the
  server hangs up by itself.
