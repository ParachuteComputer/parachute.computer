# Execution Plan — ready for "go"

> Ratified by Aaron 2026-07-03; see `Work/launch-readiness-course` in the team vault.

**Date:** 2026-07-03 · **Author:** Uni · **Status:** RATIFIED — in execution
**Supersedes nothing** — this is the operational layer under the [approved course of action](/design/2026-07-03-launch-course-of-action/), with Aaron's decisions folded in.

## Your decisions, locked

| # | Decision | Locked value |
|---|---|---|
| 1 | Free tier | **1 vault, 100 MB** (motivate signup, protect COGS). Paid **$3/mo · $30/yr — 5 vaults, 10 GiB** |
| 2 | Paid tiers | One at launch |
| 3 | History | Daily backups on a **GFS rhythm** (dailies → weeklies → monthlies), paid-restore only, never metered into quota |
| 4 | FUBU | **Don't wait** — I write the homepage copy from the team transcript + our discussions |
| 5 | Accounts | Build in Unforced Development now; you create the dedicated parachutecomputer account early next week (everything I build is env-separated so the move is config, not surgery) |
| 6 | Surface Starter | Out of default seed; button/CLI to add |
| 7 | Drip | 3 emails, behavior-aware |
| 8 | Free restore | No — restore is paid; free = our internal DR only |
| + | GitHub backup | ~~In scope~~ **SUPERSEDED** — replaced by real git for cloud vaults (see the section note below) |

## The margin math (decision 1 + 2 sanity)

- Typical active vault costs us **$0.30–0.90/mo** (DO wall-clock dominates; SSE pinning is the driver — WS hibernation is the known future lever). An idle vault ≈ storage only, **~2¢/GiB-mo**.
- A realistic paid user (1 active vault + a couple idle, 1–3 GiB used): **COGS ≈ $0.40–1.20/mo → 60–85% margin at $3.**
- Free user at 100 MB, mostly idle: **< 2¢/mo.** Ten thousand free users ≈ $200/mo worst case — an acceptable growth spend, and the 100 MB ceiling caps it structurally.
- Snapshots: a full 100 MB vault × ~34 GFS points ≈ 3.4 GB R2 ≈ **5¢/mo** — noise.
- GFS retention (locked): **14 dailies → 8 weeklies → 12 monthlies** (max ~34 points, ~3 years of monthly reach). Free tier: 1 rolling weekly, internal-only.

## GitHub backup (your "rad" item — how it lands)

> **SUPERSEDED 2026-07-03.** Aaron rejected the GitHub-API backup in favor of real git for cloud vaults — see [`2026-07-03-git-for-cloud-vaults.md`](/design/2026-07-03-git-for-cloud-vaults/). The GitHub-API approach survives only as an optional mirror-push target later; the section below is kept for the record.

A Worker needs no git binary: the **GitHub contents/trees API** can commit files. Nightly (or on-demand), the vault's portable-md export is committed as *files* (not a tarball) to a **repo the user owns**, with their fine-grained PAT stored as a vault-scoped secret. That yields:
- **Real git history** of the vault, on their GitHub — the interim answer to "integrated git," free of workerd's limits.
- **The migration bridge**: the bun vault already imports portable-md — clone the repo, `parachute-vault import`, and a hosted user is self-hosted (or vice-versa: push a self-host mirror to GitHub, import to cloud).
- Tier call (my default, flag if you disagree): **available on all tiers** — it uses *their* storage and embodies export-anytime; R2 snapshot-restore stays the paid convenience. Nerds get freedom, everyday users get the button.
- Honest caveat shared with snapshots: v1 exports exclude attachment *binaries* (portable-md divergence, documented) — notes/links/tags are complete. Async attachment export is a fast-follow before we say "full restore" anywhere.

## The run — PR-by-PR

**Wave 1 — Front door** *(site + patterns repos; fully autonomous now that FUBU is unblocked)*
1. site: homepage promotion — landing takes `/`, `/v2/` redirects home, final copy pass in the team's voice (transcript phrases over mine), og-image, footer routes to blog/docs/start/roadmap.
2. patterns: migration file for the canonical-homepage change.
3. site: ToS + Privacy pages (short, honest, PBC-voiced) — prerequisite for Wave 4.
4. site: Cloudflare Web Analytics (cookieless). If site-creation needs dashboard perms my token lacks → snippet lands behind a 2-minute step on your ledger.

**Wave 2 — Production posture** *(cloud repo; parallel with Wave 1)*
1. Export-R2 retention/GC — the live leak — plus a manifest-based layout the GFS snapshots will reuse.
2. Environment split: **current workers become production** (`ENVIRONMENT=production` — debug echo dies on the live domain; e2e-* debris rows cleaned), **new staging workers + D1/R2** stood up for tests and the headless E2E. Deploy scripts per env, documented for next week's account move.
3. CI/CD: typecheck+vitest on PR (no secrets needed); staging deploy on merge + prod deploy on tag (needs a CF API token as a GitHub secret → your ledger, non-blocking).
4. Observability: health-check cron + failure email via send_email, weekly ops digest, alert on `magic_link_send_failed`/5xx.
5. Security: DO-backed rate limiter (#30); CORS reconcile (#35); KDF honestly — workerd caps PBKDF2 at 100k, no argon2 exists there, so the posture is *magic-link-primary + hardened throttles + password-as-secondary*, documented (#28 closes with rationale, not wishful crypto).

**Wave 3 — Guided arrival** *(core/vault + cloud + surface repos)*
1. core (parachute-vault): named **seed packs** — `welcome`, `getting-started`, `surface-starter`; bun suite green; rc chain per governance; Getting Started's wikilink softened; projection pointer intact.
2. vault: bun runtime seeds welcome+getting-started by default; `parachute vault add-pack` CLI.
3. cloud: DO seeds from the core packs (deletes tonight's duplicated content); console **"Add the Surface Starter"** button; cross-runtime parity test.
4. cloud: console first-run (name-your-vault hero + the two questions, answer №2 becomes her first note) + the persisted checklist card + the Connect-your-AI card (Claude connector walkthrough, copy-button MCP URL).
5. cloud: drip worker (day-0 / day-3-if-no-token-activity / day-14; unsubscribe flag).

**Wave 4 — Money** *(cloud repo)*
1. `plan` column + wiring: issuer pushes `cap_bytes` into the DO's existing (unwired) override seam; new vaults default free/100 MB; existing real vaults comped via admin.
2. Usage rollup cron → D1 `usage` table (databaseSize + R2 meter per vault, daily).
3. Admin console `/admin` (operator role, session-gated): users, vaults, usage, comps/overrides, suspend, send-failures, signups/day.
4. Stripe port from the old control plane (client/checkout/webhook-idempotency/lifecycle + their tests, Drizzle→raw-D1) + **customer portal** (new) + Stripe Tax. Built and unit-tested in full; **live checkout smoke waits on your Stripe keys** (your ledger, ~10 min, end of wave).
5. Snapshot history: nightly cron enumerates vaults → export → R2 under the GFS manifest; paid restore-to-new-vault endpoint + console UI; cap warnings at 100%, write-stop at 120%, reads/export untouchable.
6. ~~GitHub backup (stretch, after 5)~~ *(superseded — see [`2026-07-03-git-for-cloud-vaults.md`](/design/2026-07-03-git-for-cloud-vaults/); the git-for-cloud-vaults track replaces this item.)*

**Wave 5 — noted, not scheduled**: core note-versions design issue + git-remote tail, written up so the thinking isn't lost.

## Operating rules while I cook

- Every PR reviewer-gated; merges use the verified-conditional pattern; post-merge hygiene only after `state=MERGED`.
- The **browser E2E re-runs at every wave boundary** (against staging once it exists) — the funnel is the regression suite.
- Wave boundaries get: a team-vault work-note update + a direct progress report with evidence (files/screenshots sent to you, not paths).
- **I stop and wait only for**: anything that deletes user data, live-payment activation, DNS/domain moves beyond this plan, or spend anomalies. Everything else proceeds on this document's authority.
- Ambiguities get decided by this doc's principles (door-not-manual; money-buys-room-never-rescue; export-always), logged in the work note, and flagged in the next report — not queued on you.

## Your ledger (all non-blocking until late Wave 4)

1. ~~Cloudflare email~~ ✅ done tonight.
2. **Real-inbox magic-link test** (2 min, whenever — before Wave 2 flips production it validates delivery).
3. CF API token → GitHub secret for auto-deploy (2 min, when Wave 2 PR asks).
4. **Stripe account + test/live keys** (~10 min, end of Wave 4).
5. Dedicated parachutecomputer CF account (next week, your move — everything will be ready to lift).
6. A design read of the promoted homepage with Neil whenever you two are ready — it ships first, iterates after.

**Say go, and Wave 1 + Wave 2 start in parallel.**
