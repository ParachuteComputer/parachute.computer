---
title: "Individual users and vault operations — self-serve backup, vault defaults, usage monitoring, invites, and the multi-user security sweep"
description: "Make Parachute work for individual (non-admin) users on a shared server. Today self-serve git backup is already AUTHORIZED — an assigned user holds vault:<name>:admin — but there is no UI, so the operator configures backup by hand per person. This doc designs the missing surfaces: a per-vault 'Back up this vault' page on the server-rendered /account/* family, internal-live-mirror as the default for new vaults with one-button GitHub linking, a read-scoped per-vault usage endpoint with hub aggregation, one-time invite links that provision an account + vault, an owner-vs-shared role distinction, and the prioritized security risk register that gates shipping invites to strangers on a shared box."
---
# Individual users and vault operations

**Date:** 2026-06-04
**Status:** Design proposal — informs the hub + vault code PR chain that follows. No code ships with this PR. Companion to the multi-user arc (hub#252) and the git-projection arc.

**Companions:**
- [`2026-05-20-multi-user-phase-1.md`](./2026-05-20-multi-user-phase-1.md) — the multi-user foundation (admin-creates-user, force-change-password, per-user vault assignment). This doc is the Phase 2 continuation: invite links, self-serve config, owner-vs-shared roles, usage — all the things that doc explicitly punted.
- [`2026-05-20-vault-as-git-projection.md`](./2026-05-20-vault-as-git-projection.md) — the mirror/backup system (presets, field mapping, "no mirror until enabled" default this doc changes).
- [`2026-04-20-hub-as-portal-oauth-and-service-catalog.md`](./2026-04-20-hub-as-portal-oauth-and-service-catalog.md) — hub-as-issuer OAuth (the substrate every scope claim rides on).
- [`2026-05-18-v06-deploy-architecture.md`](./2026-05-18-v06-deploy-architecture.md) — single-container hosted deploy (the disk-posture question for `default_mirror` on cloud).
- [`2026-06-01-hub-as-supervisor-unification.md`](./2026-06-01-hub-as-supervisor-unification.md) — hub-as-supervisor (where module reachability mediation would live if we decide to mediate).

> **Grounding note.** This doc is written against the real source at `main` across `parachute-hub`, `parachute-vault`, and `parachute-scribe`. Every file:line below was read by a 7-area research fan-out (account-surface, git-mirror-system, vault-creation-flow, user-auth-model, invites-onboarding, monitoring-usage, security-surface), not assumed. Recommendations Uni makes that need an Aaron call are tagged **Recommendation (Uni) — confirm**; the genuine product decisions are consolidated in §11.

---

## 1. The program

From Aaron, 2026-06-03 — make Parachute work for **individual (non-admin) users on a shared server**. Seven threads:

1. **Self-serve git backup.** Today setting up backup requires full admin; Aaron configures it manually per person. Let an assigned user back up their own vault.
2. **Vault creation sets up backup.** New vaults should **default to an internal live mirror** (local git history, no external dependency), with easy GitHub linking as an opt-in upgrade.
3. **Per-vault usage monitoring** — priority over caps. An operator running twenty vaults for twenty people needs to see disk consumption per vault. Flying blind today.
4. **One-time invite links.** Send someone a link → they create an account + a vault on this server. No admin-typed default password.
5. **Deep design of the `/account/` surface** — how an individual, vault-scoped user actually uses Parachute.
6. **Deeper passes on git-backup + GitHub flows + defaults.**
7. **A real security sweep** now that strangers get vault access on a shared box.

### The highest-leverage current-state fact

**Self-serve backup is already authorized.** Since 2026-05-30, an assigned user holds `vault:<name>:admin` on their vault — `vaultVerbsForRole("write")` returns `["read","write","admin"]` ([hub `users.ts:178-182`](#)), and every mirror route gates on exactly that scope ([vault `mirror-routes.ts:16-21`](#), [`routing.ts:470-663`](#)). A friend can already mint that token three ways: the OAuth consent flow, `POST /account/vault-token/<name>` ([`account-vault-token.ts`](#)), and `POST /api/auth/mint-token` (attenuating an already-held vault-admin token).

So the authorization gap is **closed**. The only thing missing is **UI** — and one specific gate. The vault's mirror config lives in the vault's own admin SPA (`VaultMirror.tsx`), which bootstraps its bearer from hub `GET /admin/vault-admin-token/<name>` — and **that** endpoint is still hard-gated on `isFirstAdmin` ([`admin-vault-admin-token.ts:70`](#)), with a stale doc-comment (lines 22-25) that predates the 2026-05-30 change and still says "friends don't get vault admin." A signed-in friend gets `403 not_admin` and is bounced to `/account/`. That single gate — not the scope model — is why Aaron configures every backup by hand.

The unlock is a **non-admin sibling endpoint** `/account/vault-admin-token/<name>` that swaps the `isFirstAdmin` gate for an assignment check (`vaultVerbsForUserVault(user, name)` includes `admin`) and hands the friend's own token to the vault SPA via the `#token=<jwt>` fragment it already accepts ([vault `auth.ts:69-90`](#)). This is the spine of the whole program: ~10 lines of plumbing completes work that is already 90% done.

### Goals

- An individual user can **back up their own vault** (internal + GitHub) from `/account/`, without the operator.
- **New vaults are backed up by default** (internal live mirror), with one-button GitHub upgrade.
- The operator can **see per-vault disk + note usage** across all vaults.
- The operator can **invite someone with a link** that provisions an account + vault.
- The shared box is **hardened** for strangers: force-rotation enforced per-request, owner-vs-shared roles distinguished, provisioning races closed.

### Non-goals (this doc)

- **Usage caps / quotas.** Monitoring first (Aaron's explicit priority). We note the cap hook (§5) but build none.
- **Email / magic-link recovery.** Invites are link-copy-paste; no email anywhere in the stack.
- **A second account SPA.** We extend the server-rendered `/account/*` family (§2).
- **Full RBAC.** Owner-vs-shared is two roles, not per-action grants.
- **Multi-admin.** The `isFirstAdmin`-by-earliest-row model stays; we flag replacing it as an open question, not a build.

---

## 2. The account surface

### Current state

`/account/` is **not** part of the `/admin/*` React SPA. It is a separate, **server-rendered HTML family**, dispatched in `hub-server.ts` before the SPA catch-all ([`hub-server.ts:2191-2257`](#)). Four routes today:

- `GET /account/` — the friend home ([`api-account.ts:481`](#) → `renderAccountHome`, [`account-home-ui.ts:163`](#)).
- `GET|POST /account/change-password` — self-service password change ([`api-account.ts:131/197`](#)).
- `GET|POST /account/2fa` — self-service TOTP enroll/disable (hub#473).
- `POST /account/vault-token/<name>` — friend mints a `vault:<name>:read|write|admin` bearer ([`account-vault-token.ts`](#)).

The page renders: a "Get started with your AI" card (hub#529), one tile per assigned vault (MCP connect commands + Notes deep-links + a collapsed "Mint an access token" `<details>`), and an account card (username, sign-out, password/2FA links). What it **cannot** do: configure backup, see usage, list/revoke its own tokens (mint-only — the banner literally says "To revoke it, ask the hub operator", [`account-home-ui.ts:505`](#)), or manage OAuth grants. Everything substantive is admin-SPA-only.

`GET /api/me` returns only `{ hasSession, user:{id, displayName}, csrf }` ([`api-me.ts:62-103`](#)) — no vaults, no usage, no role. That is the per-user data ceiling today.

### Decision: extend the server-rendered `/account/*` family — do NOT build a second SPA

Three options were weighed (research account-surface §designOptions):

- **A — extend server-rendered `/account/*`.** New sibling pages, hand-rolled HTML + inline CSS, session-cookie + CSRF auth (already proven). No bundle, works without JS, matches the cohesive `account-home-ui.ts` chrome family.
- **B — a second friend-scoped SPA** at `/account/*` over new `/api/account/*` endpoints. Richer interactivity (status polling, charts), but a whole second bundle + auth path for a small population — over-engineered.
- **C (recommended) — server-rendered pages, with the backup form built ONCE** and reused by both the friend page and the operator's admin path (link the admin to the same `/account/backup/<vault>` route, or deep-link into the existing `VaultMirror.tsx`).

**Recommendation (Uni) — confirm: ship Option C.** The backup authorization is already closed server-side; only the UI is missing, and a server-rendered page reuses the proven session/CSRF posture with zero new auth surface. The "Get started with your AI" card (hub#529) is the precedent: server-rendered cards on `/account/`, links to externally-iterated `parachute.computer/onboarding/*` content, friend-and-operator parity. A "Back up your vault" card sits alongside it as the natural next step.

### What lands on `/account/`

Priority-ordered (research account-surface §designOptions "what belongs on a real account surface"):

1. **My vaults** (exists) + **per-vault BACKUP config/status** — the headline gap. A new `/account/backup/<vault>` page (GET form + POST) driving the vault's already-`vault:admin`-gated `/.parachute/mirror` + GitHub device-flow endpoints, plus a "Back up this vault ↗" affordance on each vault tile (mirroring the existing token-mint `<details>`).
2. **Per-vault USAGE** — a one-line "X notes · Y MB" stat per tile, sourced from the new usage endpoint (§5). Read-scope, so the user's own credential suffices.
3. **My TOKENS** — `GET /account/tokens` listing the user's own minted vault tokens with a self-serve revoke POST. Closes the mint-without-revoke asymmetry; the registry + revocation machinery already exist ([`api-tokens.ts`](#), [`api-revoke-token.ts`](#)) — this is a session-gated, self-scoped view over them.
4. **My CONNECTORS / OAuth grants** — review + revoke apps authorized against my vault (today admin-only via `/admin/permissions`). **Open question** — whether a friend may revoke their own grants needs a session-gated self-scoped `/api/permissions` variant (§11-g).
5. **Security** (exists: password, 2FA) + sessions ("sign out everywhere" — a Phase-2 item).
6. **Profile** (display name, optional email for recovery) — `displayName == username` today; deferred.

Items 1–3 are the clear builds for this arc. The substrate decision (C) is what makes them cheap.

---

## 3. Git backup + defaults

### Current state

The mirror is **"vault knows about its own git projection."** A per-vault `MirrorManager` drives export → commit → push. Config lives at `data/<vault>/mirror-config.yaml`; credentials at `data/<vault>/.mirror-credentials.yaml` (0o600). The config shape ([`mirror-config.ts:127-155`](#)): `enabled`, `location` (internal|external), `sync_mode` (events|manual), `auto_commit`, `auto_push`, `commit_template`, `safety_net_seconds`. **Defaults: `enabled=false`** — so a brand-new vault has the mirror OFF.

**"Internal live mirror"** mechanically = `location:internal` + `sync_mode:events` + `auto_commit:true`. The manager subscribes to in-process note/tag/attachment hooks ([`mirror-manager.ts:724`](#)), debounces ~500ms, runs a portable-markdown export + git commit into `<vaultDir>/mirror/` — a vault-managed repo `bootstrapInternalMirror` auto-`git init`s ([`mirror-manager.ts:232`](#)). This is a **live, on-disk, git-versioned backup with zero external dependency** — no GitHub, no token. Adding `auto_push:true` + credentials turns it into off-box backup. git-less boxes degrade to a friendly `last_error` rather than crash ([`git-preflight.ts:25-49`](#)).

GitHub linking is already built two ways ([`mirror-credentials.ts:71`](#)): **OAuth Device Flow** (recommended — needs only a public `PARACHUTE_GITHUB_CLIENT_ID`; placeholder → 503) and a **PAT fallback**. Saving credentials auto-enables `auto_push` and fires an initial push ([`mirror-routes.ts:1010`](#)).

**Five distinct paths create a vault** (research vault-creation-flow §currentState) — CLI `create`, CLI `init`, hub SPA `POST /vaults`, the setup wizard, and container first-boot. **None touch mirror config.** All funnel through `createVault()` ([vault `cli.ts:3336`](#)) except container first-boot ([`server.ts:147-190`](#)). That single funnel is the hook point.

### Decision A: new vaults default to internal live mirror, behind a config knob

**Recommendation (Uni) — confirm: flip the default to internal live mirror at create-time, gated by a `default_mirror` knob.**

- Make `createVault()` write a History-preset `mirror-config.yaml` — `{ enabled:true, location:internal, sync_mode:events, auto_commit:true, auto_push:false }` — right after `getVaultStore(name)`. One edit covers CLI create, init, hub-SPA `POST /vaults`, and wizard create, since all four funnel through `createVault`.
- Gate it behind a global config field **`default_mirror: internal | off`** (default `internal`). An operator on a git-less or disk-constrained box flips it off once; no code change.
- **Create-time only** for new vaults (existing vaults untouched — no surprise behavior change). Optionally add an idempotent boot pass that writes the History preset for pre-existing mirror-config-less vaults when `default_mirror=internal`, so they retroactively get local backup. **Open question** whether to do the retro-pass (§11).

**Cost** (research §designOptions C): one markdown copy of the vault per vault (small for text — the same artifact export already produces), a one-time git-init + full export on first boot (seconds), and one debounced events subscription per vault. The real risk is correctness on git-less boxes, already handled by `git-preflight` degrade-not-crash. Surface the `last_error` on `/account/` + the admin SPA so a bootstrap failure is visible, not silent.

### Decision B: GitHub linking is an opt-in upgrade via the existing device flow

The coherent shape is two-step **by design**: (1) creation auto-enables the local internal mirror (free, no creds); (2) a prominent "Back up to GitHub" CTA on the `/account/` vault tile (and the admin vault row) deep-links into the existing device flow → create-repo (defaults private) → select-repo wires `origin`, flips `auto_push` on, fires the initial push. **All of step 2's backend already exists.** The only new surface is the CTA + the owner-token unlock (§2 / §4).

Reframe the `VaultMirror.tsx` copy around **"Backup"** — "Local backup: on" (internal) + "Off-site backup: GitHub" — rather than the operator-centric "mirror/sync" vocabulary. Pure frontend.

**Recommendation (Uni) — confirm: for the GitHub link on an internal mirror, keep `location=internal` and just set `origin` + `auto_push`** (the credential-application path supports this) rather than flipping to `location=external` with an operator-visible path. Internal-stay is lower-friction for a non-technical friend; external is what Obsidian/IDE cookbook users expect. This is a genuine fork — §11-h.

### Decision C: ship a Parachute-owned GitHub OAuth App client_id

For "one button → backed up on GitHub" to work for a non-technical friend, the Device Flow needs a real `PARACHUTE_GITHUB_CLIENT_ID`. Unset → 503 → friends fall back to pasting a PAT (a much rougher UX).

**Recommendation (Uni) — confirm: register a Parachute-owned GitHub OAuth App and ship its public `client_id` as the default.** Device Flow only needs the public client_id (no secret), which is exactly why it was chosen for unpredictable self-hosted origins. **This needs Aaron to register the app** (the only blocker) — §11-c. Operator-configured remains the fallback for those who want their own app.

### Adjacent fixes to fold (vault repo)

- vault#401 / #385 — persist selected `owner/repo` into the credentials struct so it survives `DELETE /auth` + re-OAuth and mirror-not-yet-enabled (don't regex-parse `.git/config` origin).
- vault#393 — the missing hermetic test for the PAT → auto_push → initial-push chain.
- Turn the wizard import step's dead-end "set up push credentials later from the vault's mirror settings" ([`setup-wizard.ts:756`](#)) into a real link to the new backup page.

---

## 4. User / auth + roles — the owner-vs-shared problem

### Current state (read the code, not the old doc)

The schema has moved **past** the 2026-05-20 Phase 1 doc. That doc described a single `assigned_vault` column; the live code is at Phase 2: a `user_vaults (user_id, vault_name, role TEXT DEFAULT 'write', created_at)` join table (migration v10 dropped the old column, [`hub-db.ts:309-321`](#)), `User.assignedVaults: string[]`, and per-user TOTP (v11).

**"Who is admin" is positional.** `isFirstAdmin` = the earliest-created `users` row ([`users.ts:360-373`](#)). One admin, N friends. No role column on `users`, no second admin possible.

**The dormant role.** `vaultVerbsForRole("write")` → `["read","write","admin"]`, `("read")` → `["read"]`, unknown → `[]` (fail-closed) ([`users.ts:178-182`](#)). But **every assignment is written `role='write'`** ([`users.ts:273,431`](#)) → so **any assigned user gets full vault admin** (token mint/revoke + config edits on that vault). This was Aaron's explicit 2026-05-30 call. The `role='read'→[read]` path **exists in code but no flow ever creates it.**

### The problem this opens

Self-serve sharing forces the question: the moment you invite someone into a vault you co-use, they hold **admin** over it — they can mint admin tokens, revoke *your* tokens on that vault, and edit its config (providers, retention, schema). There is **no owner-vs-shared distinction.** For a single-operator-N-friends-with-N-separate-vaults model this never bit (each friend owns their one vault). For *shared* vaults it is the biggest blast-radius lever in the system.

### Decision: light up the dormant `user_vaults.role` for owner-vs-shared

Three authz models were weighed (research user-auth-model §designOptions):

- **A — keep scopes as the authority, just unblock the UI** (the §1 token-unlock). Ships now, smallest diff. Owner-of-X stays the existing triple (`vault:X:admin` scope + `vault_scope` contains X + `aud=vault.X`). This is the spine and it's recommended regardless.
- **B — use the dormant role column for owner vs shared.** Write `role='owner'` (or keep `'write'`) for the primary/creating user; default users *shared into a co-used vault* to a narrower role. Gate owner-only actions (config, delete-vault, invite-others) on it **server-side**, keeping the JWT wire shape stable. The cap path (`capScopesToUserAuthority`, `account-vault-token` gate 3) reads role **dynamically**, so it enforces a narrower role for free.
- **C — full per-action RBAC.** Over-engineered for "twenty friends, twenty vaults"; the Phase 1 doc already rejected this. Skip.

**Recommendation (Uni) — confirm: do A now (unblock the UI), and adopt B's role semantics** — light up `role='read'` (or a `'shared'` role) as the default for users *shared into an existing vault*, reserving the admin-granting role for the vault's owner. **Do NOT add a new wire claim** (`vault_owner`) yet — gate on `user_vaults.role` server-side and keep the JWT stable. This is the single biggest hardening lever, and the schema + the dynamic cap are already in place — it's a one-line policy change at the assignment/invite site.

The **exact default role** for a shared user (read vs write) is a genuine product call — §11-a. It is also security-P0 #2 (§6), because invites are the flow that creates shared-vault membership for the first time.

The first-admin-by-earliest-row heuristic is fine for single-operator but should eventually become an explicit `users.role` / `is_admin` flag before multi-admin. **Low urgency, flagged not built** — §11.

### Capability matrix (vault-owner user, current vs target)

| Capability | State |
|---|---|
| Connect AI clients (OAuth) | ✅ already (`capScopesToUserAuthority` admits admin) |
| Mint headless read/write/admin tokens | ✅ already (`POST /account/vault-token/<name>`) |
| Change password, enroll 2FA, sign out | ✅ already (`/account/*`) |
| Configure git backup (mirror + GitHub) | **authorized, UI-blocked** → §1/§2/§3 unlock |
| Manage vault retention/providers/schema/tokens | same UI-block, same unlock |
| See own vault usage (size, notes, last backup) | **not built** → §5 |
| Create/delete own vault, invite others | **not built**, stays operator-gated in this phase (revisit with invites) |

---

## 5. Monitoring — per-vault usage (Aaron's priority)

### Current state

**There is no usage/disk-size monitoring anywhere.** `getVaultStats` ([core `notes.ts:1540-1596`](#)) computes logical counts only (notes, attachments, links, tags, date range, histogram) — **no bytes**. `byteSize` exists per-note ([`notes.ts:1485`](#)) but is never summed. The admin SPA vault row shows only name/version/url/Connect/Manage ([`VaultsList.tsx:178-235`](#)); its only data source is the anonymous `/.well-known/parachute.json` (logical topology). The `/account/` tiles show no usage. **Genuinely greenfield** — no `du`/`statfs`/dir-walk anywhere.

The on-disk paths to measure (research monitoring §currentState): per-vault dir `<root>/vault/data/<name>` containing `vault.db` (+ `-wal` + `-shm` sidecars — WAL mode, so all three count), `assets/` (date-bucketed uploads), and `mirror/` (the internal git working tree + `.git`).

### Decision: compute usage vault-side, aggregate in hub, surface in both SPA and /account

The `GET /vault/<name>/.parachute/mirror` admin-metric endpoint is the exact dispatch+scope precedent to clone — but for usage we use **read** scope, not admin (a user should see their own vault's size; matches the bare-root stats precedent at [`routing.ts:452`](#)).

**(a) The vault-side endpoint** — `GET /vault/<name>/.parachute/usage`, gated `hasScopeForVault(scopes, name, "read")`, returning:

```jsonc
{
  "counts": { "notes": …, "attachments": …, "links": …, "tags": … },   // existing getVaultStats — free
  "bytes": {
    "content": …,   // SUM(LENGTH(CAST(content AS BLOB))) over notes — one cheap SQL query (new)
    "db":      …,   // vault.db + vault.db-wal + vault.db-shm — 3 statSync calls (WAL-aware)
    "assets":  …,   // recursive walk of assetsDir (cost)
    "mirror":  …,   // recursive walk of resolveMirrorPath (cost)
    "total":   …    // db + assets — mirror EXCLUDED (it's a projection of the same data), shown as a separate line
  },
  "computedAt": "<iso>", "cached": true
}
```

`content` and `db` are O(1)/cheap-SQL and stay always-on. `assets` + `mirror` need recursive dir-walks — the cost center.

**(b) Caching — required, not optional.** **Recommendation (Uni) — confirm:** compute counts + content + db **always**; compute the two dir-walks **lazily behind a ~60s in-process TTL cache** keyed by vault name, invalidated on upload ([`routes.ts:2435`](#)) and on a mirror export pass; `?fresh=1` forces recompute. This bounds walk cost to once/minute/vault. (Fallback if caching is contentious: ship counts + content + db only first — already answers "how big is this vault's data" for the DB-dominant case.)

**(c) Hub aggregation + surfacing.** Add `getVaultUsage(name)` to the SPA api client ([`web/ui/src/lib/api.ts`](#)) fetching through the existing `proxyToVault` ([`hub-server.ts:586`](#)); render a size + note-count cell in the `VaultsList` row. For the cross-vault total: client-side fan-out first (N small), promote to a hub `GET /api/vaults/usage` aggregator if N grows. On `/account/`, fetch each assigned vault's usage in `handleAccountHomeGet` via the user's own session-derived vault bearer and render a one-line stat per tile — **read scope is the key unlock**; the user's own credential suffices (admin-only would block them).

**Total semantics:** present `total = db + assets` with **mirror as a separate line** (avoids double-counting the projection). Whether Aaron wants one headline number that includes the mirror is a presentation call — §11.

### Caps: explicitly out of scope (hook noted)

Monitoring first, per Aaron. The endpoint's `bytes.total` is the natural cap input; a cap would live as a `usage_cap_bytes` field on `VaultConfig` ([`config.ts:144`](#)), checked at write/upload time, with the mirror manager's periodic pass as the alerting hook. **No build now** — the endpoint shape + a vault.yaml field are the only prerequisites when a cap story materializes.

---

## 6. Security posture — the multi-user sweep

Strangers getting accounts on a shared box changes the threat model. The research mapped the hub's five gate flavors (host-admin bearer; session + first-admin; session-any-user `/account/*`; capability-attenuation mint; generic service/vault proxy with no hub-level auth) and the strong cross-vault isolation (audience strict-check + `vault_scope` claim + broad-scope reject — three independent gates in vault `auth.ts`). Below is the **prioritized risk register**, split load-bearing (opened/amplified by this program) vs pre-existing.

### P0 — directly opened or amplified by invites/self-serve. **These GATE shipping invites.**

**P0-1 — #469: force-change-password is redirect-only, not per-request.** ([`hub-server.ts:2197-2200`](#) comment is explicit.) A friend handed a temp password can navigate directly to `/account/`, `/account/vault-token/<name>`, or a per-vault proxy URL and operate **indefinitely** on the un-rotated secret. Invites = temp-credential handoff *at scale*, so this scales with every invited user. **Fix:** implement the per-request gate the issue sketches — hard-gate `/account/*` (except `/logout`) + per-vault proxy on `password_changed===true`, redirect to `/account/change-password` otherwise. The hub already resolves the user per request, so the cost is low; the only design call is which surfaces stay reachable pre-rotation (§11-f). Pair with auto-cascade reset-password → session-revoke (`resetUserPassword` already revokes tokens at [`users.ts:546`](#); add a sessions DELETE in the same tx). **Do this in the invite PR.**

**P0-2 — owner-vs-shared authority** (§4). Self-serve sharing hands admin over a co-used vault to whoever you invite. **Fix:** light up `role='read'→[read]` as the **default for invited/shared users**, reserving the admin-granting role for the owner — a one-line policy change at the assignment site; the dynamic cap enforces it for free. Biggest single hardening lever, nearly built. The exact default is §11-a.

**P0-3 — bootstrap-token public-first race** ([`bootstrap-token.ts`](#)). The hosted/invite story provisions **public** boxes; whoever POSTs `/admin/setup` first claims admin. Mitigated only by the in-memory token printed to the operator's logs. **Fix:** the hosted provisioner **env-seeds `PARACHUTE_INITIAL_ADMIN_*`** so the wizard's claim step is never reachable (the bypass already exists). For self-host, document the log-and-claim-fast flow. No new code if provisioning seeds env. §11-c-race.

### P1 — pre-existing exposure that strangers-on-the-box make materially worse (same hardening sweep)

**P1-4 — #526: `layerOf` fails OPEN to "loopback".** ([`hub-server.ts:444-456`](#).) When no proxy headers are present, a header-absent network peer is misclassified as most-trusted loopback and **bypasses the `publicExposure:loopback` 404-cloak** on `proxyToService`/`proxyToVault`. The docstring premise ("hub binds 127.0.0.1") is falsifiable — containers/Render bind 0.0.0.0. **Fix:** derive trust from `Bun server.requestIP` instead of header-absence. Independent of invites but lands in the same sweep — it's the integrity of the cloak that hides friend-facing surfaces.

**P1-5 — mint-token folds (#451, #450, subject-pin):**
- **#451** — bare `vault:admin` (no name segment) is not in `NON_REQUESTABLE_SCOPES` and mints through `/api/auth/mint-token` from a host:auth bearer. Vault rejects broad unnamed scopes today ([`auth.ts:422-433`](#)) so blast radius is limited, but the requestability is surprising. **Fix:** add bare `vault:admin` to `NON_REQUESTABLE_SCOPES` (one-line).
- **#450** — mint-token doesn't validate vault existence; a typo mints `vault:typo:admin` (unusable, automation-confusing). **Fix:** thread `knownVaultNames` into `ApiMintTokenDeps` (the session path already does this).
- **subject-pin** — `subject` is caller-controllable ([`api-mint-token.ts:234-241`](#)); a host:auth bearer can stamp any `sub` while scopes stay attenuated. Authority isn't escalated, but the **audit-attribution label is forgeable.** **Fix:** pin `subject=bearerSub` (or validate authority over the requested subject) before audit-by-user ships. §11 notes the "is anyone relying on caller-set subject" check.

**P1-6 — scribe runs auth-open on installs predating the auto-wire (the config-auth self-heal gap).** Scribe gates on a shared secret bridged from `config.json` `auth.required_token` ([`server.ts:736-741`](#), [`auth.ts:115-126`](#)), which the **hub's install-time auto-wire** writes (scribe#66). An install that **predates** the auto-wire never had `auth.required_token` written → `bridgeConfigAuthToken` returns nothing → scribe boots **auth-open** (it logs "Set SCRIBE_AUTH_TOKEN … before exposing scribe", [`server.ts:788`](#), but does not refuse to start). On a shared box reachable through the generic proxy (which applies **no hub-level auth** — "the service does its own auth", [`hub-server.ts:671-718`](#)), an auth-open scribe is reachable by anyone on the exposure layer. **Fix:** an **auth self-heal on scribe start** — if no token is configured and the box is exposed beyond loopback, re-derive/write `auth.required_token` from the hub (the auto-wire path) rather than silently serving open. This is the [origin-pinned-credentials self-heal] pattern applied to scribe config. **Recommendation (Uni) — confirm** the self-heal vs a hard refuse-to-start-when-exposed-and-tokenless posture (§11).

### P2 — hygiene / written boundaries (non-gating)

- **Generic proxy has no per-user module authorization** ([`hub-server.ts:671-718`](#)). A signed-in friend reaches scribe/notes/etc. gated only by *that module's* auth, with no check that their hub assignment includes that module. Fine while modules are trusted first-party — but **write down** whether the hub should mediate per-user module reachability or "modules self-gate" is the permanent boundary, before a future module trusts the hub session implicitly. §11-module-mediation.
- **`/account/*` origin-check asymmetry** — friend POSTs rely on CSRF double-submit + SameSite=Lax but do not call `isSameOriginRequest` (the belt the oauth/admin POSTs use). Defensible, but close it when the friend surface broadens — `isSameOriginRequest` ([`origin-check.ts:112`](#)) is ready to call.
- **`UNKNOWN_IP_SENTINEL` shared rate-limit bucket** ([`rate-limit.ts:293-306`](#)) — header-absent peers collapse into one `/login`+2FA throttle bucket. Throttle-evasion / mutual-DoS seam, low sev; noisier with strangers on the box.
- **`revocation_lag_seconds: 60`** — admin reset/revoke takes up to 60s to propagate (scope-guard cache). Compounds P0-1's standing-temp-password exposure; the "kill NOW" path needs a module restart.
- **patterns#37 tag-scoped-tokens §Future** — 8 deferred sub-vault delegation knobs (read/write split, path-form allowlist, tag-groups, etc.). Not regressions; capability gaps that limit how finely a shared vault can be delegated. Relevant only if invites want sub-vault sharing rather than whole-vault membership. §11.

### What gates invites

**P0-1 (per-request force-change), P0-2 (owner-vs-shared default role), and P0-3 (env-seed provisioning) GATE shipping invites.** All three are low-code because the primitives exist. P1-4 (#526 cloak) + the P1-5 mint-token folds belong in the same hardening sweep but don't strictly block. The separate deep adversarial sweep should focus on the **mint/attenuation arithmetic** and the **`enforceVaultScope` empty=open sentinel** ([`scope.ts:108-114`](#)) under adversarial scope strings — those are the load-bearing correctness invariants.

---

## 7. Invite links

### Current state

**No invite primitive exists.** Onboarding is admin-types-a-default-password only; the 2026-05-20 doc explicitly punted invite links to Phase 2 ("`/account/setup/<one-shot-token>` → pick-your-password, no admin-typed password ever exists"). But **every constituent primitive already exists** (research invites §currentState): the wizard's account-claim flow `handleSetupAccountPost` ([`setup-wizard.ts:1802-1930`](#)) is the exact "redeem one-time token → createUser(passwordChanged) → consume-after-commit → createSession → 302" template; `auth_codes` ([`auth-codes.ts:107-170`](#)) is the canonical DB-backed single-use+expiring+bound-context token model; `handleCreateVault` provisions a vault; `createUser` drops `user_vaults` rows atomically; `pending_first_client_auto_approve_window` ([`hub-settings.ts:159-212`](#)) is the precedent for skipping the first-OAuth-client approval wall.

### The design

**Token representation — DB row, not signed JWT.** New `invites` table (**migration v12**) modeled on `auth_codes`: `token TEXT PK` storing **sha256(token)** (not raw — invites are longer-lived than 60s auth-codes, so a DB read can't replay), `created_by`, `vault_name` (nullable if account-only), `role TEXT DEFAULT 'write'`, `provision_vault INTEGER`, `default_mirror TEXT` (wires to §3), `expires_at`, `used_at`, `redeemed_user_id`, `revoked_at`, `created_at`. A stateless JWT buys nothing here (single-use needs a server-side used-set anyway; revocation needs a denylist) and loses the audit/list/revoke surface.

**Redemption flow — server-rendered (NOT SPA), mirroring `/login` + the wizard.** New un-authed routes (added to the pre-admin-lockout exemption list, [`hub-server.ts:1056`](#)):
- `GET /account/setup/<token>` — renders a "pick your username + password" form (reuse `admin-login-ui.ts` chrome; **reuse `validateUsername`/`validatePassword`** [`users.ts:637/689`](#) so the un-authed boundary has the same gate as `/api/users`).
- `POST /account/setup/<token>` — one handler mirroring `handleSetupAccountPost`: (1) look up invite by `sha256(token)`, reject not-found/expired/used/revoked (404/410); (2) validate credentials; (3) if `provision_vault`: `handleCreateVault`-equivalent (idempotent); (4) `createUser(…, { allowMulti:true, passwordChanged:TRUE, assignedVaults:[vault_name], role:<invite.role> })` — **passwordChanged TRUE** because the user chose their own password, so they skip force-change; (5) **write the §3 default mirror config** for the provisioned vault; (6) stamp `invites.used_at` + `redeemed_user_id` **AFTER** the user row commits (wizard ordering — a `createUser` exception leaves the invite re-usable); (7) optionally open a per-user OAuth-client auto-approve window so their first Claude MCP connect doesn't bounce through admin approve; (8) `createSession` + cookie + 302 to `/account/`.

**Admin management surface** — new `/api/invites` (host:admin-gated, like `/api/users`): `POST` (create: `{vault_name?, role?, provision_vault?, default_mirror?, expires_in?}` → one-emit token + URL, never retrievable later); `GET` (list with status pending/redeemed/expired/revoked); `DELETE /:id` (revoke). A section in the admin SPA `Users.tsx` (create-invite form + list with copy-URL + revoke), reusing the cached host-admin bearer + confirm-modal patterns.

**Security posture:** 256-bit random token (matches bootstrap/auth-code entropy); sha256 storage; single-use via `used_at` sqlite-serialized stamp; expiry enforced at redeem (default **7 days** — long enough to deliver out-of-band with no email, short enough to bound a leaked link); redemption rate-limited (reuse the `/login` bucket, keyed by IP) + CSRF on the POST. **What the invite pre-authorizes:** creating exactly ONE account + assigning exactly the named vault at the baked-in role — **NOT** host:admin, NOT any other vault. The redeemed user inherits only the `user_vaults` row's authority.

### This is GATED by the §6 P0s

An invite is the flow that hands a temp-equivalent credential and creates shared-vault membership for the first time. **Do not ship invites before P0-1 (per-request force-change), P0-2 (owner-vs-shared default role), and P0-3 (env-seed provisioning) land.** The §6 fixes go in the same PR chain — P0-1 is explicitly "do this in the invite PR."

---

## 8. Sequencing — the implementation PR plan

Serial, per-repo, one PR through merge before the next (workspace governance). Roughly:

1. **Vault: usage endpoint** (Aaron's priority, no auth/product decision) — `SUM(content-bytes)` into `getVaultStats`, `dirSize`/`dbBytes` helpers, `GET /.parachute/usage` (read-scope) + 60s cache. Pure additive, testable against fixtures.
2. **Hub: surface usage** — SPA `VaultsList` cell + `/account/` tile stat via `proxyToVault`. Client-side fan-out for the cross-vault total.
3. **Vault: default_mirror knob + createVault writes History preset** — pure vault repo, no hub coupling. Add `--no-mirror` flag for parity.
4. **Hub + vault-SPA: self-serve backup unlock** — `/account/vault-admin-token/<name>` (assignment-gated sibling of the admin endpoint), `/account/backup/<vault>` page (or deep-link to `VaultMirror.tsx#token=…`), "Back up this vault" + "Back up to GitHub" affordances. Update the stale `admin-vault-admin-token.ts` doc-comment. **This is the highest-leverage UI PR.**
5. **Hub: the §6 security sweep** — P0-1 per-request force-change + cascade revoke, P0-2 owner-vs-shared role default, P1-4 #526 cloak fix, P1-5 mint-token folds. (Scribe self-heal P1-6 is a separate scribe-repo PR.)
6. **Hub: invite links** — migration v12, `invites.ts`, `/api/invites`, `/account/setup/<token>`, `Users.tsx` section. **After** steps 4 + 5; P0-1 lands here if not already.

Steps 1–4 deliver the individual-user value; 5 is the prerequisite hardening for 6.

---

## 9. What changes in the existing DB + config shape

- **Hub** — migration **v12**: `invites` table (§7). No backfill. The `user_vaults.role` column already exists (v10); we begin writing values other than `'write'` (§4).
- **Vault** — global config gains **`default_mirror: internal|off`** (§3). `VaultStats` / a sibling `VaultUsage` gains byte fields (§5). `VaultConfig` *may* later gain `usage_cap_bytes` — **not this phase** (§5 hook).
- **Scribe** — no schema change; an auth self-heal on start (§6 P1-6).

---

## 10. Where Uni's recommendation diverges from the research

The research and these recommendations agree almost everywhere. Two notable deltas:

1. **GitHub-link location.** The git-mirror research's open question leaves internal-stay vs flip-to-external genuinely open; the vault-creation research's option D leans "reuse device-flow + keep internal + set origin/auto_push." This doc **commits to internal-stay** as the recommended default (§3-B) for non-technical-friend UX, while preserving it as an explicit fork (§11-h). Slight commitment beyond the research's neutrality.
2. **Default role for shared users.** The research's user-auth-model area is comfortable keeping "any assigned user gets admin" for the friends-and-family model; the **security-surface** area is more forceful that owner-vs-shared is the #2 P0 and shared-should-default-to-read. This doc **sides with the security framing** (§4, §6 P0-2) — recommend defaulting shared users to read — because invites are precisely what make co-used-vault sharing a first-class flow. The two research areas are in mild tension; this doc resolves toward the more conservative posture and surfaces the exact default as the headline open question (§11-a).

Everything else (substrate = server-rendered, default_mirror=internal, read-scope usage, mirror excluded from total, DB-row invites, the P0 gating) follows the research directly.

---

## 11. Open questions for Aaron

The genuine product calls. Defaults above are tagged "Recommendation (Uni) — confirm"; these need Aaron's decision before the relevant PR lands.

**(a) Owner-vs-shared default role — the headline call.** When a user is *shared into a vault someone else owns*, do they default to `read` (read-only — the path already coded but unused) or `write` (which today maps to full admin)? Today **every** assignment is `write`→admin. This is the single biggest sharing-safety lever (§4, §6 P0-2). Recommend: shared → read, owner → admin-granting role. Is "share a read of one vault" a first-class mode, or does sharing always mean co-admin?

**(b) Cloud disk posture for `default_mirror`.** On the hosted single-container deploy ($7/mo flat, one persistent disk), should `default_mirror=off` (the internal markdown mirror ~doubles every vault's storage on the same disk the data lives on) while internal stays on everywhere for self-host? Or internal-on everywhere? Relatedly: does the container-first-boot path ([`server.ts:147-190`](#)) also get the internal mirror?

**(c) Ship a Parachute-owned GitHub OAuth App.** Register a Parachute GitHub OAuth App and ship its public `client_id` as the default (one-button backup for non-technical friends), or leave Device Flow operator-configured (friends fall back to PAT-paste)? **Recommend ship it — but this requires Aaron to register the app** (the only blocker). Operator-configured stays the fallback.

**(c-race) Provisioning race posture.** Does the hosted/invite provisioner env-seed `PARACHUTE_INITIAL_ADMIN_*` (closing the bootstrap-token public-first race entirely — §6 P0-3), or rely on the in-memory-token log-and-claim flow? Determines whether the race window exists in the hosted story.

**(d) Account substrate.** Confirm: extend the server-rendered `/account/*` family (Option C — recommended) vs build a second friend-scoped SPA (Option B)? Sets the shape of all subsequent account work. Sub-question: should the **same** backup UI serve both the operator (configuring a friend's vault) and the individual user (one server-rendered page linked from both `/account/` and `/admin/vaults/<name>`), or separate surfaces?

**(e) 2FA enforcement on public expose.** For a publicly-exposed multi-user hub, is **force-2FA-when `setup_expose_mode ∈ {tailnet,public}`** in scope now, or still deferred (the 2026-05-20 doc wanted stronger nudges + eventual Phase-3 enforcement)?

**(f) Does an invite auto-create a vault, or just an account?** Aaron's "twenty vaults for twenty people" implies provision-on-redeem, but `parachute-vault create` is a shell-out that can fail mid-redemption. Recommend: `provision_vault` flag (default true); on provision failure still create the account + surface "vault pending" to the admin. Sub-questions:
- **Vault naming when provisioning** — admin pre-bakes `vault_name` into the invite (redeemer can't squat names — recommended) vs redeemer types it vs derive-from-username?
- **Invite cardinality** — single-use single-account (recommended, matches "one-shot URL") vs a multi-use "join my hub" link for a group?
- **Default expiry** — 7 days proposed; confirm, and whether per-invite override is wanted.
- **Auto-open the per-user OAuth-client approval window** on redemption (so the first Claude MCP connect doesn't hit the DCR approval wall — recommended)? It auto-approves whichever client the new user first registers — confirm the threat tolerance.

**(g) Token/grant self-management scope.** Should a friend be able to revoke their own **OAuth grants/connectors** (today `/admin/permissions`, admin-only — needs a session-gated self-scoped `/api/permissions` variant), or only their minted **bearer tokens** (the `/account/tokens` build)?

**(h) GitHub-link location on an internal mirror.** Keep `location=internal` + set `origin`/`auto_push` (lower-friction, recommended for friends) vs flip to `location=external` with an operator-visible path (what Obsidian/IDE cookbook users expect)?

**(i) Force-change-password vs first-read friction (#469).** The per-request gate (§6 P0-1) walls a friend off until they rotate. Right trade vs letting them read one note first? The issue explicitly flags where the line sits as Aaron's call.

**(j) Replace the first-admin-by-earliest-row heuristic?** Introduce an explicit `users.role` / `is_admin` flag before enabling multi-admin/teams, or keep single-admin for the foreseeable "one operator, N friends" model? Low urgency.

**(k) Per-user module reachability mediation.** Should the hub mediate which user may reach which module (scribe/notes/etc.), or is "each module self-gates, hub just proxies" the permanent boundary ([`hub-server.ts:671-718`](#))? Needs a *written* decision before a future module trusts the hub session implicitly. (Directly relevant to the scribe P1-6 self-heal: if the hub mediated, an auth-open scribe would be less reachable.)

**(l) Sub-vault delegation depth.** Whole-vault membership only (today), or do invites want sub-vault sharing via the deferred tag-scoped/path-form allowlist (patterns#37 §Future)? Determines whether the tag-scope survey gets de-deferred for this program.

**(m) Mint-token caller-controllable subject.** Is anyone relying on it (e.g. operator minting on behalf of a user), or is it pure forgery surface to pin shut (§6 P1-5)? Pinning is safe only if no flow depends on it.

**(n) Usage presentation + scope.** Confirm: usage is **read-scope** (user sees own vault size — recommended, the individual-user unlock) not admin-only; `total = db + assets` with **mirror as a separate line** (no double-count) vs a single headline number including the mirror; and a **60s in-process TTL** for the dir-walks (vs always-fresh) acceptable.
