---
layout: post.njk
title: "Parachute is here"
subtitle: "The ecosystem launches today: Vault, Lens, Scribe, and a single-command installer"
date: 2026-04-23T12:00:00
author: "Aaron G Neyer"
permalink: /blog/parachute-is-here/
description: "Parachute is now available. One command installs the ecosystem: Vault for the knowledge graph, Lens for the web app, Scribe for voice transcription, all coordinated by a single CLI."
---

Four months ago I wrote [Opening the Parachute](/blog/opening-the-parachute/) — a description of what I wanted to build and why. Today it's real, and it's open source, and you can install it with one line.

```sh
bun add -g @openparachute/cli && parachute install vault
```

Add Lens and Scribe the same way:

```sh
parachute install lens
parachute install scribe
```

Then expose the whole thing at an HTTPS URL on your tailnet (or publicly):

```sh
parachute start
parachute expose tailnet
```

That's it. Your own knowledge graph, your own writing app, your own transcription — all running on your machine, reachable from every device you own, accessible to any AI that speaks [MCP](https://modelcontextprotocol.io).

## What's here today

**Parachute Vault** — the knowledge graph itself. Self-hosted, SQLite-backed, Bun-native. Notes, tags, links, attachments, full-text and graph queries. Exposed over both a REST API (for humans and tools) and [MCP](https://modelcontextprotocol.io) (for AI). Import from and export to Obsidian. Each vault is its own database on your disk, portable and entirely yours.

**Parachute Lens** — a browser-based companion for the Vault. Installable as a [PWA](https://web.dev/progressive-web-apps/) so it works offline on your phone, your laptop, any device with a modern browser. Write, link, tag, search, graph-browse, drop in voice memos that auto-transcribe. Point it at a vault URL, do a one-time OAuth handshake, and that's the setup. The earlier Parachute Daily — which required a native app install — is retired; Lens replaces it with the same workflow but works everywhere.

**Parachute Scribe** — audio transcription. Whisper-compatible API (`POST /v1/audio/transcriptions`) plus optional LLM cleanup. Runs locally on your machine by default, using [parakeet-mlx](https://github.com/senstella/parakeet-mlx) for on-device transcription. You can BYO a cloud provider for higher-quality models.

**Parachute CLI** — the coordinator. `install`, `start`, `stop`, `status`, `logs`, `expose` — one command for every lifecycle step across every service. Also a small hub page at your root URL that lists what you've installed.

## How it fits together

```
  Browser · Phone (PWA) · Pendant
             ↓
  Parachute Lens ───── REST ──→
                              ↘
  Parachute Scribe ── transcribe ──→ Parachute Vault ── MCP ──→ Claude · ChatGPT · Gemini
                                          ↓
                                   SQLite on disk
                                   (yours, portable, exportable)
```

Each service is a module. The CLI hosts them, coordinates them, and exposes them under a single HTTPS URL. The hub page at the root lists everything you have. Everything speaks a common contract — `/.parachute/info`, `/.well-known/parachute.json` — so adding a new module (a `Pendant`, a `Calendar`, a third-party service built by someone else) doesn't require re-architecting anything.

The URL shape stays consistent whether you're on your tailnet, on the public internet via Tailscale Funnel, or (eventually) on Parachute Cloud:

```
/                       → the hub
/lens                   → Lens
/vault/default          → Vault API (MCP + REST)
/scribe                 → Scribe API
/.well-known/parachute.json   → ecosystem discovery
```

## What I care about most

**Local-first.** Your data lives on your machine in a SQLite database. If this project disappeared tomorrow, your data would still be there — portable, exportable, and entirely yours. No lock-in, no cloud dependency, no phone-home.

**Open standard.** Everything's built on [MCP](https://modelcontextprotocol.io). Whatever AI you use today, whatever AI you'll use next year — Parachute works with it.

**Open source, AGPL.** You can read every line of code that touches your notes. The only way to earn trust with personal thinking is transparency.

**Extensible by design.** The module contracts are small and stable. If you want to build your own service that plugs into Parachute — your own capture surface, your own AI agent, your own integration — the ecosystem will render it like it was native. No vendor relationship required.

## What's next

Launch week was focused on the self-hostable base. Post-launch directions:

- **Identity architecture**: migrating OAuth to the hub origin (the seam is in place; the implementation lives in Vault today) so eventually every module shares one ecosystem sign-in.
- **Configuration portal**: the hub will render per-module settings forms automatically, pulled from each module's JSON Schema. You won't need the CLI for most config changes.
- **Scopes**: fine-grained permissions so clients request only what they need — read-only, read-write, per-vault, eventually per-folder.
- **Parachute Cloud**: the hosted path for people who'd rather not run their own services. Same architecture, same URL shape, same portability guarantee. Coming in a few months.

If you want to follow along, the [roadmap](/roadmap/) is live and the [source](https://github.com/ParachuteComputer) is open.

If you'd like to try it, the install walkthrough is on the [front page](/). For anyone who was using Parachute Daily: whatever you'd synced into your vault is still there. Install Lens, point it at the same vault, and your notes are waiting.

If you find anything broken: please [open an issue](https://github.com/ParachuteComputer). I'm launching this small and listening carefully.

Thanks for being here.

— Aaron
