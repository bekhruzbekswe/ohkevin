# 4. Kevin runs on Haiku

Status: decided, November 2026.

## Context

Kevin must answer within a second or so, every turn, and mostly relays: it answers, asks, and hands work over.

## Decision

Kevin is one more Claude Code session on Haiku that only talks and delegates. The real work goes to Claude Code workers
on the model the user picks (Opus by default; Sonnet, Haiku or Fable in Settings).

## Consequences

- Fast, cheap turns; the heavy thinking happens in workers, in parallel.
- Kevin's prompt keeps replies to one or two sentences and never does the work itself.
