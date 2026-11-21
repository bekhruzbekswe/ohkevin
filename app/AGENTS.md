# app/: rules

- `Sources/VoiceCore`, `Sources/CallViews` and `Sources/Updating` are links to `launcher/Sources/`. Edit them there, on an
  `a/` branch, and keep both apps building (`./check.sh`).
- `Sources/Ears` is a one-for-one port of `call/ears.mjs` and `call/voice.mjs`'s turn-taking; its replays must match.
- Everything else in `app/` is the Mac app's own, changed on `b/` branches.
