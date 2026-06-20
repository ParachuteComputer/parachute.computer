# Surfaces as least-privilege vault bridges

**Status:** the core primitives are BUILT (see "What works today"); this doc names
the model, the patterns, the operator flow, and the roadmap. Companion to the
P1–P11 primitive spec (`parachute-surface/design/2026-06-10-surface-runtime-primitives.md`,
in the surface repo) and
[`2026-05-21-parachute-surface-design.md`](./2026-05-21-parachute-surface-design.md)
(the host shape). Written 2026-06-19 alongside the first two backed surfaces —
`meeting-ingest` (write) and `meeting-mcp` (read).

> **Tag convention:** the namespaced `capture/meeting` (consistent with the vault's
> `capture/text` / `capture/voice`) is the intended tag for ingested meetings, and
> what `meeting-mcp` reads by default. NOTE the current divergence:
> `meeting-ingest` still defaults to the bare `meeting` tag, so the two reference
> surfaces must be aligned via each surface's `config.tag` until the defaults are
> reconciled (tracked in `parachute-surface`). Examples below use `capture/meeting`.
>
> **`#`-prefix footgun:** the vault stores tags **literally** — there is no `#`
> normalization. Write `capture/meeting`, NOT `#capture/meeting`; the `#` is a
> display convention only, and a `#`-prefixed write lands in a *separate* tag the
> read surface (querying `capture/meeting`) will never see. Verified the hard way.

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
  transcripts → `capture/meeting`) and can touch nothing else.
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
| Triggers / Connections | vault `note.created/updated (filter)` → a sink module action (today: deliver a chat message / reload a def; "react to a domain note" is agent#120) | hub Connections engine |

The line: a surface owns **domain logic, route shapes, projection definitions, and
config**. The kit/host own **actor resolution, the credential custody, the
deny-by-default routing, rate-limit, CSRF, and trust-layer derivation**. A backed
surface is meant to be *thin*: meeting-ingest's `createBackend` *wiring* is ~40
lines (the domain logic — HMAC verify, the GraphQL fetch, the transform — lives in
its own modules), because the kit does the dangerous parts.

## The trust + credential model (and the proof)

- The host custodies **one** vault credential per surface and hands the backend a
  `ScopedVaultClient` — a capability handle whose token lives in `#private` fields
  with no accessor. The surface code *cannot* read the credential or widen its own
  scope.
- The credential is **tag-scoped** (`scoped_tags`) and the **vault enforces it**.
  Verified 2026-06-19 against the live vault with a `vault:default:write` token
  whose `permissions.scoped_tags` is `["capture/meeting"]`:
  - write a note tagged `capture/meeting` → **201**
  - write a note tagged anything else → **403 `tag_scope_violation`** (*"This token
    is restricted to tags: capture/meeting. The note (or write) is outside that
    scope."*)
- And the full chain end-to-end: that scoped write → the `meeting-mcp` P9 read
  surface's `recent-meetings` returned the note **shaped** to `{id, title, date,
  summary}` (no tags, no path, no raw note) over both REST and the MCP `tools/call`.
- So "this surface can write only `capture/meeting`" is a real, enforced property —
  not a convention. A public projection over `capture/meeting` (read, tag-scoped)
  exposes only those notes, and only the fields its `shape` function copies.

## The patterns

### 1. Ingest (+ a future trigger fan-out) — meeting-ingest
A `public`, HMAC-verified webhook writes one tag:
```
Fireflies → POST /surface/meeting-ingest/api/webhook/fireflies   (public, HMAC)
          → ctx.vault.createNote(capture/meeting)                (write scoped to that tag)
```
The natural next step is "wake an agent on each new meeting," and the right *shape*
is a **vault trigger**, not surface code — so the surface stays scoped to one
write-tag and the fan-out is a separate connection. **Status (corrected
2026-06-19): not wired yet.** The trigger *engine* exists (vault triggers + the hub
Connections engine), but the agent side has no action that consumes a *domain*
note: `message.deliver` accepts only inbound **message** notes (it requires
`metadata.channel`), so a `capture/meeting` note can't drive a turn. Waking an
agent from a domain note needs a new agent "react to a note" action
(parachute-agent#120). So today: ingest + tag-scoped write is **live**; the agent
fan-out is a **roadmap** item, not a click.

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

## Operator provisioning (what's automatic, what's a click)

Provisioning is cookie-gated to the portal operator (no headless/CLI path), but
it's mostly lighter than "approve a pending item." **Connections are *created* in
the hub Connections *builder*, not approved** — the Connections "Approve" button
appears ONLY for the narrow credential-*renewal* claim flow (a module re-presenting
a credential it already holds; surface#113), never for a new surface or trigger. So
**an empty Connections view with nothing wired is the correct, expected state** —
you *build* there, you don't wait for an approval that won't come. For a backed
surface:

1. **Install** the surface (admin SPA `inspect → stage → install`, or place
   `meta.json` + `dist/` + `server/index.bundle.js` in
   `~/.parachute/surface/uis/<name>/` and restart surface).
2. **Vault credential:**
   - *Read surface, single vault* → **nothing to do.** The host **auto-binds** a
     least-privilege read credential (`credential-store.ts`) — no click, no
     Connections entry. (This is why `meeting-mcp` read live with an empty
     Connections view.)
   - *Write surface* → **create** a credential connection in the builder (a write
     credential *requires* a non-empty tag scope — vault-wide write is refused),
     then **bind it in the surface's OWN admin page (`CredentialPanel`)**, not the
     hub Connections view. Binding ambiguity (multiple matching credentials)
     surfaces only there. Until a credential resolves, the static bundle serves but
     `/api/*` gates with a host `credential_pending` 503 (distinct from an app-layer
     `not_configured` 503 — e.g. a missing webhook secret in `config.json`).
3. **Fan-out trigger** (optional) → **create** a `note.created (filter <tag>) →
   agent <action>` connection in the builder. NOTE: the agent consumer isn't built
   yet (Pattern 1 / agent#120) — the engine is ready, the agent action isn't.
4. **Provider surfaces** → set `config.json` (0600) — e.g. the Fireflies API key +
   webhook secret.

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

**Roadmap** (`parachute-surface` issues, + `parachute-agent`):
- **agent#120** — an agent "react to a domain note" action: the missing consumer
  that makes the ingest→agent fan-out (Pattern 1) actually work. The trigger engine
  is ready; this is the agent side.
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

The **operator-builds-their-own-surfaces** version is mostly *working-today-with-
provisioning*: tag-scoped **ingest** (write), **public write-only intake**, and the
**custom end-user MCP** (proven end-to-end on real data) are compositions of
primitives that exist. The one piece that *looks* done but isn't: the
**ingest→agent fan-out** — the trigger engine is ready but the agent has no action
to consume a domain note (agent#120). The **anyone-publishes-a-surface** version
needs two more things, both scoped above: authoring/distribution DX (#126) and
per-surface process isolation for untrusted code (#127). None is invented from
scratch.
