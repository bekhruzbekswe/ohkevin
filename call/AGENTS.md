# call/: rules

- The routes and events in `server.mjs` are a contract with two clients (the page and the Mac app): add, never rename
  or remove.
- `voice.mjs` changes only for a real defect, never for speed, and the change must pass `voice.replay.test.mjs`. If a
  change alters what a recorded call does, say why in the commit.
- `ears.mjs` sets when a turn ends; the Mac app ports it one for one. Change it as carefully as `voice.mjs`.
- Every module has its test beside it (`<name>.test.mjs`); `node --test` runs them all.
- A test never reaches a model with a real task, never plays sound, and leaves no process running.
