---
title: "Connect your AI"
summary: "Give Claude, ChatGPT or any MCP app your vault's address; it can then read and write your records."
door: use
order: 2
checked: "parachute docs/SIMPLE.md (Connect); parachute-cloud workers/identity/src/console.ts cardFor; parachute-core packages/vault/src/mcp-tools.ts getServerInstruction, packages/vault/core/src/mcp-annotations.ts"
---

Every vault has one address for AI apps, its **connector address**:

```
https://<your server>/vault/<vault name>/mcp
```

On Parachute Cloud that is `https://my.parachute.computer/vault/<vault name>/mcp`. In the app's simple view it is under **Connect** on the bar, with **Copy**; your Cloud account page shows it too, with the Claude Code command ready to copy. The first time an AI app connects, you sign in and approve it on your server's page; nothing else to paste.

## Claude

- **Claude:** on claude.ai, **Customize → Connectors → + Add → Add custom connector**. Paste the address, press Continue, and allow it when Parachute asks. It then works in Claude's desktop and phone apps too.
- **Claude Code:** `claude mcp add --transport http parachute <address>`

## ChatGPT

In Settings, **Apps & Connectors**: create a custom connector (an MCP server) and paste the same address. It needs a paid plan, and may need Developer mode. Each tool says whether it only reads or changes something, so ChatGPT needn't ask before every read.

## Any other MCP app

Cursor, Grok, Muse and others take the same address: an MCP server over HTTP, signed in with OAuth.

## Then ask it

Your AI starts each conversation knowing your vault's name and its types (and, on a server with the `docs` tool, how to read these pages). Try:

- "Make me a reading tracker I can use in Parachute."
- "What did I capture this week? Sort it into the right places."
- "Make me a home screen with my journal and my reading list pinned."

What it makes shows up in the app: records in your vaults, new [applets](/docs/build/make-an-applet/) in the list of applets (in **Everything**, or your bundle; each asks you before it runs), and your [home](/docs/use/your-home/).

## What it can do

The connection can do what you allowed when you approved it: read, write, or also manage the vault's types and keys. It reaches that one vault, nothing else on your server. An AI can't make an applet run: you allow each one in the app ([What Allow means](/docs/use/allowing-applets/)).
