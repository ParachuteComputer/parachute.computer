# Surfaces as least-privilege vault bridges

**Status:** the core primitives are BUILT (see "What works today"); this doc names
the model, the patterns, the operator flow, and the roadmap. Companion to
[`2026-06-10-surface-runtime-primitives.md`](./2026-06-10-surface-runtime-primitives.md)
(the P1–P11 primitive spec) and
[`2026-05-21-parachute-surface-design.md`](./2026-05-21-parachute-surface-design.md)
(the host shape). Written 2026-06-19 alongside the first two backed surfaces —
`meeting-ingest` (write) and `meeting-mcp` (read).

## The thesis

A **surface** is a least-privilege bridge between the outside world and a Parachute
vault. The point isn't "an app that has a vault token" — it's the opposite: the
surface-server layer *is the boundary*, so an outside actor (a webhook, a browser
visitor, an MCP client) **never holds a vault credential at all**. They reach
exactly the routes the surface declares, and the surface's backend reaches exactly
the vault tags its credential is scoped to. Everything else is denied by
construction.

That single idea unlocks a family of things people actually want:

- **Ingest** — a webhook drops external data into one tag (e.g. Read.ai/Fireflies
  transcripts → `#capture/meeting`) and can touch nothing else.
- **Public write-only intake** — a feedback form anyone can submit to, writing one
  tag, reading nothing. No blind token that could read or rewrite the vault.
- **Custom end-user MCP** — a curated, domain-vocabulary MCP/REST over a slice of a
  vault (e.g. a city's council-meeting notes surfaced as "upcoming meetings" /
  "search by topic"), exposing only the fields the author shapes — never raw notes.
- **Per-surface apps** — a surface with its own auth layer and its own operational
  state, bridged into a vault, that a third party could eventually author + run.

## The primitives (a deliberately small set)

A backed surface composes these — nothing more:

| Primitive | What it is | Owned by |
|---|---|---|
| `createBackend(ctx)` | the factory the host calls once per mount; returns `{ fetch, websocket?, shutdown? }` | author writes; host calls |
| `ctx` (`SurfaceHostContext`) | the only doorway: `vault` (scoped client), `config`, `store`, `layer`/`clientIp`, `log`, `shutdownSignal` | host injects |
| Routes × 4 access kinds | `public` / `audience` / `operator` / `note` — deny-by-default; undeclared = 404 | surface-server kit |
| **Tag-scoped vault credential** | a `vault:<v>:read|write` credential narrowed to `scoped_tags`, host-custodied, **vault-enforced** | hub mints; vault enforces |
| **P9 projections** | `defineProjection` → one definition derives **both** a REST endpoint **and** an MCP tool; only `notes.map(shape)` leaves | surface-server kit |
| Audience auth | per-surface auth distinct from operator + vault (capabilities `cap_`, personal links `lnk_`) | surface-server kit |
| `ctx.store` | per-surface SQLite for *operational* state (caches, cursors) — knowledge lives in the vault | host |
| Triggers / Connections | vault `note.created/updated (filter)` → an action (e.g. wake an agent) — reactive fan-out | hub Connections engine |

The line: a surface owns **domain logic, route shapes, projection definitions, and
config**. The kit/host own **actor resolution, the credential custody, the
deny-by-default routing, rate-limit, CSRF, and trust-layer derivation**. A backed
surface is meant to be *thin* — meeting-ingest's whole gateway is ~30 lines.

## The trust + credential model (and the proof)

- The host custodies **one** vault credential per surface and hands the backend a
  `ScopedVaultClient` — a capability handle whose token lives in `#private` fields
  with no accessor. The surface code *cannot* read the credential or widen its own
  scope.
- The credential is **tag-scoped** (`scoped_tags`) and the **vault enforces it**.
  Verified 2026-06-19 against the live vault with a `vault:default:write` token
  scoped to `#capture/meeting`:
  - write a note tagged `#capture/meeting` → **201**
  - write a note tagged anything else → **403 `tag_scope_violation`**
    (*"This token is restricted to tags: #capture/meeting"*)
- So "this surface can write only `#capture/meeting`" is a real, enforced property —
  not a convention. A public projection over `#capture/meeting` (read, tag-scoped)
  can expose only those notes, and only the fields its `shape` function copies.

## The patterns

### 1. Ingest + trigger (meeting-ingest)
A `public`, HMAC-verified webhook writes one tag, then a **vault trigger** fans out:
```
Fireflies → POST /surface/meeting-ingest/api/webhook/fireflies   (public, HMAC)
          → ctx.vault.createNote(#capture/meeting)               (write scoped to that tag)
          → vault trigger: note.created (filter #capture/meeting)
          → hub Connections → agent message.deliver              (wake an agent)
```
Keep the downstream action a **trigger**, not surface code: the surface stays
scoped to one write-tag; the fan-out is a separate, operator-approved connection
(the same engine that drives reactive agent def-reload).

### 2. Public write-only intake (feedback)
A `public` POST route writing `#capture/feedback` on a tag-scoped credential. The
submitter never gets a token; deny-by-default means they can reach only that route;
the credential means it can write only that tag. Same primitives as #1, minus the
webhook signature, plus `public`.

### 3. Custom end-user MCP (meeting-mcp / the "boulder" pattern)
P9 projections over a read-scoped credential: declare `recent-meetings`,
`search-meetings`, `meeting(id)` once → get a public (or audience-gated) **MCP tool
set + REST** that speaks domain vocabulary. The `shape` function is the disclosure
boundary — raw notes never leave. This is how you give end-users (or their AI) a
friendly window into a vault slice (city-council meetings, a knowledge base) without
vault access.

## Operator provisioning (the clicks that aren't headless)

Installing a surface is in the operator's hands by design — provisioning a vault
credential or a trigger is an *approval*, so it's cookie-gated to the portal
operator (no CLI/headless path). For a backed surface:

1. **Install** the surface (admin SPA `inspect → stage → install`, or place its
   `meta.json` + `dist/` + `server/index.bundle.js` in `~/.parachute/surface/uis/<name>/`
   and restart surface).
2. **Approve its credential connection** — grant the surface `vault:<v>:read|write`
   **scoped to its tag(s)** (e.g. `#capture/meeting`). Until delivered, the static
   bundle serves but `/api/*` returns 503 (`not_configured`/pending-credential).
3. (Ingest) **Approve the fan-out connection** — `note.created (filter <tag>) →
   agent message.deliver` — if you want the downstream action.
4. (Provider surfaces) set the surface's `config.json` (0600) — e.g. the Fireflies
   API key + webhook secret.

Roadmap items #124/#125 below make steps 2–3 *declared by the surface* so install
offers them as one click instead of hand-wiring.

## What works today vs. what's next

**Built:** the host runtime (discovery, mounting, supervision, credential custody),
the deny-by-default gateway (4 access kinds, actor resolution, rate-limit, CSRF,
no-existence-oracle, the public conformance suite), **tag-scoped vault credentials
(vault-enforced)**, **P9 projections (REST + MCP from one definition)**, audience
auth (capabilities/links), `ctx.store`, and the Connections/trigger engine. Two
backed surfaces ship as references: `meeting-ingest` (write) and `meeting-mcp`
(read/MCP).

**Roadmap** (`parachute-surface` issues):
- **#124** — declare a surface's write-tag so the credential auto-scopes (ergonomics
  over the operator-set `scoped_tags`).
- **#125** — declare a post-write trigger/connection on a surface (one-click fan-out
  vs. separate provisioning).
- **#126** — `create-surface` scaffolding + authoring DX for third-party authors.
- **#127** — per-surface **process isolation** for untrusted backends (today they run
  in-process; the host quarantines but cannot sandbox — the blocker for a
  multi-tenant "anyone publishes a surface" model).
- **#128** — passwords/passkeys audience auth (v2; today it's capability/link-shaped).
- **#129** — a scoped **surface-admin MCP** so a parachute agent can update a surface
  (config get/set + status grantable to an agent; stage→operator-approved install
  for code). The trust gradient: safe config now, code/install gated until #127.

## How close is the vision?

The **operator-builds-their-own-surfaces** version — a feedback intake, a council-
meeting MCP, an ingest+trigger pipeline — is *working-today-with-provisioning*, not a
roadmap: every thread is a composition of primitives that exist. The
**anyone-publishes-a-surface** version needs exactly two things, both named and
scoped above: an authoring/distribution DX (#126) and per-surface process isolation
for untrusted code (#127). Neither is invented from scratch.
