---
layout: post.njk
title: "Parachute is here"
subtitle: "An open memory layer for your AIs — install in one line, works with every tool that speaks MCP"
date: 2026-04-23T12:00:00
author: "Aaron G Neyer"
permalink: /blog/parachute-is-here/
description: "Your AI's memory is fragmented. Even inside one company's tools — Claude Code, Claude Chats, Claude Cowork — each conversation starts from scratch. Parachute Vault is a persistent memory layer any AI can read and write to. Notes, tags, links, on your machine, over MCP."
---

Your AI's memory is fragmented. Claude Code doesn't know what you said to Claude in the browser. Claude Cowork doesn't know what Claude Code is working on. Even inside one company's ecosystem, every chat starts from scratch. Across ChatGPT, Gemini, or any other tool you use, it's worse — each one a walled garden.

Today we're launching **Parachute Vault** — an open memory layer that any AI can read and write to. One knowledge graph, on your machine, connected to every tool you use.

```sh
bun add -g @openparachute/cli && parachute install vault
```

That's the entire install. You now have a self-hosted knowledge graph — SQLite on disk, exposed over MCP + REST — organized around **notes, tags, and links**. Obsidian-adjacent vocabulary, now accessible to every AI you talk to.

## Use it immediately

Run that install inside any Claude Code session — Claude Code picks up the MCP automatically and can start reading and writing your vault before you leave the terminal.

Want it elsewhere? One more command:

```sh
parachute expose tailnet
```

Now your vault is reachable at an HTTPS URL on your tailnet. Point Claude Desktop at it. Point ChatGPT Desktop at it. Point Claude Cowork, Gemini, your own custom agent — anything that speaks MCP — at the same URL. They all read and write to the same graph.

For public exposure through Tailscale Funnel:

```sh
parachute expose public
```

Same URL shape, now reachable from anywhere.

## What this unlocks

- **Persistent memory across every AI you use.** The notes your Claude Code session wrote are there for ChatGPT to read an hour later. What you capture on your phone is context for the next chat you open on your laptop.
- **A compounding knowledge base.** As your AIs read and write, the graph grows. Wikilinks resolve, tags accrete, notes point at each other. Queries get richer over time — not because the index is bigger, but because the shape of what's there gets more useful.
- **Your data, your hardware.** It's a SQLite file on your disk. If Parachute disappeared tomorrow, your graph is still there.

## Security-first install

The default install runs a local daemon on `127.0.0.1:1940` — nothing reaches the network without you asking. `expose tailnet` keeps traffic on your tailnet; `expose public` puts it behind a public HTTPS URL (Tailscale Funnel by default, or `--cloudflare` for a 30-second zero-config Cloudflare Quick Tunnel).

Before you share a public URL, gate it: either **OAuth + 2FA** for human clients like claude.ai (`parachute vault set-password && parachute vault 2fa enroll`), or **API tokens** for scripts and agents (`parachute vault tokens create`). Either works on its own; use both if you want. The goal is that *something* is gating writes once the Vault is reachable externally.

Per-token scoping is coming — so you can give a read-only integration read-only access, or limit an agent to one corner of your graph. Queued, not in this launch.

## The shape

Vault is the core. Self-hosted, SQLite-backed, runs as a local daemon, imports and exports Obsidian markdown.

If you want a UI to view and edit your notes through, we've built one — an alpha-quality PWA you can install or fork. It's an example, not the definitive front-end. Run your own, modify this one, or build something new. The API is open.

This is **alpha**. The core works, but interfaces will shift, docs are thin, edges are rough. AGPL, and open to contribution.

## What we care about most

**Local-first.** Your data is a SQLite file on your disk.

**Open standard.** Everything speaks [MCP](https://modelcontextprotocol.io). Whatever AI you use today or next year, Parachute works with it.

**Open source, AGPL.** Read every line of code that touches your notes.

**Extensible.** The service contracts are small and stable. Plug in your own modules.

## What's next

- **Hub-issued OAuth** — one sign-in across every module in your ecosystem.
- **Per-token scopes** — fine-grained permissions for agents and integrations.
- **Config portal** — per-module settings rendered from each module's JSON Schema.
- **Parachute Cloud** — a hosted path for people who'd rather not self-host. Same architecture, same guarantees.

The [roadmap](/roadmap/) is live. The [source](https://github.com/ParachuteComputer) is open.

If you try it, tell us what breaks. [Open an issue.](https://github.com/ParachuteComputer) We're launching this small and listening.

Thanks for being here.

— The Parachute team
