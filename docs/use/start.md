---
title: "Get Parachute"
summary: "A vault of your own, the Parachute app, and one sign-in."
door: use
order: 1
status: next
status_note: "The Parachute app has no public release yet. Builds for Android and Apple Silicon Macs come from the app's repository and are shared by hand while it is tried; this page says what the first release will ask of you."
checked: "parachute README.md (Install and sign in), docs/SIMPLE.md; parachute-cloud workers/identity/wrangler.toml"
---

You need two things: a **vault** (where your records are kept) and the **Parachute app** (where you see them).

## 1. A vault

Pick one:

- **Parachute Cloud.** Sign up at [my.parachute.computer](https://my.parachute.computer/console) with your email. We run the server; your vault is yours to export. See [Parachute Cloud](/docs/run/cloud/).
- **Your own server.** One command installs Parachute on a Mac or a Linux box. See [Run your own](/docs/run/self-host/).
- **Someone else's.** An organisation or a friend can give you a vault on theirs.

## 2. The app

Android (8 or newer) and Apple Silicon Macs. The Mac build isn't notarised yet, so macOS asks once before it opens it.

## 3. Sign in

- **On Parachute Cloud:** on the first screen, **Sign in with Parachute Cloud**, then the code it mails you. No key needed. The app opens on your notes.
- **On a server of your own, or an organisation's:** you sign in with a **key**, a Nostr key the app keeps in your phone's or computer's secure storage. On the first screen choose **Make a new key**, or **Pair from a device that has your key** if one already does. The server's owner links your key to your account once (`parachute user pubkey add`). Then type the server's address, say it is **Mine**, and press **Approve** on the server's page.

The first sign-in reads your **home vault** only. Other vaults on the same server show in Settings as one line each, **Open**, and are read only after you tap it.

## What you see first

On Parachute Cloud you start in the **simple app**: **Notes** (every vault's newest notes, search, new note), **Capture** (a line or a voice note into `Inbox/`), and **Connect** (the address to give your AI). Settings → **Your app** switches to **Everything**, or to a [bundle](/docs/use/your-home/) you or your AI made.

Next: [connect your AI](/docs/use/connect-your-ai/).
