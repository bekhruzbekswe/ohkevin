# 2. Natural turn-taking over speed

Status: decided, November 2026.

## Context

A build tuned for faster replies (shorter waits before Kevin answers) was tried on real calls. It cut people off
mid-thought and felt worse, though it measured faster.

## Decision

The earlier turn-taking is the baseline: a turn ends when you are done, not when a short timer runs out. Speed work may
not change when a turn ends. `call/voice.mjs` and `call/ears.mjs` change only to fix a real defect, and every change
passes the replay test of recorded calls (`call/voice.replay.test.mjs`).

## Consequences

- Faster replies come from elsewhere: a quick model for the voice (decision 4), shorter replies, a faster first sound.
- The Mac app's ears are a one-for-one port, checked against the page's.
