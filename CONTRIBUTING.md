# Contributing

How the pieces fit is in [ARCHITECTURE.md](ARCHITECTURE.md); why they are this way, in [decisions/](decisions/).
How branches, merges and releases work is in [AGENTS.md](AGENTS.md).

## Run it from source

```sh
cd call && npm ci                      # the SDK, with its own Claude Code binary for terminal runs
node server.mjs ~/some/project         # a call from the terminal
cd ../app && ./build.sh                # the Mac app, built from this checkout: build/Oh Kevin.app
```

A development build of the app uses this checkout's `call/` folder; a built app carries its own copy.
`?demo=1` on the call page replays a made-up call with no server, microphone or model: good for screenshots.

## Test

`./check.sh` runs every check below; run it before asking to merge. The checks one by one, from the repository root:

```sh
(cd call && node --test)               # the server and its modules, and the page in headless Chrome
(cd app && swift test)                 # VoiceCore, Ears and CallKit
(cd app && ./build.sh)                 # the app, then its replays and the differential against the page; AppChecks: app/README.md
```

Rules for tests:

- Nothing a test starts may reach a model with a real task. Anything that could reach Claude Code uses
  `WORKER_MODEL=haiku` and an empty throwaway project folder.
- Chrome in a test is `--headless=new` with a throwaway profile. Nothing plays through the speakers.
- A test leaves nothing running: no server, Chrome or helper process.

## Commits

`type: short title`, for example `fix: the page ends the call when the server stops`. Types and the rest are in
[AGENTS.md](AGENTS.md). A change to `call/` must keep the Mac app and the page working: `./check.sh` checks both.
