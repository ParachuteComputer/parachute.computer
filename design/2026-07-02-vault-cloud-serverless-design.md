# Vault Cloud — the serverless per-tenant design

*Design doc — 2026-07-02. Status: **DEEP DESIGN** (per `Decisions/2026-07-02-cloud-do-per-vault`: serverless per-tenant is the direction; Cloudflare is the default, not an attachment; bounded runtime divergence accepted; maximize shared core + shared wire contract). Author: uni/session (with Aaron). Grounded in three commissioned inventories run against the actual code and July-2026 vendor docs: the vault-core portability audit, the wire-contract map, and the substrate survey. Supersedes nothing — this is the "how it gets created" companion to [`2026-07-01-parachute-cloud-v1.md`](./2026-07-01-parachute-cloud-v1.md) and the [substrate deliberation](./2026-07-02-cloud-substrate-deliberation.md).*

---

## 1. What we're building

The Simple Vault tier, for real: someone pays $3–5/mo and gets a vault with **platform-enforced per-tenant isolation** — a vault instance whose code *cannot address* another tenant's data — plus the hosted Notes PWA, connect-your-AI in minutes, and export-anytime. The governing invariant (amended D4): **shared vault-core + shared wire contract**; the runtime around core may diverge, deliberately and boundedly. The dedicated tier (~$25, full-parity stack on a VM) is unchanged and ships first; this document is the cheap tier's blueprint.

## 2. Substrate selection

The survey scored every credible per-tenant serverless shape (matrix in the survey; kills: Turso-alone fails the isolation bar — data-per-tenant under shared compute still lets an app bug cross tenants — and its vendor is deprioritizing the hosted DBaaS; Lambda+EFS corrupts SQLite over NFS; Aurora is the wrong database; Fargate has no real scale-to-zero; Railway can't orchestrate thousands of per-tenant instances). Two finalists:

| | **Durable Objects (+SQLite)** | **Fly Machines (+volume)** |
|---|---|---|
| Isolation | A — isolate + storage bound 1:1 to the object | A — microVM per tenant |
| **Durability/solidity** | **5-datacenter synchronous WAL replication (3/5 quorum) + 30-day point-in-time recovery, fully managed** | one NVMe slice on one host, **no replication**, daily snapshots docs warn "may not have your latest data"; HA/backup is yours to engineer |
| Rewrite | the runtime port (core goes behind a shim — §4) | none |
| Idle $/tenant @1GB | ~$0.20 (storage only; hibernated compute bills $0) | ~$0.20–0.30 provisioned — *if it truly idles*; open SSE/MCP keeps it awake and billing |
| Exit | data exits (portable-md); runtime is CF-specific | best-in-class (plain Docker + volume) |
| Ops | zero servers | HA, backups, incidents are ours |

**Selected: Durable-Object-per-vault.** Aaron's ranking — isolation and solidity above rewrite-avoidance and lock-in — points here unambiguously: DO wins the top-ranked axes and pays on the lower-ranked ones. The durability line alone is the answer to "not like our DIY DigitalOcean setup." **Named fallback: Fly Machines**, only if the Phase-0 spike falsifies the port economics — and only with an explicit HA/backup plan budgeted (a naive one-machine-per-tenant Fly deploy is *less* solid than the DigitalOcean setup we're leaving). **Watch item: Cloudflare Containers** — if persistent-disk snapshots ship (~12-month horizon), it could combine Fly's no-rewrite with DO's platform ops; not bettable in mid-2026.

Accepted exposure, stated honestly: Cloudflare has rare but total control-plane events (Nov 18 2025, 5h38m global). We accept correlated downtime risk in exchange for never operating storage ourselves; the dedicated tier (different substrate) remains the diversification.

## 3. Architecture

```
   Claude / ChatGPT / Claude Code          Notes PWA (Pages/CDN, static)
              │  MCP + OAuth                        │  REST + SSE/WS + OAuth
              ▼                                     ▼
   ┌─────────────────────────────────────────────────────────┐
   │  edge Worker — router                                    │
   │  <name>.parachute.computer → DO id  ·  discovery docs    │
   │  bearer pre-validation (scope-guard)  ·  CORS            │
   └───────────────┬─────────────────────────────────────────┘
                   │ one binding, one object per vault
                   ▼
   ┌─────────────────────────┐      ┌──────────────────────────┐
   │  Vault DO (per tenant)  │      │  Identity Worker (AS)     │
   │  · DO SQLite ← shim ←   │      │  authorize/token/DCR/JWKS │
   │    @openparachute/core  │      │  refresh rotation+grace   │
   │  · MCP sessions         │      │  revocation list          │
   │  · SSE / WS-hibernation │      │  state: D1 + secrets      │
   │  · hooks → live queries │      └──────────────────────────┘
   │  · cap enforcement      │      ┌──────────────────────────┐
   │  · export serializer    │      │  Control-plane Worker     │
   └────────┬────────────────┘      │  accounts·Stripe·dunning  │
            │ bytes                 │  provisioning = D1 row    │
            ▼                       │  (parachute-cloud reborn) │
   ┌─────────────────────────┐      └──────────────────────────┘
   │  R2: attachments ·      │
   │  export tarballs ·      │
   │  (later: mirror bundles)│
   └─────────────────────────┘
```

**The single-writer property is the keystone.** One DO per vault means every write, every post-commit hook, every open live-query stream, and every MCP session for that vault co-locate in one object. The bun runtime's hardest distributed problem (in-process hook dispatcher feeding a process-wide subscription singleton) simply disappears — the DO *is* the process, per tenant. And isolation is structural: a vault DO holds a handle only to its own SqlStorage; there is no path in our code that can name another tenant's data.

### 3.1 The Vault DO

- **Storage**: DO SQLite behind a `Database`-shaped shim (§4). Schema v23 ports as-is — FTS5 external-content, JSON1, FK cascades, NOCASE collations are all DO-supported; WAL/synchronous PRAGMAs become no-ops (DO owns durability).
- **Engine**: `@openparachute/core` — dependency-pure (zero npm deps, no `new Database()` anywhere; the handle is injected), runs unchanged behind the shim except for the transaction refactor (§4).
- **MCP**: the POST path is already stateless per request (`mcp-http.ts` builds a fresh server per call) — Worker forwards to the DO, which executes tools against local storage. The GET stream and session state live in the DO. Discovery-chain exactness (dual `.well-known` shapes, narrowed `scopes_supported`, `WWW-Authenticate resource_metadata`, the `Accept: application/json, text/event-stream` 406 rule, `?key=` fallback for Claude Web) is reproduced byte-shaped from the wire inventory — any subtle miss presents as an opaque connector failure.
- **Live queries**: v1 serves the existing SSE contract unchanged (fetch-streaming + Bearer header, snapshot→upsert/remove, reconnect-re-snapshots — the no-replay semantic makes drops self-healing). An open stream pins the DO awake and bills duration (~$1.3/mo for an 8h/day tab at 128MB) — so **Phase 4 adds a WebSocket-hibernation transport to surface-client** (try WS, fall back to SSE): hibernatable WS lets the DO sleep between events, restoring ~$0 idle even with a tab open.
- **Caps**: enforced in-DO at write time — `sql.databaseSize` + an R2-usage meter row vs the tenant's `cap_bytes` → the documented 413 shape. (The same check lands in bun-vault for parity — cap enforcement was already an M1 gate.)
- **Triggers/webhooks**: the core hook dispatcher runs in-DO; outbound webhook POSTs are plain `fetch`. Data-only v1 needs none of the agent-tier triggers; the mechanism ports for free.

### 3.2 Identity Worker (the highest-subtlety net-new piece)

Cloud vaults have no hub, so the issuer contract the hub provides today must be reproduced *exactly* — clients are byte-shape sensitive. From the wire inventory, the conformance bar: PKCE **S256 mandatory**; DCR (RFC 7591); token response carrying `services` (it's how clients find the vault URL at all); **refresh rotation with replay detection, one-generation 30s grace, family revocation on replay** (surface-client's Web-Locks + adopt-sibling-token behavior exists *because* of these exact semantics — diverge slightly and users get logged out in families); JWKS with `kid = base64url(SHA-256(pubkey PEM))`; the revocation list document; RFC 8707 `resource` + the broad-`vault:read vault:write`+`vault=` narrowing path AND the direct-narrowed path; `aud=vault.<name>` strict binding. State in D1; keys in Secrets. **Guard: an issuer-conformance test corpus that runs against both the hub and the Identity Worker** — same flows, same assertions — so the two issuers cannot drift.

### 3.3 Attachments, export, backup (the no-lock-in mechanics)

- **Attachments**: bytes were never in SQLite (metadata rows only) — they map to `R2://vault-<id>/attachments/…`, Worker-proxied with the same traversal/scope gates and the existing deny-list upload policy. R2 egress is free — exports don't bleed margin.
- **Export-anytime**: portable-md's byte-stable serializer (fixed key order, alpha-sorted nested keys, pinned by round-trip tests) is the product's no-lock-in promise. The cloud implements it as a **streaming** serializer (DO → R2 tarball → signed download): "Export vault" gives a tarball that `parachute-vault import` round-trips into a self-hosted box byte-identically. This replaces runtime parity as the ownership guarantee — and the streaming rewrite fixes the bun runtime's full-corpus-in-memory export too (shared-core win).
- **Backup**: three layers. (1) *Platform*: DO PITR — any point in the last 30 days, free, zero code. (2) *Portable*: nightly automated export tarball to R2 (the same serializer), retained N days — restore = import, anywhere. (3) *Later*: optional GitHub mirror via REST-API commits (no git binary on Workers; `Bun.spawn` git — the port's long pole — is simply not needed for v1).

### 3.4 Control plane, addressing, provisioning

- **The reborn `parachute-cloud`**: the CF steelman was right — the old Worker control plane is already CF-native; it gets revived in place (accounts, Stripe webhooks with signature-verify + event dedup, the dunning state machine) with its Fly provider deleted. **Provisioning is a D1 row**: allocate vault name → bind name→DO-id → done; DOs come into existence on first access. No boxes, no cloud-init, no fleet.
- **Addressing**: subdomain-per-tenant from day one — `<name>.parachute.computer` (wildcard cert + Workers routes make gate 6 free on this substrate). Reserved-name list; renames = new subdomain + redirect row.
- **The PWA**: notes.parachute.computer stays the one interface; its vault-URL discovery and OAuth (DCR path) work unchanged against the Identity Worker per the conformance bar.

## 4. The shared core — what changes in `parachute-vault` (and helps bun too)

The portability audit found the seam is real but leaky. Three refactors land as normal vault PRs (bun tests stay green — these are shared-core improvements, not cloud code):

1. **Close the `Store.db` leak** (`types.ts:264` + ~30 raw-`db` sites in routes/mcp-tools/triggers-api/cli/server + core's own `mcp.ts:178`): route through async Store methods. This makes Store the *only* doorway — the precondition for any second backend, and better layering for bun.
2. **Transaction abstraction**: the 13 imperative `BEGIN/COMMIT` blocks become `store.transaction(cb)` — bun backs it with `BEGIN IMMEDIATE`, DO with `ctx.storage.transactionSync(cb)`. (Explicit transaction SQL is blocked by DO's `sql.exec` — this is the one construct that cannot be shimmed.)
3. **Streaming export/import**: portable-md loses its sync-fs + full-corpus-in-memory shape in favor of a source/sink interface (fs on bun, R2 on Workers) — fixing the flagged single-tenant memory-spike hazard everywhere.

The **shim itself** is small by measurement, not hope: core calls only `prepare→get/all/run`, `exec`, and one `.changes` — all positional params, all synchronous, all immediately materialized; no named params, no `.iterate()`, no custom functions, no `safeIntegers` output marshaling (bigint appears only as an accepted *input* binding in `query-operators.ts:77` — the shim passes it through). DO's SqlStorage is synchronous, so the shim is mechanical (`.get` → `.toArray()[0] ?? null`, `.run` → map `rowsWritten`, PRAGMA no-op layer). **Four empirical unknowns gate everything** (undocumented on DO): generated columns, `ALTER TABLE ADD/DROP COLUMN`, `RETURNING`, and introspection PRAGMAs (`table_info`/`table_xinfo`) — all four are exercised by the boot path or the indexed-fields subsystem, and all four are Phase-0 spike items. The file-path-open/`VACUUM INTO` backup code (db.ts, auth-status.ts, backup.ts) has no DO equivalent and stays bun-only (its cloud role is covered by §3.3).

## 5. Shared vs. forked — the explicit ledger

| Shared (one source of truth) | Forked (deliberate, bounded) |
|---|---|
| `@openparachute/core` — engine, schema, query grammar, MCP tool semantics, hooks (with §4 refactors) | server runtime: `Bun.serve` routing ↔ Worker + DO class |
| `@openparachute/scope-guard` (pure jose+fetch; ports as-is — pin its in-memory JWKS/revocation caches to the Cache API so cold isolates don't fail closed) | attachment bytes: fs ↔ R2 |
| the wire contract: REST grammar, error discriminators (`error_type`, 409/428 OC bodies, `X-Next-Cursor`), OAuth flows, MCP discovery, SSE event shapes | backup: git-binary mirror ↔ PITR + R2 tarballs (+ GitHub-REST later) |
| portable-md format v1 (byte-stable) — the interchange + exit mechanism | issuer: hub ↔ Identity Worker (conformance-tested against each other) |
| the Notes PWA + surface-client (gains a WS transport, keeps SSE) | supervision: launchd/systemd ↔ the platform |

**Enforcement, not intention: the conformance suite is a first-class deliverable.** One HTTP/MCP/OAuth test corpus runs in CI against (a) the bun vault, (b) the DO vault under `workerd`, and (c) both issuers; plus a cross-runtime export test (DO-vault export → bun-vault import → re-export → byte-equal). Cross-runtime drift becomes a red build, not an archaeology project — the lesson of every convergence bug this ecosystem has already paid for.

## 6. Build plan

- **Phase 0 — the spike (2–3 days, DO NOW).** Shim + core test suite green under workerd (`@cloudflare/vitest-pool-workers`); empirically settle the four unknowns; FTS5 MATCH+rank timing on a 100k-note corpus in DO; `sql.databaseSize` accounting behavior. **Gate: unknowns green → this whole design is real; any red → Fly-fallback conversation with data in hand.**
- **Phase 1 — shared-core refactors** (vault repo, normal PRs): Store-doorway closure, `store.transaction`, streaming export. Bun suite green throughout; these merge on their own merits.
- **Phase 2 — the Vault DO + router**: notes/tags/attachments(R2)/query/storage endpoints against the conformance suite; caps in-DO; subdomain routing.
- **Phase 3 — identity + MCP**: the Identity Worker against the issuer-conformance corpus; MCP discovery chain; **gate: Claude.ai, Claude Code, and ChatGPT connectors work against a cloud vault with zero client changes.**
- **Phase 4 — live + PWA**: SSE serving, WS-hibernation transport in surface-client, notes PWA end-to-end; **gate: the PWA daily-driver flows (Today, capture, edit, live lists) against a cloud vault.**
- **Phase 5 — money + ops**: control-plane revival (accounts/Stripe/dunning), provisioning rows, export tarballs + PITR runbook, observability (tail workers, analytics engine), abuse fences (email verification, Turnstile), the trust-posture page. **Gate: the v1 doc's M2 gate list, re-mapped to this substrate.**

Honest sizing: Phase 0 in days; Phases 1–5 ≈ 6–10 focused weeks at this team's session cadence, with Phase 3 (issuer exactness) the highest-subtlety stretch. The dedicated tier earns money on boxes the whole way through — nothing here blocks first dollars.

## 7. Economics recheck

Per idle-heavy tenant at 1GB: storage ~$0.20/mo (first 5GB-mo of the account included), requests/rows/duration effectively $0 under hibernation with the WS transport; account minimum $5/mo Workers Paid amortizes across the fleet. **$3/mo (no scribe) carries ~90%+ marginal margin; the $1–2 tier stops being aspirational and becomes a pricing choice** once Phase 4 lands. Stripe's fixed fee (~15% at $2, ~6% at $5 for the $0.30 component) — annual billing from day one. Scribe stays out of these tiers (the one real per-use COGS).

## 8. Risks, ranked

1. **Issuer exactness** (rotation/replay/grace/family semantics) — mitigation: the conformance corpus + reusing hub's own test suite as the spec; §3.2.
2. **The four DO unknowns** — mitigation: Phase 0 gates everything; Fly is the named, pre-conditioned fallback.
3. **SSE duration cost** pre-WS-transport — mitigation: acceptable for beta scale; Phase 4 closes it; measure in Phase 2 telemetry.
4. **DO CPU-time budget** vs. big imports — correction from review: the 30s limit is *CPU time* (configurable to 5 min), not wall-clock, and it **resets on every incoming message** — so chunked imports need neither alarms nor special machinery: repeated small requests each get a fresh budget (the Obsidian-zip path already batches client-side). First lever if a single chunk is heavy: raise `limits.cpu_ms`.
5. **CF control-plane correlation** — accepted + disclosed (§2); dedicated tier diversifies.
6. **Lock-in** — mitigations are structural: portable-md tarballs (data), the bun runtime staying first-class in CI (the self-host product *is* the exit), and the Store dual-backend seam meaning core never becomes CF-shaped.
7. **Scope-guard cold-isolate revocation fail-closed** — pin caches (Cache API / a small DO), §5.

## 9. Open questions (small; none block Phase 0)

1. Subdomain style: `<name>.parachute.computer` (recommended) vs a `.vaults.` infix?
2. Repo home: rebirth `parachute-cloud` as the Workers monorepo (vault-do + identity + control-plane) — recommended, keeps its git history and harvested billing code in place?
3. Product name for the tier ("Simple Vault"?) — Layer-0 territory, defer to the site work.
4. Beta sequencing: does the DO tier's private beta replace or follow the dedicated-box beta? (Recommendation: follow — dedicated starts collecting dollars and lessons now; DO tier opens at Phase 4.)

---

*Tracked: team vault `Decisions/2026-07-02-cloud-do-per-vault` (the direction) · `Work/cloud-v1` (the arc) · the three inventories live in this session's record. Phase 0 spike is the first engineering task and its result amends this doc in place.*
