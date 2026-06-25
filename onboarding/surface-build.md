---
layout: post.njk
title: "Starter prompt — build a custom UI for your vault"
description: "Paste this into Claude Code (or your editor's AI). It builds a static SPA on the surface SDK (@openparachute/surface-client + surface-render) against a local dev server, then deploys the built output to GitHub Pages — signing in to your vault via your hub's OAuth."
permalink: /onboarding/surface-build/
date: 2026-05-26T12:00:00
---

A custom front-end for *your* vault, designed to surface what *you* actually look at. Built by an AI in your editor — no framework lock-in, no Parachute approval needed. Lives on GitHub Pages or any static host.

This is the second of two starter prompts. The first ([set up your vault](/onboarding/vault-setup/)) is for figuring out what's in your vault. This one is for figuring out how you want to see it.

**Build this one in your editor, not in chat.** A surface runs in a *browser* — it needs a real OAuth redirect to your hub and back, a local dev server, and a CORS origin your hub trusts. None of that exists in an MCP/chat session (no browser, no redirect, no dev server). So paste this into **Claude Code** (or Cursor, Zed, Codex — any AI that works in your editor against a local dev server), not into a chat-only client. The AI builds and iterates against `vite`/`bun dev` and you sign in through the browser there.

**Before you paste**: have a vault running with some content in it (even just the seeded *Getting Started* note works). You usually don't need to look up your hub URL or vault name — once your hub is exposed, the vault **states its own coordinates** (hub origin, REST base, MCP base) via `vault-info`, so the AI reads them rather than ask (on a purely-local hub it'll ask you once). No token to mint either — the app signs you in through your hub's standard OAuth flow and you approve it once on a consent screen.

---

## Copy this:

```markdown
I want to build a custom front-end for my Parachute Vault. A static
SPA in a GitHub repo I own, talking to my vault over HTTP. No Parachute
installation needed.

## Build this in my editor, not from a chat/MCP session

A surface runs in a *browser*: it needs a real OAuth round-trip (a
redirect to my hub's consent screen and back), a local dev server, and
a CORS origin my hub trusts. None of that exists in an MCP/chat session.
So build it here in my editor against a local dev server (`vite` /
`bun dev`) — that's where I sign in through the browser and we iterate.
Don't try to "run" the surface from a vault MCP session.

## Coordinates — read them, don't ask me

You don't need to ask me for my hub URL or vault name. My vault states
its own coordinates — hub origin, REST base, and MCP base — via
`vault-info` (and the instruction it sends on connect). If you have my
vault connected over MCP, call `vault-info` and read them. (If you're
working purely in the editor with no MCP connection, then ask me for
the hub origin and vault name once — but prefer reading them.)

## What I'll give you

- A description of what I look at most — projects, people, daily
  notes, etc. (You'll interview me.)

No API token — auth is the hub's standard OAuth, handled by the
client library below. I'll approve the app once on my hub's consent
screen the first time I sign in.

## Use the surface SDK — don't hand-roll the plumbing

Two npm packages cover everything generic. Read their READMEs before
writing code; import, don't reimplement:

- **`@openparachute/surface-client`** — auth + data, framework-
  agnostic. `createVaultSurface({ clientName, hubUrl, vaultName,
  redirectUri })` handles OAuth (PKCE + dynamic client registration),
  token storage, and refresh, and hands back a typed `VaultClient`
  (`queryNotes`, `createNotes`, `updateNote`, `fetchAttachmentBlob`,
  `subscribe` for live-updating views over SSE).
  https://github.com/ParachuteComputer/parachute-surface/tree/main/packages/surface-client

- **`@openparachute/surface-render`** — React rendering primitives:
  `<NoteRenderer>` (format-dispatched), `<MarkdownView>` with
  `[[wikilink]]` resolution, `<VaultImage>`/`<VaultAudio>` for auth'd
  attachments, `useVaultFetchBlob(client)` for fetching attachments
  yourself, plus an importable base `styles.css`. Primitives, not an
  app shell — routing and layout stay mine. I supply three hooks:
  `resolve(target)` (map a `[[wikilink]]` to *my* route + note index —
  validate against my own index, never echo a raw vault string as an
  href), `linkComponent` (my router's `<Link>`), and `fetchBlob`.
  https://github.com/ParachuteComputer/parachute-surface/tree/main/packages/surface-render

  This is the fast path and what you should reach for. *Only* if I
  need `[[wikilink]]` resolution that surface-render can't express —
  e.g. resolving against a custom client-side entity index with
  in-app routing — render with `react-markdown` + a small `components`
  map instead, and keep using the client's `fetchAttachmentBlob` for
  auth'd attachments. Ask me before going that route.

Other references if you need them: the full vault HTTP API is
documented in https://github.com/ParachuteComputer/parachute-vault
(docs/HTTP_API.md), and Notes — the canonical full-featured PWA — is
at packages/notes-ui in the parachute-surface repo. Don't use Notes
as a starting point unless I say so — the framing here is "build me
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
   job)? Anything that should be quiet? Anything that should update
   live (`subscribe` makes that cheap)?
5. Styling preferences — do I have a favorite reference site or
   look I want to mimic?

Once I've answered, propose a one-paragraph spec. Don't commit code
yet. Make sure I agree on what we're building before you build it.

## Build

Vite + React + TypeScript (surface-render is React; the data layer
works anywhere). No backend — static SPA only. Develop against a local
dev server (`vite` / `bun dev`); that's where the OAuth redirect and
sign-in actually happen.

Wiring:
- One `createVaultSurface` call at module scope. `clientName` is the
  only required option; pass `hubUrl` + `vaultName` from `vault-info`'s
  coordinates (don't make me type them). Set `redirectUri` so
  it's correct on the deployed path, e.g.
  `` `${location.origin}${import.meta.env.BASE_URL}oauth/callback` ``
  (GitHub Pages serves project sites under `/repo-name/` — set Vite's
  `base` to match).
- An `/oauth/callback` route that calls `surface.handleCallback()`
  then redirects home.
- `surface.getClient()` → a ready `VaultClient`, or null → show a
  "Sign in" button that calls `surface.login()`.
- Render note content through `<NoteRenderer>` / `<MarkdownView>`,
  attachments through `<VaultImage>` / `<VaultAudio>`.
- For anything where staleness would show, use
  `client.subscribe(query, handlers)` (live-query over SSE) instead of
  polling — it self-corrects on reconnect and carries auth in the
  header. A free "thinking…"/live indicator falls out of subscribing
  to a query and reading note `metadata.status` — no extra writes.
- Branch on the typed error classes the client throws
  (`VaultAuthError`, `VaultPermissionError`, `VaultConflictError`,
  `VaultNotFoundError`, `VaultUnreachableError`) — don't string-match
  HTTP status. A `400 invalid_grant` on refresh is terminal: clear
  tokens and re-auth, don't loop (the client handles this for you).

## Deploy — push the built output, no Actions workflow

This is a static build: `vite build` produces a `dist/` folder of plain
HTML/JS/CSS that hosts **anywhere static** — GitHub Pages, Cloudflare
Pages, Netlify, an S3 bucket. Nothing server-side.

**Deploy by pushing the *built output* to a branch — do NOT write a
GitHub Actions workflow.** Some AI/agent GitHub integrations can't push
files under `.github/workflows/` (it's a permission a lot of tokens lack),
so a `deploy.yml`-based flow silently fails for many people. Pushing the
built bytes themselves always works. For GitHub Pages, either path:

1. `gh repo create my-vault-ui --public`
2. Build to `dist/` with `vite build` (set Vite's `base` to
   `/my-vault-ui/` so asset paths resolve under the project-site
   subpath).
3. Publish the built `dist/` — pick one:
   - **`gh-pages` branch:** push the contents of `dist/` to a `gh-pages`
     branch (e.g. with the `gh-pages` npm package, or
     `git subtree push --prefix dist origin gh-pages`), then set
     Pages → Source = **Deploy from a branch** → `gh-pages` / root.
   - **`docs/` folder on main:** build into `docs/`, commit it, and set
     Pages → Source = **Deploy from a branch** → `main` / `docs`.
4. Custom domain optional; default `username.github.io/my-vault-ui/`
   is fine for personal use. (Hosting elsewhere? Cloudflare Pages /
   Netlify just want the `dist/` output and a build command — same
   bytes.)

Set up the build + the push-to-branch step for me (a small npm script
is fine — e.g. `"deploy": "vite build && gh-pages -d dist"`). I'll
commit + push.

## Don't:
- Hand-roll OAuth, a vault REST client, token storage, or markdown /
  wikilink rendering — the two packages above own that layer
- Hardcode tokens anywhere (there are none in this flow; if I ever
  paste one, stop me)
- Add npm dependencies I don't recognize unless you explain why
- Build for someone else's brain — this is mine
```

---

## What you get

A repo you own with a static SPA that signs in to your vault through your hub. Lives at `username.github.io/my-vault-ui/` (or your own domain — and it hosts on Cloudflare Pages or Netlify just as well). Updates by rebuilding and re-publishing the `dist/` output (one `npm run deploy`).

Some operators stop at one. Some build five — a daily-capture view, a project dashboard, a graph explorer, a meeting-prep tool, a weekly-review board. Each is a separate small repo, all hitting the same vault. The vault doesn't care which UI calls it.

[← back to vault setup](/onboarding/vault-setup/)
