# app/: rules

- `Sources/VoiceCore` has no screen: no AppKit or SwiftUI. What can be tested without a window lives there.
- `Sources/Ears` is a one-for-one port of `call/ears.mjs` and `call/voice.mjs`'s turn-taking; its replays must match.
- Everything in `app/` is changed on `b/` branches; `./check.sh` before asking to merge.
