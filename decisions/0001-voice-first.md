# 1. Voice first, not a rebuild of the Claude app

Status: decided, November 2026.

## Context

Claude Code already has good screens: the Claude app shows sessions, diffs and history. Early designs drifted toward
showing the same things in our call window.

## Decision

Oh Kevin is the voice in front of Claude Code: you manage several Claude Code sessions by voice alone. The call window
shows only what a voice call needs (what you said, what Kevin said, one card per worker, a request that needs you).
Anything deeper opens in the Claude app ("Open in Claude"), and when a call ends its work opens there.

## Consequences

- No diff viewer, file browser or session history of our own.
- A feature is judged by whether it helps you steer work without looking.
