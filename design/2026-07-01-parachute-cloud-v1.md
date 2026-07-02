# Parachute Cloud v1 — pay us money, get a vault

*Design doc — 2026-07-01. Status: **DIRECTION** (D4 ratified by Aaron 2026-07-01: data-only v1, control plane around hub, harvest-not-revive parachute-cloud). **Substrate addendum:** see [`2026-07-02-cloud-substrate-deliberation.md`](./2026-07-02-cloud-substrate-deliberation.md) — corrects this doc's process-model assumption (one multi-vault process per box, not process-per-vault), replaces gate 9's density measurement with the concurrent-heavy-op ceiling, and adds the DO fit spike + tripwires. Author: uni/session (with Aaron). Builds on the 2026-06-28 cloud product plan (team vault `Strategy/2026-06-28-parachute-cloud-plan`); supersedes `2026-04-20-cloud-offering-sketch.md`, `2026-05-26-fly-migration-path.md`'s runtime substrate, and the v0.6 doc's "single container" framing for cloud purposes.*

## 1. The product, in Aaron's words

> "The core offering is literally just: people pay us money, and they get a vault. $X means you get a vault with up to 1GB stored."

**The unit a customer buys is a vault** — not a server, not a seat, not an app. Data-only in v1: nothing a customer uploads ever executes on our infrastructure. What arrives with the vault:

- **A vault at a stable URL** — their coordinates, reachable by any MCP client.
- **The Notes app** — the hosted, auto-updating PWA (notes.parachute.computer) connected to their vault. No install, no version to manage. (The Layer-1 daily-driver work is the same product motion.)
- **"Connect your AI" in minutes** — Claude.ai / Claude Code / ChatGPT via OAuth; the vault's Getting Started note orients the AI (the Layer-1 interview→propose protocol lands here too).
- **Backup + export, always** — automatic git mirror; lossless export at any moment. The no-lock-in promise is a *priced-in feature*, not a caveat.
- **Import** — Obsidian/markdown at v1 (the Layer-1 importer unification feeds this directly).

What v1 deliberately is **not**: custom surface code (Layer 2), native agents (Layer 3), orgs/teams self-serve, or a free tier. Cloud v1 = **hosted Layer 1**.

## 2. Architecture — a thin control plane *around* unmodified hubs

```
                    ┌──────────────────────────────┐
  stripe ⇄  billing │   cloud control plane (bun)  │  waitlist / signup
                    │  accounts · plans · dunning   │
                    │  provisioning · fleet registry│
                    └───────┬──────────────┬───────┘
                    admin API (operator)   │ cloud-init (digitalocean.sh)
                    ┌───────▼──────┐  ┌────▼─────────┐
                    │ shared box(es)│  │ dedicated box │   ← standard, UNMODIFIED
                    │ hub + N vaults│  │ hub + 1 tenant│     @latest installs
                    └──────────────┘  └──────────────┘
```

- **The control plane** is a new, small bun+SQLite service (reborn in the `parachute-cloud` repo, bun-native — the Worker/D1/Fly runtime is discarded; the billing lifecycle design — dunning state machine, accounts schema, `ProviderClient` seam, Stripe signature-verify + event dedup — is harvested, ~30-40% logic reuse). It owns exactly what a tenant's hub never should: accounts, Stripe, DNS, fleet state, provisioning orchestration.
- **Boxes are stock Parachute.** Every box runs published `@latest` packages installed by the same `digitalocean.sh` a self-hoster runs. The control plane drives hubs only through their existing public seams: invite redemption, `provisionVault`, `setVaultCap`, usage read, and first-admin bootstrap — preferring the same browser bootstrap-token flow self-host operators exercise (`digitalocean.sh` deliberately avoids env-var admin seeding; the `PARACHUTE_INITIAL_ADMIN_*` env path exists but is the less-tested route, so the control plane automates the token handshake rather than diverging onto it). **The no-drift invariant: if the control plane needs a hub change, the change ships in hub for everyone, or it doesn't ship.** (To be codified as `parachute-patterns/patterns/cloud-no-drift.md` with the ratification migration file.)
- **Two substrates, one product.** A vault lives on a **shared box** (separate SQLite DBs served by one multi-vault process today — see the [substrate addendum](./2026-07-02-cloud-substrate-deliberation.md) §2a: that rung-0 shape is for trusted circles only; the paying-stranger cheap tier requires a real per-tenant boundary) or a **dedicated box** (one tenant, one VM — the strongest boundary we own). The customer buys a vault either way; the substrate is a tier attribute. Lossless export/import is the migration mechanism between them.

## 3. Secure and solid — the gates, honestly

Being able to *technically* host strangers and being *ready to charge them* are different. These are the gates, grouped by when they must hold:

**Before charging anyone (M1 gates):**
1. **Storage-cap enforcement** — hub stores `cap_bytes` today; the vault data plane has zero readers. Wire cap → upload/write-time 413. (vault PR; the tier system is fiction without it.)
2. **Backup you'd bet on** — automatic per-vault mirror on by default **plus a tested restore drill**. A paid vault without a rehearsed restore is negligence.
3. **Account self-serve** — a paying customer manages their own life: see usage vs cap, revoke own tokens, change password, export, delete (the #715 cascade). The current "to revoke it, ask the hub operator" is the anti-cloud.
4. **Trust posture, written down** — on a shared box we *can* read tenant vaults (the operator token is root over the box). Disclose it plainly; dedicated tier is the privacy answer; at-rest encryption is roadmap, not v1.

**Before public self-serve (M2 gates):**
5. **Per-tenant resource ceilings** — memory/CPU/request-rate per vault process, so one runaway tenant can't degrade siblings (today: nothing beyond crash-loop throttle).
6. **Subdomain-per-tenant origin** (`<name>.parachute.computer`) — a real same-origin boundary + clean OAuth/cookie separation (today: single-hostname ingress; path-based is acceptable for an invite-gated beta of known people, not for strangers).
7. **Abuse fences** — email verification, Turnstile on signup, the shipped rate-limit pooling, Stripe Radar defaults.
8. **Fleet operability** — minimal `sshExec` upgrade script across boxes + uptime/disk alerting + an incident runbook. (friends stranded on an old rc for weeks is the proof this can't be manual.)

**Before cheap tiers (M3 gate):**
9. **Measured density** — ~~RAM-per-vault-process~~ *(superseded by the [substrate addendum](./2026-07-02-cloud-substrate-deliberation.md): production is one multi-vault process, RAM is ~1–3MB/warm vault and not the constraint)* — the real measurements are the concurrent-heavy-op ceiling per box and single-tenant export peak RSS; and per §2a the cheap tier additionally requires a real per-tenant isolation boundary before any stranger lands on it.

## 4. Pricing — honest now, cheap later

| Tier | What | Price | When |
|---|---|---|---|
| **Simple Vault** | vault + notes app + AI connect + backup, 1GB cap — ~~shared box~~ *on a real per-tenant boundary (DO-per-vault or process/OS-user isolation — [addendum §2a](./2026-07-02-cloud-substrate-deliberation.md); the rung-0 shared pool never takes paying strangers)* | **~$3-5/mo** | ~~M1~~ M2, gated on the boundary |
| **Bigger caps** | 5GB / 10GB steps | +$3-5/step | M2 |
| **Dedicated** | own box, own origin, privacy posture, all caps off | **~$25/mo** | **M1** (manual) — the beta tier, per §2a |
| **$1-2 entry** | isolated cheap tier at real density | aspirational | M3, gated on the DO spike + measurements |

Rationale: $5 clears worst-case shared-box COGS *before* density is measured (and Stripe's fee — 2.9% + $0.30 — is ~$0.45 ≈ 9% of $5, vs ~$0.36 ≈ 18% of $2). The $1-2 vision is the destination — it becomes real when density is a measurement, not an assumption. **Trial-not-free**: a 14-day card-on-file trial instead of a free tier (a free tier on shared boxes is an abuse magnet and a COGS leak before ceilings exist). Scribe/transcription is **not** in v1 tiers (it's the one real per-use COGS; BYO-key or a metered add-on later).

## 5. The landing sequence

- **M0 — the gates that are pure engineering (start now):** cap enforcement · backup-default + restore drill · account self-serve completions · the density load test · the written trust-posture page (gate 4 — a doc, not code) · one waitlist mechanism on the site (D1 worker + `cloud` flag; retire the substack fork). All of this is valuable for self-host + friends even if cloud slipped.
- **M1 — private beta, real money (~5-15 people):** ~~$5 Simple Vault on a shared box~~ *(superseded by [addendum §2a](./2026-07-02-cloud-substrate-deliberation.md): no paying stranger on the rung-0 pool)* — **dedicated-by-hand at ~$25/tenant**: fresh droplets off the standard installer, waitlist/friendlies, Stripe payment links, provisioning via a control-plane CLI driving hub seams. The goal is *learning + the first honest dollars*, not automation. The cheap tier follows at M2 on a real boundary.
- **M2 — self-serve:** signup → verify → pay (Stripe Checkout) → vault provisioned → welcome email with coordinates + first-hour guide. Subdomain-per-tenant. Public CTA lands with the Layer-0 site rework (which has its own pending context from Aaron).
- **M3 — density + cheap tiers:** second box, fleet reconciler, measured pooled pricing, dedicated self-serve, pooled→dedicated migrator.

## 6. Reuse vs. build (the build is smaller than it looks)

**Exists, reused as-is:** hub invite/provision/cap/usage/seed-admin seams · `digitalocean.sh` zero-SSH install · multi-origin iss-set · per-vault OAuth + `aud`-binding isolation · vault git mirror · the hosted Notes PWA · Getting Started seeding (+ the Layer-1 rewrite in flight).
**Harvested (design, rewritten bun-native):** parachute-cloud's billing lifecycle + accounts schema + ProviderClient seam.
**Net-new:** the control plane service · cap-enforcement vault change · resource ceilings · restore drill + alerting · subdomain ingress · waitlist flag · the ops runbook.

## 7. Open questions (small, none blocking M0)

1. **Beta price**: $5 Simple Vault feel right, or start $8-10 and discount early birds?
2. **Scribe in tiers**: defer entirely (recommended), BYO-key, or metered add-on at M2?
3. **Beta box**: fresh droplet (recommended) vs the friends box?
4. **Repo**: rebirth `parachute-cloud` bun-native under the existing name/history (recommended) vs a fresh repo?

---

*Tracked in the team vault: `Decisions/2026-07-01-cloud-shape-d4` (accepted) · `Work/cloud-v1` (the arc) · `Strategy/2026-06-28-parachute-cloud-plan` (the research foundation). A `parachute-patterns/migrations/` propagation file ships when the first control-plane PR lands.*
