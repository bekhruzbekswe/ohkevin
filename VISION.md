# Vision

Oh Kevin lets you run Claude Code by voice. You talk to Kevin, a fast voice that answers at once; Kevin hands the real
work to Claude Code workers in your project, several at a time, and tells you how they are doing while you keep
talking. You never have to look at a screen to steer the work.

It is for developers who already use Claude Code and want to think out loud, walk around, or keep several pieces of
work going without typing. It is one Mac app, running on their own Mac with their own Claude Code and their own account:
there is no server of ours and nothing passes through us. A browser page for every other computer is coming.

What good looks like: the call feels like talking to a sharp colleague. Turns end when you are done, not when a timer
says so. Every reply is short. Every screen has one obvious next step, and every number is measured, not assumed.

## Non-goals

- Rebuilding the Claude app. The work opens there; Oh Kevin is the voice in front of it.
- Being faster at the cost of natural turn-taking.
- A login, an account, or a server of our own. Claude Code's own sign-in is used.
- A second app for the Mac. One Mac app; other computers get the browser page (decision 8).

## What needs the owner's sign-off

- Anything the user sees or hears: designs, words on screen, the voice, how turns end.
- Releases, publishing, and anything that leaves this repository.
- Licences and what is shipped or downloaded.
- Changes to the call's contract (`call/server.mjs` routes and events) or to `call/voice.mjs`.

Decisions already made, and why, are in [decisions/](decisions/).
