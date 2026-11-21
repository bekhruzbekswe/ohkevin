# 3. Chrome's speech recognition for the launcher's calls

Status: decided, November 2026.

## Context

The launcher needs ears that are accurate, hear you while Kevin talks, and need no build step or model download.

## Decision

The launcher's call runs in its own Chrome window: Chrome's speech recognition on an echo-cancelled microphone track,
and Chrome's own voice when no local voice is installed. The window uses its own Chrome profile on a fixed local
address, so Chrome remembers the microphone permission.

## Consequences

- Chrome is required, and speech goes to Google to become text; the README says so.
- The native Mac app (Track B) uses Apple's recogniser instead and needs no Chrome; both talk to the same call server.
