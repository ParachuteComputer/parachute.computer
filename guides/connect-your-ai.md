---
title: "Connect your AI"
description: "Your vault speaks MCP, so any AI — Claude, ChatGPT, Cursor — can read and write it. One memory, shared with every AI you connect."
permalink: /guides/connect-your-ai/
order: 4
vault_path: "Connect your AI"
---
# Connect your AI

Your vault speaks MCP — an open standard — so any AI can read and write it:
Claude, ChatGPT, Claude Code, Cursor, or an agent you build. Grab the
connection URL from your console.

Once you're connected, try:

- "Read the Getting Started note and help me set this vault up."
- "What did I want to write about?"
- "Tag my untagged notes."

Your AI sees what you see — the same notes, links, and tags — and what it
writes lands here, as notes you can read, edit, or delete. There's even a note
in this vault written for it: [Getting Started](/guides/getting-started/), the vault-design brief your
AI reads so you don't have to.

One memory, shared with every AI you choose to connect. That's the point.

Next: [Yours to keep](/guides/yours-to-keep/).

<!-- site-only -->

## Connect from anywhere

Your console hands you a ready-to-paste command for Claude Code. On **Parachute
Cloud**, each vault card at [cloud.parachute.computer/console](https://cloud.parachute.computer/console)
shows that vault's own URL:

```
claude mcp add --transport http parachute-<vault> https://my.parachute.computer/vault/<vault>/mcp
```

**Self-hosting**, it's the same command pointed at your own hub:

```
claude mcp add --transport http parachute-<name> <your hub origin>/vault/<name>/mcp
```
