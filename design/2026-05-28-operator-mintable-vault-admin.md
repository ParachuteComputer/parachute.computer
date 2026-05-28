---
title: "Capability-attenuation auth (operator-mintable vault:admin → general attenuation)"
description: "Hub's mint-token + revoke-token endpoints learn one rule: any bearer may mint OR revoke a token whose authority is a subset of its own. Began as the narrow host:admin → vault:<name>:admin de-escalation that supplied the missing admin-scope replacement for the pvt_* retirement (vault#282); generalized into capability attenuation, which lets vault drop pvt_* entirely and become a pure hub resource-server."
---
# Capability-attenuation auth

**Date:** 2026-05-28
**Status:** LANDED (Aaron approved + merged, 2026-05-28). The full arc is merged to `main` across hub and vault; only the breaking pvt_* DROP (vault#282) remains, gated on the human. Began as Option 1 of three considered ("operator-mintable vault:admin") and generalized to capability attenuation.

> **What this doc is.** It opens with the original narrow decision — *operator-mintable `vault:<name>:admin`* (PR-A) — because that's where the design started and the security argument for de-escalation is clearest there. §"Generalization: capability attenuation" then records how PR-A turned out to be the first instance of a single broader rule, and what shipped on top of it. Read top-to-bottom for the history; jump to that section for the landed model.

**Companions:**
- [`2026-04-20-hub-as-portal-oauth-and-service-catalog.md`](./2026-04-20-hub-as-portal-oauth-and-service-catalog.md) — hub-as-issuer, scopes per service, the foundation this builds on.
- [`../../parachute-patterns/research/auth-architecture-shape.md`](../../parachute-patterns/research/auth-architecture-shape.md) §11 — the AS/RS convergence decision and the pvt_* retirement arc this slots into (§11.6 records this decision as the admin-scope replacement).
- vault#282 — pvt_* Phase-6 hard removal at vault 0.6.0. The DROP this arc clears the runway for; the only remaining step, gated on the human.
- [`../../parachute-patterns/patterns/tag-scoped-tokens.md`](../../parachute-patterns/patterns/tag-scoped-tokens.md) — tag-scoping now rides the hub-JWT `permissions.scoped_tags` claim (C0).
- [`../../parachute-patterns/migrations/2026-05-28-operator-mintable-vault-admin.md`](../../parachute-patterns/migrations/2026-05-28-operator-mintable-vault-admin.md) — the propagation checklist (the landed PR map).

## Context / Problem

An operator who wants a `vault:<name>:admin` bearer — to point an MCP client at a vault that manages schema and tokens, or to drive the vault admin SPA's token-mint page — has no canonical headless path today.

Hub's `POST /api/auth/mint-token` refuses `vault:<name>:admin`. The endpoint runs a *non-requestable-scope* guard: a fixed set of high-privilege scopes that the public mint surface won't hand out, vault-admin among them. The reasoning was sound at the time — vault-admin is the keys-to-the-vault scope, and the public OAuth flow shouldn't grant it on request.

The fallout: `parachute vault mcp-install`, when the operator asks for an admin-capable MCP connection, can't get an admin JWT from hub. It falls back to minting a deprecated `pvt_*` opaque token (the vault-DB-resident, hash-stored, no-expiry legacy bearer). The vault admin SPA's tokens page is in the same bind — its only admin-scope source is pvt_*.

That fallback is a dead end. pvt_* is slated for hard removal at vault 0.6.0 (vault#282 — the CLI currently cites the wrong issue, #288, in three places). Once vault stops validating pvt_*, both consumers break with no replacement. We need a headless, hub-minted source of `vault:<name>:admin` before pvt_* goes away.

## Decision

Allow `POST /api/auth/mint-token` to mint `vault:<name>:admin` **when, and only when, the calling bearer carries `parachute:host:admin`.**

A `parachute:host:auth`-only bearer still cannot mint vault-admin — no change there. The guard relaxes for exactly one caller class: the box-wide host admin.

One hub change unlocks two consumers:

1. **`parachute vault mcp-install`** (headless CLI) reads `~/.parachute/operator.token` — which carries the `admin` scope-set including `parachute:host:admin` — and POSTs to `/api/auth/mint-token` with `scope=vault:<name>:admin`. This replaces the pvt_* fallback.
2. **Vault admin SPA tokens page** (browser) holds a session cookie and walks the existing session → host-admin-token → mint-token chain to land a durable hub JWT. No new SPA-specific endpoint.

## Why de-escalation is safe (the security argument)

`parachute:host:admin` is the box-wide administration scope. It already implies administrative control of **every vault on the hub** — schema, tokens, config, the lot. A holder of `parachute:host:admin` can already do everything a `vault:<name>:admin` token can do, and more, against any vault.

Minting a *vault-pinned* admin token from a host-admin bearer is therefore a privilege **reduction**: the resulting token is scoped to one named vault and to vault-admin operations only. It can do strictly less than the bearer that authorized it. There is no path by which holding `parachute:host:admin` and minting `vault:<name>:admin` grants the caller anything they didn't already have.

That makes the guard relaxation principled rather than a loosening. The non-requestable-scope guard exists to stop the *public OAuth flow* — arbitrary consented clients — from requesting vault-admin. A host-admin bearer is not that population. The guard stays fully in force for every caller below host-admin.

This is the same shape as a root user minting a scoped service account: the scoped credential is safer to hand out and circulate than the root credential it descends from, so producing it from root is a de-escalation worth supporting.

## The two consumer paths

### Path 1 — headless CLI (`parachute vault mcp-install`)

Operator runs mcp-install and asks for an admin-capable connection. The CLI reads the on-box operator token and mints directly:

```
POST /api/auth/mint-token
Authorization: Bearer <operator.token>        # carries parachute:host:admin
Content-Type: application/json

{ "scope": "vault:default:admin" }
```

```
200 OK
{
  "jti": "<token id — the handle for later revocation>",
  "token": "<hub-signed JWT, aud=vault.default, scope=vault:default:admin>",
  "expires_at": "<ISO-8601 expiry>",           # 90-day default TTL (durable; right for MCP configs), 365-day max
  "scope": "vault:default:admin"
  // "permissions": { ... }                     # present only when the mint request carried a permissions object (e.g. scoped_tags)
}
```

> **Response shape (corrected — audit R8).** The mint-token success body is `{ jti, token, expires_at, scope, permissions? }` — verified against `parachute-hub/src/api-mint-token.ts`. It is **not** the OAuth-token-endpoint `{ access_token, token_type, expires_in }` shape; mint-token is a first-party registry-minting endpoint, not `/oauth/token`. The JWT itself is in `token`; `jti` is the revocation handle; `expires_at` is an absolute timestamp, not a relative `expires_in`.

The CLI writes the JWT (the `token` field) into the MCP client config. No pvt_* row created; nothing vault-DB-resident.

### Path 2 — browser (vault admin SPA tokens page)

The SPA has a session cookie, not an operator token. It walks the existing chain — no new endpoint:

```
GET /admin/host-admin-token                    # session-cookie-gated, first-admin-gated, 10-min TTL
  → { access_token: "<JWT scope=parachute:host:admin parachute:host:auth>" }

POST /api/auth/mint-token
Authorization: Bearer <the 10-min host-admin JWT>
{ "scope": "vault:default:admin" }
  → { jti, token: "<durable vault-admin JWT>", expires_at, scope: "vault:default:admin" }
```

(`/admin/host-admin-token` is the OAuth-shaped step-up endpoint, so its body is `{ access_token }`; `/api/auth/mint-token` is the registry-mint endpoint, so its body is `{ jti, token, expires_at, scope, permissions? }`. Two different endpoints, two different — and both correct — response shapes.)

The short-lived host-admin JWT is the bridge: the session cookie isn't a bearer the mint endpoint accepts, but `/admin/host-admin-token` already converts a session into a 10-minute `parachute:host:admin` bearer for exactly this kind of step-up. mint-token then de-escalates it to the durable vault-admin token the operator keeps.

## Correctness

Verified against the landed hub + vault code:

- **Audience.** `inferAudience(["vault:default:admin"])` → `vault.default` (`jwt-audience.ts`). This matches vault's strict audience check, so the minted JWT validates at the vault resource server with no extra plumbing.
- **`vault_scope` claim.** `vault_scope: []` is the "no per-user restriction" sentinel (scope-guard `scope.ts`) — it would be accepted, since the scope string plus audience are the primary gate. The implementation **pins `vault_scope: [<name>]`** for admin mints, matching the canonical session-path mint (`admin-vault-admin-token.ts`). Defense-in-depth + least privilege: the token is explicit about the one vault it administers rather than relying on the sentinel.
- **TTL.** Default mint-token TTL is 90 days (durable — the right lifetime for an MCP config that lives in a client's settings), max 365 days. Durable-but-revocable: these tokens land in hub's token registry and ride the revocation list (auth-architecture-shape §11.6), so a leaked admin token can still be killed in <60s.

## Relationship to vault#282

vault#282 is the pvt_* Phase-6 retirement: at vault 0.6.0, vault rejects pvt_* with 401 and deletes the validation path, becoming a pure hub resource-server (validate hub-signed JWTs, nothing else). That's the endpoint of the AS/RS convergence in auth-architecture-shape §11 — one issuer (hub), one token shape (hub JWT).

vault#282 has a precondition that wasn't met: **every credential pvt_* used to provide needs a hub-minted replacement first.** Read, write, and tag-scoped tokens already have hub-JWT equivalents through the normal mint path. Vault-admin was the gap — the one scope the mint endpoint refused, leaving pvt_* as the only source. This decision supplies that replacement, so the SPA tokens page and mcp-install can drop pvt_* entirely and vault#282 can land without stranding the admin use case.

(The CLI's `#288` citations were wrong — the retirement issue is #282. vault#397 fixed the three references.)

## Generalization: capability attenuation

PR-A's `host:admin → vault:<name>:admin` carve-out turned out to be the **first instance of one general rule**, not a special case:

> **Any bearer may mint OR revoke a token whose authority is a subset of its own.**

This is the principled core. PR-A's de-escalation argument (a vault-pinned admin descends from box-wide admin, so producing it grants nothing new) is exactly the subset relation; it generalizes to every level of the scope lattice. Once stated this way, the apparent tension between "clean auth — vault is a pure resource-server" and "keep the rich token features (manage-token, tag-scoping)" dissolves: vault stops *issuing* its own tokens entirely and instead **proxies** mint/revoke to hub, which applies the one attenuation rule. pvt_* can then be dropped **entirely**, not partially.

### The one rule, in code

Implemented as two pure functions in `parachute-hub/src/scope-attenuation.ts`, shared by both the mint and revoke handlers:

- **`hasMintingAuthority(bearerScopes)`** — the cheap entry gate: does the bearer hold *any* authority at all (`host:auth`, `host:admin`, or some `vault:<*>:admin`)? A bearer with none can neither mint nor revoke via attenuation, so both endpoints 403 it before per-scope work.
- **`canGrant(bearerScopes, requestedScope)`** — could a bearer holding `bearerScopes` mint a token carrying `requestedScope`? True under one of three rules:
  1. `requestedScope` is requestable **and** the bearer holds `parachute:host:auth` — the operator-admin path mints any normal scope.
  2. `requestedScope` is `vault:<N>:admin` **and** the bearer holds `parachute:host:admin` — **this is PR-A**, the box admin de-escalating to a vault-pinned admin.
  3. `requestedScope` is `vault:<N>:<verb>` **and** the bearer holds `vault:<N>:admin` for the **same** `<N>` — a vault admin minting same-vault subtokens (`read`/`write`/`admin`).

The scope lattice the rule walks: `parachute:host:admin` → `vault:<N>:admin` → `vault:<N>:{read,write,admin}`, with tag-scoping (`permissions.scoped_tags`) as a *further* attenuation on any of those (a minted token's tag-allowlist must be a subset of the minter's — enforced on the mint side and read fail-closed on the vault side, see C0 below).

### Symmetric revoke

`canGrant` is the single source of truth for **both** directions. mint uses it to gate what a request may *issue*; revoke uses it to gate what a request may *tear down* — a target jti is revocable by a non-`host:auth` bearer iff **every** recorded scope on that token is `canGrant`-able by the bearer (you may revoke exactly what you could have minted). A mere `vault:<N>:admin` bearer can therefore neither mint nor revoke cross-vault or host-authority tokens. (hub#454.)

### Reject malformed vault-shaped scopes (hub#455)

A defensive-hygiene fold: mint-token rejects scope strings that *look* vault-shaped but are malformed (e.g. wrong segment count) rather than letting them slip past the attenuation check. Keeps the `vault:<N>:<verb>` grammar the one true shape the guard reasons about.

### manage-token becomes a hub-mint proxy

The `manage-token` MCP tool (vault#405) no longer issues local `pvt_*` rows. It forwards the MCP caller's `vault:<N>:admin` bearer to hub's `/api/auth/mint-token`; rule 3 lets that bearer mint same-vault subtokens, and revoke/list route to hub's registry. The proxy is **session-pinned** — the minting ledger is tied to the MCP session so the tool can list/revoke what it minted. This is what lets vault retain the token-management *feature* while ceasing to be a token *issuer*.

### C0 — tag-scoping rides the hub JWT (vault#403, vault#407)

The prerequisite that unblocked the SPA + manage-token migrations: vault now reads tag-scoping from the hub JWT's `permissions.scoped_tags` claim rather than from a vault-DB `tokens` row. `@openparachute/scope-guard` (0.4.0-rc.2, hub#453) stops stripping `permissions` and surfaces it on `HubJwtClaims`; vault's `authenticateHubJwt` maps `permissions.scoped_tags` into `AuthResult.scoped_tags` (was hard-coded `null`). The mapping **fails closed**: a present-but-malformed `scoped_tags` (non-array, empty array, non-string members) throws and the request is rejected (401) rather than coerced to unscoped — coercion would *widen* a token meant to be narrowed. vault#407 closed a bypass where the raw `/api/storage/<date>/<file>` attachment-binary endpoint served bytes by filesystem path without tag-scope context; it's now gated behind the same `noteWithinTagScope` check as every other note-keyed surface.

## The decision Aaron locked (2026-05-28)

- **Hub is a hard requirement for granular auth.** Running Parachute modules requires hub; vault is always hub-fronted.
- **Granular per-token auth is a hub-minted capability** — minted via capability attenuation, validated by vault as a pure resource-server.
- **Standalone-no-hub keeps only the coarse secrets** — `VAULT_AUTH_TOKEN` / `vault.yaml`. No granular per-token auth without a hub.

This is what dissolves the "clean auth vs keep features" tension: features live on, but as hub-minted capabilities, not vault-issued tokens. vault#282 amends from "delete the pvt_* validation path" to "vault is a pure RS; granular auth is hub-minted via attenuation."

## Verified

- **Adversarial security audit** of the landed arc: **5 findings, 0 P0/P1.** The 2 remaining P2s (a REST `pvt_*` launder path and a `pvt_*` persistence surface) are **closed by the pending DROP** (vault#282) — they exist only because pvt_* still exists.
- **Live end-to-end smoke** on the real deploy confirmed mint **and** revoke attenuation (`canGrant` rules 1–3 + symmetric revoke) and vault auth (hub-JWT validation + `permissions.scoped_tags` enforcement) work against the running stack, not just in unit tests.

## Implementation plan (LANDED)

The arc shipped as the PRs below (all merged to `main`); only DROP remains, gated on the human. Full PR map + checklist: [`../../parachute-patterns/migrations/2026-05-28-operator-mintable-vault-admin.md`](../../parachute-patterns/migrations/2026-05-28-operator-mintable-vault-admin.md).

- **Hub PR-A (hub#449)** — `api-mint-token.ts` exempts `vault:<name>:admin` from the non-requestable guard when the bearer carries `parachute:host:admin`; exports `isVaultAdminScope` from `scope-explanations.ts`; pins `vault_scope: [<name>]` for admin mints.
- **Hub ATTEN (hub#452)** — generalizes the guard into `canGrant` / `hasMintingAuthority` (`scope-attenuation.ts`): rule 3 lets a `vault:<N>:admin` bearer mint same-vault subtokens. Subsumes PR-A.
- **scope-guard (hub#453)** — 0.4.0-rc.2 surfaces the `permissions` claim on `HubJwtClaims` (published); the prerequisite for C0.
- **Hub revoke attenuation (hub#454)** — `api-revoke-token.ts` revokes via the same `canGrant` rule (revoke what you could mint).
- **Hub malformed-scope reject (hub#455)** — mint-token rejects malformed vault-shaped scope strings.
- **Vault PR-B (vault#397)** — `mcp-install-interactive.ts` admin → hub-mint (was legacy-pat); `cli.ts` removes the `verb==="admin"` pre-flight reject; fixes `#288`→`#282` citations.
- **Vault C0 (vault#403, vault#407)** — vault enforces tag-scoping from `permissions.scoped_tags` (fail-closed on malformed); raw `/api/storage` reads tag-scope-gated.
- **Vault MGT (vault#405)** — `manage-token` MCP → hub-mint proxy with session-pinned ledger.
- **Vault SPA (vault#406)** — admin SPA tokens page mints hub JWTs via the session → host-admin-token → mint-token chain; list/revoke via hub registry.
- **DROP (vault#282, pending human go)** — remove pvt_* issuance + validation entirely; vault becomes a pure resource-server.
- **Docs** — install / token docs stop recommending pvt_*; recommend `parachute auth mint-token` and the mcp-install hub-mint path.

## Alternatives considered

- **Dedicated SPA endpoint (`POST /admin/vault-admin-token`).** Mirror `/admin/host-admin-token` but for vault-admin. Rejected: it's a second session-gated mint surface doing what mint-token already does once the guard is relaxed, and it doesn't help the headless CLI at all (no session cookie there). The guard refinement serves both consumers with one change; a dedicated endpoint serves one and duplicates logic.
- **Guard refinement (chosen).** One conditional in the existing mint path. Reuses mint-token's audience inference, token-registry insertion, and revocation-list participation for free. Both consumers — CLI with operator.token, SPA via the host-admin-token bridge — hit the same code path. Smallest change, widest reach, no new surface to secure.
- **Device-flow / consent step for vault-admin.** Run the public OAuth flow with an interactive consent for the admin scope. Rejected for the headless case: mcp-install is non-interactive on the operator box, and forcing a browser consent for a credential the operator already implicitly holds (via host-admin) is friction without a security gain — it's de-escalation, the operator is already the box admin.
- **Refuse from the CLI, document pvt_* as the admin path.** Keep the guard, keep mcp-install on pvt_* for admin, defer. Rejected: pvt_* is being removed at vault#282; documenting a path that's about to 401 is a worse position than today.

## Resolved questions

- **~~Tag-scoped tokens don't yet ride in hub JWTs.~~ RESOLVED by C0 (vault#403).** The original open question feared a gap: pvt_* could carry a tag-allowlist (`vault:default:write` *and* limited to `tag:project-x`) but hub-minted JWTs expressed only scope + audience + `vault_scope`. That gap is **closed** — the `permissions.scoped_tags` claim (proposed in auth-architecture-shape §11.3) is now the live mechanism. scope-guard (hub#453) surfaces `permissions` on `HubJwtClaims`; vault (vault#403) reads `permissions.scoped_tags` into `AuthResult.scoped_tags` and enforces it fail-closed; vault#407 extended the gate to raw `/api/storage` attachment reads. Tag-constrained tokens have a hub-JWT home, so pvt_* removal at vault#282 strands nothing on the tag-scope axis.
