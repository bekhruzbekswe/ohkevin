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
   In the same commit, `CHANGELOG.md`'s Unreleased items become that release's section ("Launcher 0.7 — <date>").
2. Tag that commit, locally: `git tag -a v0.7` or `git tag -a app-v0.4`, the message being that section (3 to 8 bullets,
   Added / Changed / Fixed, in users' words). It is the release notes: in the update prompt and on GitHub.
3. Build: `launcher/release.sh 0.7` or `app/release.sh 0.4`, with `SIGN_ID="Oh Kevin"` (the launcher also needs its
   `FEED_URL` and `DOWNLOAD_URL_PREFIX`, as in the last release). Signs, zips, puts the tag's message in the feed, makes
   the disk image. Publishes nothing; it refuses without the tag on the commit it builds.
4. The owner tries that build on a real call. Not right: fix it through a normal branch, move the unpushed tag to the
   new commit (`git tag -f -a`), and rebuild the same number.
5. Publish, only on the owner's own go in that session: `git push origin main v0.7`, then `launcher/publish.sh 0.7` or
   `app/publish.sh 0.4`. It uploads the files, SHA256SUMS over them, and the tag's message as the release notes.

- Only the newest launcher release is GitHub's "latest"; its apps read `releases/latest/download/appcast.xml`. Earlier
  releases stay, with their files.
- The Mac app's releases are never "latest"; its apps read the fixed release `app-feed` (`appcast-app.xml`), which
  publish.sh replaces.
- Version numbers only go up. Sparkle never installs a lower version, so a bad release is fixed by a revert on main and
  a higher number; untick "latest" on the bad one meanwhile.

## What needs the owner

Pushing to origin, publishing a release, deleting releases and changing the repository's settings each need the
owner's own go. A go relayed by another session is not enough. The Sparkle signing key and the "Oh Kevin" certificate
stay in his Keychain; never print, copy or commit them.
