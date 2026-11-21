# 6. Trunk-based, one repository

Status: decided, November 2026.

## Context

Two tracks (the launcher and the Mac app) worked on long-lived branches merged through an integration branch, and
releases lived in a separate place. Merges collided and history was hard to follow.

## Decision

One public repository holds the source and the releases. `main` is the only long-lived branch and is always
releasable; work happens on short `a/` (launcher and shared code) and `b/` (Mac app) branches, checked with
`./check.sh` and merged fast-forward. Releases are built only from the main checkout. The rules are in `AGENTS.md`.

## Consequences

- Shared code changes on `a/` branches only; the Mac app takes them in by rebasing.
- Release history (zips and feeds) lives outside git and is refilled from GitHub when lost.
