---
layout: post.njk
title: "Parachute is a System Now"
subtitle: "Two months in: an open, self-hosted set of modules for your AI and your mind — and an invitation to come build on it"
date: 2026-06-23T12:00:00
author: "Aaron G Neyer"
permalink: /blog/the-system-comes-together/
description: "When we launched in April, Parachute was a Vault. Two months of building later it's a small system of modules — memory, a UI host, transcription, and the hub that ties them together — that you can run yourself in one command. Here's what's there now, and an invitation to come use it."
og_type: "article"
---

> **DRAFT for Aaron's review** — voice/scope/title all yours to change. Notes inline as `<!-- -->`. Not built (lives in `blog/drafts/`). Hero image TBD.

<!-- Suggested hero: same parachute-with-knowledge-graph motif as the launch post, but wider — several woven canopies / a small constellation, to signal "system" not "one tool." -->

> The mind is like a parachute. It doesn't work if it's not open.
>
> — Frank Zappa

Two months ago I [introduced Parachute Vault](/blog/parachute-is-here/): an open, self-hosted knowledge graph that any AI could read and write over MCP. The bet was that your extended mind — the pile of notes, chats, tools, and agents that think *with* you — only works well if it's open.

Since then I've been building, mostly in the open, mostly with Claude as the other half of the work. The Vault is still the heart of it. But it grew a body. Parachute is a small **system** now — a handful of modules that each do one thing, compose into a whole, and run on your own machine in one command. This post is a tour of what's there, and an invitation to come use it.

## The orientation, still

The point hasn't changed: most technology tries to be coherent by putting everything inside one closed box. Parachute is coherent the other way — small open parts that connect, that you can change, host yourself, or have someone you trust host for you. *That it's a choice* is the whole thing.

What's new is that there are now enough parts for the shape to be visible.

## The four modules

Each is its own open-source module; each is useful alone; together they're a system. (One page describing all of them lives at [parachute.computer/modules](/modules/).)

- **Vault** — your knowledge graph. Notes, tags, links, structured metadata in a SQLite file that's yours, portable, and doesn't require us to exist. Everything is exposed over [MCP](https://modelcontextprotocol.io) and REST, so any AI or app reads and writes the same source of truth. This is the memory the rest builds on.

- **Surface** — the UI host. It serves a reference Notes app over your Vault (browse, search, graph view, markdown editor, voice capture), and it hosts *your own* surfaces too — there's an SDK (`@openparachute/surface-client`) so building a custom view of your vault is a thin import, not a project.

- **Scribe** — transcription. Audio in, text out, with optional LLM cleanup, over a Whisper-compatible API. Local models or cloud providers, your choice and your keys.

- **Hub** — the part that makes it a system rather than a pile. It's the portal you open in a browser, the OAuth issuer that lets your AI connect securely, the supervisor that keeps the modules running (and surviving reboots), and the `parachute` command you drive it all from. You install the hub first; everything else installs through it.

## What landed in two months

The honest version — what actually shipped since April, not a roadmap:

- **Your AI connects for real.** claude.ai can connect to your Vault as a custom connector today — the public-HTTPS-exposure and OAuth flow we said were "coming" in April are here. <!-- Aaron: confirm the current state of ChatGPT/Gemini custom connectors before naming them — claude.ai is verified (it's the recurring real-user path); add the others only if they're actually working now. -->
- **One command to run it all.** `parachute serve` runs the hub as a supervisor with the modules as children, under your OS's process manager, surviving reboots — the same shape whether you're on your laptop, a VPS, or a container.
- **Host it for other people.** Multi-user hosting with invite links — stand up a Parachute and send someone a link to join with their own scoped access.
- **Run it on your own box.** A VPS you control — a Hetzner or DigitalOcean droplet with Docker — brings the whole stack up; [Fly](/deploy/fly/) is there too. Self-hosting on hardware that's *yours* is the heart of it. <!-- Aaron: reframed VPS-first per your steer; Render link dropped from the lead since it's deprioritized. Tune the host names to taste. -->
- **Your data stays yours.** Lossless portable-markdown export — git-projectable, Obsidian-round-trippable — so leaving is always an option (the best reason to stay).

## A preview: Channel

There's a fifth module taking shape that I want to show even though it's early. **Channel** lets you *talk to your Claude Code sessions* — over a chat window backed by your Vault, so the conversation is durable and shows up everywhere your memory does. It also lets you spin up **sandboxed agent sessions** from the browser and watch them work in an in-page terminal.

It's a preview (v0.1.0) — the shape is still moving, and I'd treat it as a glimpse of where agent-in-the-loop work is heading rather than something to depend on yet. But it's the most exciting edge of the project right now, and it's open if you want to look.

<!-- Aaron: this is the spot to decide how much to lean into Channel. Current framing = honest preview. Dial up or down to taste. -->

## Come use it

If April was "here's the memory," this is "here's the system, and it's ready for more of you."

```bash
bun add -g @openparachute/hub && parachute init
```

That installs the hub and walks you through the rest in your browser — account, vault, exposing it, connecting your AI. The [install guide](/install/) has the full path, [modules](/modules/) describes each part, and everything is on [GitHub](https://github.com/ParachuteComputer) to read, fork, and build on.

It's open. Come build with us.

<!-- Aaron: optional close — an invite-list / "tell me what you build" CTA, or a link to wherever you want feedback to land. -->
