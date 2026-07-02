# Cloud substrate deliberation — thin-around-hub vs. Cloudflare-native

*Design doc — 2026-07-02. Status: **RECOMMENDATION for Aaron**. Addendum to [`2026-07-01-parachute-cloud-v1.md`](./2026-07-01-parachute-cloud-v1.md). Method: two adversarial steelmen (VPS, Cloudflare) + a neutral workload analyst who measured the real system; every load-bearing fact below was verified against code, a live box, or vendor docs dated July 2026.*

Aaron's ask: *"think deeply about whether we should just be doing this thin wrapper around hub, or whether cloud should be its own thing on more easily scalable architecture such as Cloudflare — better to take time upfront to nail this than cut corners."*

## 0. The correction that reframes everything

Every prior cloud plan (including the 06-28 research and the v1 doc's own assumptions) reasoned from a wrong process model. **Production is ONE multi-vault bun process per box** — `parachute-vault serve` serves every vault on the box from one process, one port, one event loop; each vault is its own SQLite file (verified: `src/server.ts`, `self-register.ts`, `routing.ts`; one live process on the team box). `parachute vault create` does not fork a daemon.

Measured live (Bun 1.3.x): the daemon settles ~40MB; **each additional warm vault costs ~1–3MB at rest**; 50 vaults ≈ 107MB total; 10k notes adds ~4MB (SQLite is disk-backed); throughput ~353 req/s against a personal-vault duty cycle of single-digit requests per *minute*.

Consequences: **RAM density is a non-issue** (the "measure RAM-per-vault" gate was mis-specified); the real pooled-shape constraints are (1) **blast radius** — one process/upgrade/OOM drops every co-tenant, present the moment a second stranger pays; (2) **noisy neighbor on the shared event loop** — one tenant's heavy operation (full-corpus export loads everything in memory via `portable-md.ts`; even FTS-backed search costs ~108ms @ 100k notes — note: vault search *is* FTS5-indexed, `schema.ts:257`/`notes.ts:1213`; SCALE.md's "no FTS" prose is stale, and the real engineering question is why MATCH + rank still costs 108ms on a large corpus) stalls everyone; (3) **fleet ops** beyond box #1. Infra cost per pooled tenant is ~$0.12–0.24/mo at every scale — *the cost of the VPS shape is reliability engineering, ops, and — see §2a — isolation, not dollars.*

## 1. What each perspective established (the surviving facts)

**For the VPS shape:** the drift-dividend is empirical, not theoretical — four cloud-provoked fixes shipped to every self-hoster in the last month alone (multi-origin iss-set across 4 repos, upload deny-list, account self-serve stack, the shared installer). One codebase keeps the AGPL "runs without us" promise *literally* true, and cloud-as-dogfood is the brand. Cheapest to operate across the entire 0→1,000-tenant range where this business lives pre-break-even.

**For the Cloudflare shape:** stronger than assumed, in one specific form. `vault-core`'s Store API is *already async, with DO-SQLite named in the code as the intended second backend* (`store.ts:39-42`) — and since Durable Objects' SqlStorage is *also synchronous* and supports FTS5, generated columns, and `json_extract` (10GB/object vs our 1GB cap), the core port is a bounded `Database`-shaped shim (~300 LOC of shim code, though its surface must satisfy the 16 core files that import `bun:sqlite`'s `Database` directly — the fit spike sizes this precisely), not surgery. On DOs, scale-to-zero makes the $1–2 vault the *default* economics (~$0.05–0.20/tenant/mo marginal, hibernated objects bill zero duration) and four of the v1 doc's nine gates (ceilings, subdomain isolation, fleet ops, density measurement) cease to exist. The honest costs: the ~30k-LOC bun *runtime* around core is the real port (git mirror is the long pole — `Bun.spawn` git cannot exist on Workers; backup there means isomorphic-git→R2 or GitHub REST), plus CF lock-in and a hosted runtime that is no longer the self-hoster's runtime below core.

**Killed outright:** CF *Containers* as the "run the unmodified image, scale-to-zero" escape hatch — **container disk is ephemeral**; a slept vault loses its SQLite. Never-sleep containers cost like VMs. Dedicated *VMs* below ~$15 are also dead ($6 floor > $3–5 price).

**No-regret regardless of shape:** Notes PWA (and hub static) on CDN/Pages; **R2 for attachments** ($0.015/GB-mo, zero egress — attachments dominate any real 1GB vault, and moving them off box disk shrinks the biggest pooled-storage pressure).

## 2a. The isolation question (Aaron, 2026-07-02 — and it changes the weighting)

> "I'm really worried that we're gonna end up accidentally leaking data between vaults and users because they all exist on one hard drive. If somebody figures out how to escape their little isolated thing, all the other people's information is right there."

This concern is **correct, and the current shape is worse than the phrasing implies**: on today's single-process model there is no "little isolated thing" to escape. Tenant separation is application-layer only — OAuth scopes, `aud`-binding, and path routing *inside one bun process* with every tenant's SQLite file readable on one disk by that process. An attacker doesn't need a sandbox escape; they need **one application bug** (a path-traversal, a scope-check miss, a query that forgets its vault filter) anywhere in ~45k LOC of vault+hub. One bug = every co-tenant's data. This is the textbook weakest tier of multi-tenancy, and it is the standard reason strangers are never co-hosted on it.

The isolation ladder, honestly:

| Rung | Boundary | What an attacker needs | Cost |
|---|---|---|---|
| 0. Single process, app-layer checks (today) | none (logical only) | one app bug | $0 — **trusted circles only, never strangers** |
| 1. Process-per-tenant + OS-user-per-tenant + 700-mode data dirs (+ systemd hardening/cgroups) | OS process/user boundary | app bug **and** local privilege escalation | ~40MB RAM/tenant (measured daemon base) + supervisor work in hub |
| 2. VM-per-tenant (dedicated) | hardware virtualization | app bug + VM escape | $6+/tenant floor |
| 3. DO-per-vault (Cloudflare) | platform-enforced per-object storage in a professionally-hardened multi-tenant runtime | a Cloudflare runtime bug — **our** code can no longer address another tenant's data at all | the port (§1) + CF lock-in |

Two readings matter. First, **"native cloud" (rung 3) genuinely answers the fear**: with one DO per vault, another tenant's data is not merely guarded from our code — it is *unaddressable* by it; the cross-tenant attack surface moves from our 45k LOC to Cloudflare's runtime, whose isolation is their core business. Second, **rung 1 gets most of the way there on our own boxes**: per-tenant processes under per-tenant OS users means a vault-code bug exposes only that tenant's files — and it doubles as the blast-radius/noisy-neighbor fix, and benefits self-host multi-user (friends-hosting) too. What is *not* acceptable is shipping strangers on rung 0.

## 2. The recommendation (revised for the isolation weighting)

**Ship first dollars on dedicated boxes (already rung-2 isolated), never put strangers on the single-process pool, and buy the Cloudflare option now — because the isolation lens makes DO the leading candidate for the cheap tier.** Concretely:

1. **M1 beta = dedicated-first** ($15–25, one VM per tenant off the identical installer — the strongest boundary we own, zero new code). The shared single-process pool is re-scoped to its actual design point: *trusted circles* (self-host, friends-hosting) — it does not take paying strangers at any price. The $3–5 "Simple Vault" tier ships only on a real per-tenant boundary: **DO-per-vault if the fit spike passes (preferred — it answers the isolation concern by construction), or rung-1 process/OS-user isolation on our boxes as the fallback.**
2. **Run the 1–2 day DO fit spike now** (before pricing is advertised): port just the Store behind the shim to a DO-SQLite prototype; confirm a 1GB vault imports and performs, measure an MCP session's real request/duration cost, prove SSE over hibernatable WebSockets. This converts the biggest unknown from folklore to fact for ~two days of work, and keeps the $1–2 destination open *by construction* (the seam becomes CI-tested instead of aspirational).
3. **Replace the mis-specified density gate with the two real measurements**: (a) concurrent-heavy-op ceiling per box (p99 of light reads on other vaults while M exports/searches run); (b) single-tenant export peak RSS. Fix the two hot spots regardless of substrate: streaming/chunked export (SCALE.md's own flagged item), and profile why FTS5 MATCH + rank still costs ~108ms at 100k notes (search is already FTS-indexed — the work is rank/match-set cost, not adding an index). Both are self-host wins too.
4. **Do the no-regret hybrid pieces when convenient**: R2 for attachments, CDN for static. Skip the edge-Worker front for now (it solves no binding constraint).
5. **Defer the control-plane home decision to M2.** M1 needs payment links and a CLI, not a service. Whether the control plane is bun-on-a-box or the (already CF-native) old parachute-cloud Worker is a cheap, reversible choice better made after the DO spike reports — this also dissolves the v1 doc's "rewrite bun-native" vs "keep the Worker" disagreement without building either prematurely.
6. **Name the destination honestly**: if the fit spike passes and any tripwire below fires, the pooled tier's future is **DO-per-vault** (one core codebase, two Store backends; the runtime around it forks and we accept that *for the pooled tier only*), while dedicated stays "the identical stack, operated for you" — preserving exact AGPL parity where the pitch depends on it.

## 3. Tripwires (falsifiable, revisit-triggers)

| # | Condition | Action |
|---|---|---|
| 1 | We want to *advertise* a sub-$5 price | DO spike must have passed; begin the pooled-tier DO port |
| 2 | >~1,000 paying vaults or >3 boxes | Stand up the full fleet reconciler OR start the DO migration — whichever the spike priced cheaper |
| 3 | Ops >~6 hrs/week before ~500 tenants | The cattle-box model isn't one-human-operable; escalate (reconciler now, or DO) |
| 4 | Concurrent-heavy-op measurement shows the shared event loop can't hold p99 with >~50 active tenants/box | Per-tenant process mode or DO — isolation becomes load-bearing |
| 5 | v1 scope expands to code-publishing tenants | Different problem entirely: dedicated VMs / real containers; re-open the substrate question |
| 6 | DO fit spike FAILS (1GB perf, MCP cost, or SSE) | Strike DO; the cheap tier's path becomes rung-1 process/OS-user isolation on our boxes; price accordingly ($3–5 floor, not $1–2) |

**Standing rule (not a tripwire):** no paying stranger ever lands on the rung-0 single-process pool. Isolation is a launch precondition of the cheap tier, not a scaling response.

## 4. What would change this recommendation

The three facts each side nominated, preserved: (1) the concurrent-heavy-op ceiling coming back much worse than the RSS numbers suggest (pushes toward DO or per-tenant processes sooner); (2) the audience question reopening to code-publishing (pushes to VMs/containers, away from both pooled shapes); (3) the DO spike revealing the port is materially bigger than the shim analysis claims (kills the $1–2 destination and makes $3–5 the honest permanent floor — which, per Aaron, may be acceptable: "$5 might be the better starting point").

*Pricing note (Aaron, 2026-07-01): the working tier instinct is $3 without scribe / $5 with scribe. Held until the concurrent-ceiling measurement lands; annual billing (drops Stripe's fixed fee from ~13% to ~3% at $3) should ship whenever the $3 tier does.*
