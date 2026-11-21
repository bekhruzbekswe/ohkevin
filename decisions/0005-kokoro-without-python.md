# 5. The local voice without Python, espeak-ng loaded at run time

Status: decided, November 2026.

## Context

The local voice (Kokoro-82M) ran through a Python environment of 669 MB. espeak-ng, which gives Kokoro its
pronunciation, is GPL-3.0; our code is Apache 2.0.

## Decision

A small Swift program, `kokoro-runner`, runs the same model with the same pronunciation steps ported line for line. It
loads onnxruntime and espeak-ng's library at run time. Both, and their data, are downloaded at install onto the user's
Mac from their original sources, pinned by sha256; neither is in our repository or our releases.

## Why this way

- Same voice: 0 pronunciation differences in 3,170 requests, 78 of 78 audio files identical to Python's.
- Same speed, faster start; download 381 MB instead of 439, 365 MB on disk instead of 592.
- Running the stock espeak-ng program over a pipe instead changed stress on 430 of 3,170 texts.
- misaki (no espeak-ng) dropped words such as "7:05" and "Next.js", so it is not ready.

## Consequences

- `NOTICE` lists the downloaded parts and their licences.
