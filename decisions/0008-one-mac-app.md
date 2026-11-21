# 8. One Mac app

Status: decided, November 2026. Replaces [decision 3](0003-chrome-speech-for-the-launcher.md).

## Context

Two apps did the same job on the Mac: the launcher, whose call ran in a Chrome window with Chrome's speech recognition
(decision 3), and the native Mac app, with Apple's recogniser and a window of its own. Each needed its own setup, its own
releases and its own fixes.

## Decision

Oh Kevin is one Mac app, the native one. The launcher is deleted. Every other computer gets a browser page, later.

## Why

- Two Mac versions were one too many: one setup, one release and one set of fixes, and no question of which to download.
- There are no users yet, so nobody loses an app they rely on.
- The native app needs no Chrome, and speech becomes text on the Mac, never at Google.

## Consequences

- The launcher's shared code moves into `app/`; its tags and releases stop with 0.6.
- The Mac app's release becomes GitHub's "latest".
- The browser page, for computers that are not Macs, is its own milestone.
