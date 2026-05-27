---
layout: post.njk
title: "Starter prompt — build a custom UI for your vault"
description: "Paste this into Claude Code or Codex with your vault's HTTP API + an API token. The AI will generate a static SPA, host it on GitHub Pages, and wire it to your vault."
permalink: /onboarding/surface-build/
date: 2026-05-26T12:00:00
---

A custom front-end for *your* vault, designed to surface what *you* actually look at. Built by an AI in your editor — no framework lock-in, no Parachute approval needed. Lives on GitHub Pages or any static host.

This is the second of two starter prompts. The first ([set up your vault](/onboarding/vault-setup/)) is for figuring out what's in your vault. This one is for figuring out how you want to see it.

**Before you paste**: have a vault running with some content in it (even just a getting-started note works), and an API token from your hub's `/admin/tokens` panel. The AI needs both.

---

## Copy this:

```markdown
I want to build a custom front-end for my Parachute Vault. Hosted on
GitHub Pages, talks to my vault over HTTP. No Parachute installation
needed — just a static SPA in a GitHub repo I own.

## What I'll give you

- My vault's HTTP origin (e.g. `https://aaron-hub.fly.dev/vault/default`)
- An API token (`pvt_...`) with `vault:write` scope
- A description of what I look at most — projects, people, daily
  notes, etc. (You'll interview me.)

## Reference implementations

You can read these to see how the vault's HTTP API is shaped + how a
typical client structures itself:

- **Notes UI** — the canonical PWA, source at
  https://github.com/ParachuteComputer/parachute-surface/tree/main/packages/notes-ui
  — full CRUD, OAuth, PWA caching, multi-vault. Probably more than I
  need; useful as a reference.

- **Vault HTTP API reference** — the README in
  https://github.com/ParachuteComputer/parachute-vault — lists
  endpoints for notes (`/api/notes` — full-text search via the
  `?search=` query param), tags (`/api/tags`), graph
  (`/api/find-path`), attachments, and the per-vault MCP at
  `/mcp`. Wikilinks are inline `[[...]]` syntax in note content,
  not a separate endpoint.

Read whichever you need. I don't expect you to use Notes UI as a
starting point unless I tell you to — the framing here is "build me
something *new*, smaller, that fits my brain."

## Interview before building

Don't start coding yet. Ask me:

1. What do I look at most when I open a Parachute UI today?
   (Some operators want: an inbox of recent captures. A project
   dashboard. A weekly review pane. A graph view. A search bar. A
   today's daily-note view. Etc.)
2. Do I want a graph visualization? A list? A timeline? A board?
3. Single page that does it all, or multiple routes / tabs?
4. Anything that should be loud (e.g. unread captures from a runner
   job)? Anything that should be quiet?
5. Styling preferences — do I have a favorite reference site or
   look I want to mimic?

Once I've answered, propose a one-paragraph spec. Don't commit code
yet. Make sure I agree on what we're building before you build it.

## Build

Use a minimal stack — Vite + React + TypeScript is the cleanest
default, but if I prefer Svelte / Vue / vanilla, do that. No backend.
Static SPA only. All vault calls go to the operator's hub via fetch.

The auth pattern: the vault token is held in the SPA's local storage
after a one-time paste-in screen. Send it as
`Authorization: Bearer pvt_...` on every fetch. The vault's
`Access-Control-Allow-Origin: *` policy lets the cross-origin call
through.

For an MVP, use a single config screen ("paste your vault URL +
token") + the views I described. The Notes UI's OAuth flow is more
robust (DCR + per-session token) but is overkill for a personal
dashboard — token-paste is fine for the first cut.

## Deploy

GitHub Pages. Steps:

1. `gh repo create my-vault-ui --public`
2. Build to `dist/` with `vite build`
3. Use the `actions/deploy-pages` action to publish from `dist/`
4. Configure Pages → Source = GitHub Actions
5. Custom domain optional; default `username.github.io/my-vault-ui/`
   is fine for personal use

Write the deploy action for me. I'll commit + push.

## Don't:
- Hardcode my vault URL or token in source — keep them in the SPA's
  local storage with a paste-in screen
- Add npm dependencies I don't recognize unless you explain why
- Build for someone else's brain — this is mine
```

---

## What you get

A repo you own with a static SPA that hits your vault. Lives at `username.github.io/my-vault-ui/` (or your own domain). Updates by pushing to main.

Some operators stop at one. Some build five — a daily-capture view, a project dashboard, a graph explorer, a meeting-prep tool, a weekly-review board. Each is a separate small repo, all hitting the same vault. The vault doesn't care which UI calls it.

[← back to vault setup](/onboarding/vault-setup/)
