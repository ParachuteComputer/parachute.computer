---
layout: post.njk
title: "Parachute is Here"
subtitle: "An open memory layer for your AI, your own mind, and everything you use"
date: 2026-04-23T12:00:00
author: "Aaron G Neyer"
permalink: /blog/parachute-is-here/
description: "Frank Zappa said the mind is like a parachute — it doesn't work if it's not open. That applies to our extended mind too. Today I'm introducing Parachute Vault: an open, self-hosted knowledge graph that any local MCP client can read and write to — starting with Claude Code."
substack_url: "https://openparachute.substack.com/p/parachute-is-here"
og_type: "article"
---

![A parachute descending over open plains at dawn, its canopy woven with a luminous knowledge graph.](/assets/blog/parachute-is-here.jpg)

> The mind is like a parachute. It doesn't work if it's not open.
>
> — Frank Zappa

I think that applies just as well to our extended mind — the growing pile of tools, notes, chats, and agents that do our thinking with us. For that to actually work well, it has to be open.

That's the bet behind what we're launching today.

## The orientation

Most of our technology is trying to work as one whole by fitting everything inside a single box. You get it all inside Notion, or inside ChatGPT, or inside Apple, or inside Google — and inside the box, sure, things feel coherent. But the box is closed, and a closed box keeps us limited to whatever the box-maker decides technology can be.

**Parachute is taking a different orientation.** You should be able to work with it, change it, modify it, connect it to whatever else you already use. Someone you trust may host it for you to make it easier, and we'll support that choice — but *that it's a choice* is the whole point.

## The problem I've been sitting with

I've been a heavy user of both Obsidian and Tana — two tools I hold particularly dear. Both of them lean on the same bet: that adding a little structure to your notes and linking them together creates a remarkable primitive for organizing a mind.

And they're right. It's real. When it works, it's magic.

The catch is that getting there has always required a lot of upfront effort to architect the whole system. Everybody who really uses these tools has lived the paradox: *spending more time thinking about your second brain than using your second brain*. The tools are amazing if you invest. Most people never get to "amazing" because the investment is so steep.

Something's changing. LLMs can now do the architecting with us. Some people are already wiring Claude Code into their Obsidian, or plugging an MCP into Tana. But these are still not the most intuitive experiences — in Tana your data is trapped in Tana's ecosystem, and in Obsidian your data is on a file system rather than a real database, which limits what you can build on top of it. And for either of them, the code itself is closed — if what you need doesn't match what they ship, you're stuck either doing things their way or moving your data elsewhere.

## What we built

**Parachute Vault** is a graph database for your knowledge. Notes, tags, links, and structured metadata — on your machine, in a SQLite file that's yours, portable, and doesn't require us to exist. Every operation is exposed over [MCP](https://modelcontextprotocol.io), and to any script, app, or tool you write via REST.

Today the cleanest on-ramp is **Claude Code**: install the Vault, open a session, and Claude's already reading and writing to your graph — no config, no copy-paste, no per-session context rebuild. Notes from this morning's session become context for this afternoon's. Tags accrete, wikilinks resolve, the graph compounds. Any other local MCP client — Codex, Goose, OpenCode, Cursor, Zed, Cline, your own agent — talks to the same endpoint.

**claude.ai, ChatGPT, Gemini come next.** The plumbing exists; we're finishing the polish on public HTTPS exposure and the custom-connector OAuth flow. Those land in the next couple of weeks — we wanted to ship the single-client experience well before promising the many-client one. The architecture was designed around it from day one.

The install is one line; [the install guide](/install/) has the rest.

## A reference UI — if you want one

**Parachute Notes** is a web interface for your Vault. Run `parachute install notes`, open `localhost:1942/notes` in your browser, point it at your Vault, and you've got note browsing, search, tag views, a graph visualization, markdown editor with live preview, and voice capture with auto-transcription. Usable today as a local web app on your laptop. The mobile-PWA install flow lands alongside public HTTPS exposure in the next few weeks.

It's also explicitly not the definitive front-end. Our hope is that you might build your own. In this new era, it's genuinely possible to build a front-end that works how *your* brain works — not how a design team at some company guessed it might. [Fork the source](https://github.com/ParachuteComputer/parachute-notes) — Vite + React + TypeScript, AGPL — read the Vault's API, and build something that's uniquely yours. That's the invitation.

## Where this goes

We see Parachute as a first small step in a long journey — toward AI and human collaboration that's actually integrated, actually connected, and actually owned by the person whose mind it's extending. Post-launch we're working on hub-issued OAuth so one sign-in covers every module, per-token scopes so you can give an agent exactly the permissions it needs, a config portal so per-module settings render without the CLI, and Parachute Cloud for people who'd rather not run their own services.

The [roadmap](/roadmap/) is live. The [source](https://github.com/ParachuteComputer) is open. Everything is AGPL.

## Try it

```sh
bun add -g @openparachute/cli && parachute install vault
```

Start a Claude Code session after install and your Vault's tools are right there — `create-note`, `query-notes`, `update-note`, `delete-note`, `list-tags`, `update-tag`, `delete-tag`, `find-path`, `vault-info`. Ask Claude to save something, pull what you've written about a topic, walk the graph. That's the whole loop.

The [install guide](/install/) has the rest. Public HTTPS + claude.ai / ChatGPT connectors land in the next few weeks; subscribe via [the blog](/blog/) or watch the [GitHub org](https://github.com/ParachuteComputer) for the announcement. If something breaks now, [open an issue](https://github.com/ParachuteComputer) — we're launching this small and listening carefully.

I'm really looking forward to seeing what you build with it.

— Aaron Gabriel & the Parachute team
