---
title: "Run your own"
summary: "One program, `parachute`, runs your vaults on a Mac or a Linux box. Install it, make a vault, sign in."
door: run
order: 2
checked: "parachute-core README.md (Install), packages/cli/src/front.ts (0.9 command names), `parachute help` on 0.9.0-pre.1, GitHub releases of parachute-core (0.8.0 latest, 0.9.0-pre.1 pre-release); install-runbook.md"
---

Parachute is one program, `parachute` (npm package `@openparachute/core`, source [parachute-core](https://github.com/ParachuteComputer/parachute-core)). It is the server the app and your AI talk to, and it holds your vaults.

## Install

- **One line, on a fresh Linux box or a Mac:** `curl -fsSL https://parachute.computer/install/parachute.sh | bash`. On a Linux box with a public address it also sets up HTTPS. Then open the address it prints. (It still installs from npm's `next` tag, a pre-release, until it is switched to `latest`.)
- **With npm** (needs Bun 1.4 or newer): `npm i -g @openparachute/core`.
- **A release bundle** with its own Bun: download `parachute-core-<version>-<platform>.tar.gz` and `SHA256SUMS` from [the releases](https://github.com/ParachuteComputer/parachute-core/releases), check, unpack, run `bin/parachute install`.
- **An AI doing it for you:** give it the [install runbook](/install.md). It is written for an agent, with nothing to type by hand.

npm's `latest` is the current release, and `@beta` the next one's pre-releases ([releases](https://github.com/ParachuteComputer/parachute-core/releases)). The commands below are 0.9's; 0.8's older names still work in 0.9 and say what replaced them.

## Make a vault, and someone to use it

```bash
parachute status                       # is it up, where, which vaults
parachute vault new home               # 0.8: parachute vault create home
parachute user pubkey add --user me <npub1…>   # let a Parachute app's key sign in (0.8: parachute auth link-pubkey)
```

The server answers on port 1939. To reach it from your phone, put it on your tailnet or behind HTTPS: `parachute setup expose`.

## Day to day

| | |
|---|---|
| `parachute keys new <name> --vault <vault> --can read` | a key for a script ([Keys](/docs/build/keys-and-scopes/)) |
| `parachute backup` | the vaults' backups (`now`, `list`, `schedule`) |
| `parachute upgrade` | the newer release from this server's channel (`--check` tries it on a copy first) |
| `parachute doctor` | check; `--fix` repairs what is safe to repair |
| `parachute changes` | what 0.9 renamed, and what replaced it |

Every command: `parachute help`, and `parachute <command> --help`.

## On a box with Parachute 0.7

0.7 was two packages, `@openparachute/hub` and `@openparachute/vault`. Use the release bundle (it never touches the old install), then `parachute-core takeover` moves your vaults onto the new program. Don't `bun add -g @openparachute/core` there first: it silently takes over the `parachute` command.
