# Oh Kevin: how code moves

One repository, github.com/bekhruzbekswe/ohkevin, holds the source and the releases. It is public. Two apps live in it:
the launcher (`launcher/`, tags `v<x.y>`) and the Mac app (`app/`, tags `app-v<x.y>`). They share `call/`, `design/`
and the launcher's `VoiceCore`, `CallViews`, `Updating` and `kokoro-runner` (the Mac app's copies are links).

## Branches: trunk-based

- `main` is the only long-lived branch. It is always releasable: every check passes on every commit.
- Work happens on a short branch cut from main, one task each, merged within a day or so, then deleted:
  `a/<topic>` for the launcher and shared code (`call/`, `launcher/`, `design/`), `b/<topic>` for the Mac app (`app/`).
  A change to shared code is an `a/` branch, even when the Mac app needs it.
- Keep your branch current with `git rebase main`; that is also how the Mac app takes in shared changes.
  Never rebase, amend or force-push `main`.
- Before asking to merge, run `./check.sh` from the repository root. Red means no merge.
- The owner looks and says it looks right; then the orchestrator merges with `git merge --ff-only` and deletes the
  branch. If main moved meanwhile, rebase and check again.
- A long experiment the owner wants kept aside gets its own branch and is deleted when it is decided. Nothing else lingers.

## Commits

- `<type>: <short title>`, types `feat`, `fix`, `chore`, `docs`, `release`. One idea per commit.
- No AI attribution of any kind: no Co-Authored-By lines, no "generated with" notes.
- The repository is public: no personal recordings, transcripts, keys or home-folder paths in any commit.

## Releases: from main only

Releases are built in the main checkout (on `main`, nothing uncommitted); the release scripts refuse anywhere else.
Release history (the zips and feeds `generate_appcast` reads) lives outside git, in a folder beside the checkout
(`RELEASES` overrides it); if lost, `gh release download` refills it.

1. Bump: one commit on main, `release: the launcher 0.7` (`launcher/VERSION`) or `release: the Mac app 0.4` (`app/VERSION`).
2. Build: `launcher/release.sh 0.7` or `app/release.sh 0.4`, with `SIGN_ID="Oh Kevin"` (the launcher also needs its
   `FEED_URL` and `DOWNLOAD_URL_PREFIX`, as in the last release). Signs, zips, writes the feed, makes the disk image.
   Publishes nothing.
3. The owner tries that build on a real call. Not right: fix it through a normal branch, rebuild the same number.
4. Tag after the owner's go: `git tag -a v0.7` or `git tag -a app-v0.4`; the tag's message is the release notes.
5. Publish, only on the owner's own go in that session: `launcher/publish.sh 0.7` or `app/publish.sh 0.4`, then
   `git push origin main v0.7`.

- The launcher's release is GitHub's "latest"; its apps read `releases/latest/download/appcast.xml`.
- The Mac app's releases are never "latest"; its apps read the fixed release `app-feed` (`appcast-app.xml`), which
  publish.sh replaces.
- Version numbers only go up. Sparkle never installs a lower version, so a bad release is fixed by a revert on main and
  a higher number; untick "latest" on the bad one meanwhile.
- Keep only the current release of each app on GitHub (plus `app-feed`); delete the previous one after a release.

## What needs the owner

Pushing to origin, publishing a release, deleting releases and changing the repository's settings each need the
owner's own go. A go relayed by another session is not enough. The Sparkle signing key and the "Oh Kevin" certificate
stay in his Keychain; never print, copy or commit them.
