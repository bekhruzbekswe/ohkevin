# Security

## Supported versions

Only the latest release of each app gets fixes: the launcher's latest `v*` release and the Mac app's latest `app-v*`
release. Both update themselves.

## Reporting a vulnerability

Please report privately, not in a public issue: open this repository's **Security** tab and choose
**Report a vulnerability**.

## What is in scope

Oh Kevin listens to your microphone and drives Claude Code, which edits files and runs commands in your project.
Reports about any of these are welcome:

- the microphone and what is sent where (see the README's "What leaves your Mac");
- what a spoken "yes" may approve, and anything that gets Claude Code to act beyond your settings;
- the local call server and its page (`call/`), which listen only on this Mac;
- updates: the Sparkle feeds, their EdDSA signatures and the downloads they point to;
- what the apps download on first run (Node, the Agent SDK, the local voice), each checked against a pinned hash.

Claude Code's own behaviour belongs to Anthropic: report that to them.
