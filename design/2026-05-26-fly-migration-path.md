---
title: "Fly.io migration path — self-host and hosted on one substrate"
description: "Chart of work to migrate self-host from Render to Fly while standing up a parachute.cloud paid offering on the same substrate. Two tracks, one image, portable both directions."
---
# Fly.io migration path — self-host and hosted on one substrate

**Date:** 2026-05-26
**Status:** Proposal. Pre-implementation. Decision point ahead for Aaron.

**Companions:**
- [`2026-05-18-v06-deploy-architecture.md`](./2026-05-18-v06-deploy-architecture.md) — current Render-based deploy shape; this doc proposes the next substrate
- [`2026-04-20-cloud-offering-sketch.md`](./2026-04-20-cloud-offering-sketch.md) — long-horizon multi-tenant sketch (subdomain-per-tenant, Postgres-backed); this doc proposes an interim shape that delays the heavy migration
- [`parachute-hub/render.yaml`](../../parachute-hub/render.yaml) — current Render Blueprint, the artifact being mirrored

## The proposal

**One substrate (Fly.io), two delivery shapes (self-host + hosted), one image.**

A single Fly app definition serves both paths: an operator self-hosting runs the same image in their own Fly org; parachute.cloud runs many copies of the same image, one per operator, in our org. Migration between the two is a `fly volume snapshot` + restore — no data migration, no schema translation, no scope change.

This is a strategic departure from the cloud-offering sketch (multi-tenant Postgres with row-level security). That shape is still the right north star for scale-out, but it requires a major data-layer rewrite and assumes we want one shared backend for many users. Single-app-per-operator on Fly defers that rewrite indefinitely while still enabling a paid offering — operators get strong isolation, we get clean cost-per-customer accounting, and we keep the option to consolidate later if the unit economics warrant.

## Why Fly over Render (and why now)

Three drivers, ordered by importance:

1. **Lock-in symmetry.** Render's deploy is a one-way trip for self-hosters: their disk lives in Render's blob store with no portable snapshot. If we onboard 50 operators to Render-hosted-by-us and later decide to move, we're either eating 50 manual migrations or telling people "deploy yourself elsewhere." Fly volumes have `fly volumes snapshot create` and restore-into-other-org as a first-class operation. The escape hatch exists day one for self-hosters and for us.
2. **Same substrate top-to-bottom.** Operator-self-host and parachute.cloud-hosted run the same `fly.toml` and the same image. One CI pipeline. One bug-fix path. One ops mental model. Render forces a fork: the Render Blueprint is operator-side; a hosted offering on Render would mean a separate code path (multi-service, multi-disk, completely different shape). Fly collapses that.
3. **Cost shape.** Fly shared-cpu-1x 512MB in `iad` is $3.47/mo all-in (compute + 1GB volume) vs Render Starter at $7/mo. The delta funds the paid offering's margin: charge $10/mo, pay $3.50, the rest covers ops + support. Render's $7 floor crushes the margin on a low-end tier.

The non-driver: **reliability is a wash.** Fly's edge has had bad weeks (`fly-proxy` regressions, IAD outages). Render's edge has its own bad weeks ([hub#399](https://github.com/ParachuteComputer/parachute-hub/issues/399) — Oregon `portdetectorv2` flap, currently affecting the Aaron deploy intermittently). Neither has Vercel's SLA. **Don't migrate for reliability** — migrate for lock-in symmetry and substrate alignment.

## Track 1 — self-host on Fly (replaces Render as primary path)

### What changes in `parachute-hub`

| Artifact | Render today | Fly proposed |
|---|---|---|
| Deploy config | `render.yaml` | `fly.toml` |
| Deploy command | git push + auto-deploy | `fly launch` (first time), `fly deploy` (updates) |
| Persistent disk | Render Disk @ `/parachute` | Fly Volume @ `/parachute` |
| Env-var injection for setup | Render dashboard | `fly secrets set` |
| Auto-detected origin env | `RENDER_EXTERNAL_URL` | `FLY_APP_NAME` → `https://<app>.fly.dev` |
| Build context | Render's builder | Fly's `remote-only` builder (default) or local Docker |
| Region | One default (oregon) | Operator picks at launch (default `iad`) |
| Plan + scaling | Starter / Standard tiers | `[[vm]]` block, shared-cpu-1x default |
| Health check | `healthCheckPath: /health` | `[[services.http_checks]]` on `/health` |

### Code changes required

1. **Add `fly.toml`** alongside `render.yaml`. Both stay in the repo during transition; docs default to Fly, Render kept for operators already deployed.
2. **`src/hub-server.ts:263`** — extend `canonicalOrigin` resolver to recognize `FLY_APP_NAME` (compose `https://${FLY_APP_NAME}.fly.dev` when set, same precedence position as `RENDER_EXTERNAL_URL`).
3. **`src/setup-wizard.ts:236`** — `auto-skip expose` step recognizes Fly the same way it recognizes Render. The check is "is the platform routing this URL publicly without us doing anything?" — both platforms do.
4. **`src/api-hub.ts:145`** — Fly equivalents for `RENDER_GIT_COMMIT` / `RENDER_GIT_BRANCH` are `FLY_RELEASE_COMMAND` + `FLY_REGION` (different shape; revisit what the admin "build info" panel actually needs).
5. **No changes needed** in services-manifest, port handling, supervisor, or modules — those are platform-agnostic. The PORT env-var + `0.0.0.0` bind pattern is identical on Fly.

### Deploy-from-fork ergonomics

Render's killer feature is the Deploy Button — a Render-hosted URL that takes a `render.yaml` repo and provisions everything. Fly doesn't have an exact equivalent, but it's two commands:

```sh
gh repo fork ParachuteComputer/parachute-hub --clone
cd parachute-hub && fly launch --copy-config
```

For first-time-Fly users this requires installing `flyctl` (one-line on macOS/Linux/Windows). That's friction vs Render's "click button, paste env vars." Mitigations:

- **`scripts/deploy-to-fly.sh`** — one script that detects flyctl, installs it if missing, runs `fly launch --copy-config --yes`, prints the URL.
- **README updates** spelling out the three-step path.
- **Eventually**: a Vercel/Netlify-style "Deploy to Fly" button. Community projects have built these; Fly hasn't shipped an official one. Worth a small effort to package one.

### Pricing (self-host)

Operator-side cost on Fly @ shared-cpu-1x 512MB + 1GB volume, always-on:

| Region | Compute/mo | Volume/mo | Total |
|---|---|---|---|
| `iad` (Virginia) | $3.32 | $0.15 | **$3.47** |
| `sjc` (San Jose) | $4.05 | $0.15 | **$4.20** |
| `lhr` (London) | similar to sjc | $0.15 | ~$4.20 |

Render Starter equivalent: **$7.00/mo flat** regardless of region. Operator saves $3-3.50/mo on Fly. Not a huge absolute number, but the percentage gap (~50%) is meaningful as a marketing point and the snapshot-portability story is the real win.

256MB shared-cpu-1x ($2.17 iad / $2.62 sjc) would work for hub-alone deployments but is tight once vault + scribe + notes are all supervised. Recommend 512MB as the default; advanced operators can downsize.

### What we lose

- **Render's auto-deploy from GitHub push** — gone unless we add a GitHub Action that runs `fly deploy` on push. Worth doing; pattern is well-trodden.
- **The Deploy Button itself** — until/unless we build/find a Fly equivalent, the first-touch is `flyctl` install. Documentation can soften this but it's real friction.
- **Render's Web UI for env vars and logs** — Fly has a Web UI too (`fly.io/dashboard`), but it's less polished. Most ops happen via `fly secrets`, `fly logs`, `fly ssh console`. Operators comfortable with a CLI win; click-only operators lose.

## Track 2 — hosted on Fly (parachute.cloud)

### Architectural shape

**One Fly app per operator, all in our org `parachute-cloud`.** Each app is the same image as the self-host path, parameterized by env vars + their own volume.

```
parachute-cloud (Fly org)
├── operator-acme            ← app, $3.47/mo cost basis
│   ├── machine-1            ← shared-cpu-1x 512MB
│   └── volume               ← 1GB, /parachute mount
├── operator-bravo
├── operator-charlie
└── ... one per signup
```

### Per-operator lifecycle

1. **Signup at parachute.cloud** → email + password + plan selection (Stripe Checkout).
2. **Webhook from Stripe** hits our provisioning service.
3. **Provisioning service** calls Fly Machines API:
   - `flyctl apps create operator-acme --org parachute-cloud`
   - `flyctl volumes create parachute-home --region iad --size 1`
   - `flyctl deploy --image registry.fly.io/parachute-hub:<current-tag>`
   - `flyctl secrets set PARACHUTE_HUB_ORIGIN=https://acme.parachute.cloud ...`
4. **DNS update** — CNAME `acme.parachute.cloud` → `operator-acme.fly.dev` (Cloudflare API).
5. **TLS** — Fly auto-provisions Let's Encrypt for custom domains via `flyctl certs add`.
6. **Welcome email** — link to `https://acme.parachute.cloud/admin/setup` with the bootstrap token surfaced (pulled from provisioning logs).
7. **Done.** Operator's hub is theirs. They install modules from the admin SPA same as a self-host operator would.

### Updates orchestration

When we ship a new hub version:

```sh
# After CI publishes hub@<v>, push the matching image to Fly registry
flyctl auth docker
docker pull ghcr.io/parachutecomputer/parachute-hub:<v>
docker tag ... registry.fly.io/parachute-hub:<v>
docker push registry.fly.io/parachute-hub:<v>

# Then roll across all operator apps
flyctl apps list --org parachute-cloud --json | \
  jq -r '.[].Name' | \
  xargs -I{} flyctl deploy --app {} --image registry.fly.io/parachute-hub:<v>
```

This is "blue-green per app" — Fly's `release_command` + healthcheck flips traffic only when the new machine is healthy. Each operator gets ~30s of degraded service during their roll; we'd spread the rollout over hours to avoid all-at-once.

Eventually we'd want a control-plane app that:
- Watches the npm registry for new `@openparachute/hub` versions
- Auto-promotes through canary (10% of operators) → wide rollout
- Tracks per-operator deploy status + rollback button

But Phase 2 is fine with manual orchestration.

### Pricing math (hosted)

Per operator on Fly:
- Compute: $3.32/mo (iad shared-cpu-1x 512MB)
- Volume: $0.15/mo (1GB)
- Snapshot: 5-day retention free under 10GB allowance
- **Cost basis: ~$3.50/mo per operator**

Plus shared infra:
- Cloudflare DNS: free tier handles 10K req/mo per zone
- Stripe: 2.9% + $0.30 per transaction
- Provisioning service (Fly app): $3.50/mo total, scales to thousands
- Support email (Postmark/Resend): $0-15/mo

**Pricing tiers (proposed):**

| Tier | Price/mo | Operator gets | Margin |
|---|---|---|---|
| Self-host | $0 (we collect nothing) | Their own Fly app, their own bill | $0 |
| Solo | $10 | Hosted on parachute.cloud, 1GB disk, custom domain | $6.50 |
| Plus | $25 | 10GB disk, priority support, scribe paid-tier defaults | ~$18 |
| Pro | $50 | 50GB, SLA, multi-region snapshot replication | ~$35 |

Solo tier covers a friend-and-family launch. Plus/Pro are speculative until we have a real high-end use case.

### Tenant isolation properties

**Strong by construction.** Each operator is a separate Fly app with separate volume. No shared DB rows, no shared filesystem, no shared process. An OOM in operator A's vault can't touch operator B. A SQL injection in one operator's app can't read another's data.

The cloud-offering sketch's RLS-in-Postgres design solves this through schema-level isolation; the Fly-app-per-operator design solves it through infrastructure-level isolation. Both work; the Fly shape is much simpler to reason about and much harder to get wrong.

Trade-off: per-operator overhead is ~10x more compute than a shared backend would be. For ~1000 operators that's ~$3500/mo cost basis vs maybe $300 on a shared Postgres setup. The breakeven for "switch to shared" is somewhere around 5000-10000 operators. We're nowhere near that. Defer the shared-backend rewrite until the bill demands it.

### Backup/restore for hosted

Fly's native daily snapshots cover the "we have a backup if disk fails" case. For "operator wants their data" or "operator wants to migrate to self-host":

1. **One-click export from admin UI** — calls our backup service, which:
   - SSH-execs `sqlite3 /parachute/hub.db ".backup /tmp/backup.db"` (transactionally consistent vs raw volume snapshot)
   - Tars `/parachute/` into `/tmp/backup.tar.gz`
   - Uploads to S3/R2 with a 7-day signed download URL
   - Emails the operator the link
2. **Migration to self-host** — operator runs `fly volumes restore --from-url=<signed-url>` against their own Fly org. Same image, same data, same URL shape (their `acme.fly.dev` instead of `acme.parachute.cloud`).
3. **Migration to other infra** — they get the `.tar.gz`; we don't lock them in.

This is the lock-in symmetry payoff. **The export-to-self-host primitive exists on day one of the paid offering**, not as a future migration project.

## Phased timeline

### Phase 0 — now (no migration)

- Aaron's `parachute-hub.onrender.com` keeps running.
- Render `parachute-hub-renderyaml-bound` deploys (operators who already forked) keep working.
- No code changes; no migration tax.

### Phase 1 — Fly track for self-hosters (~2 weeks)

- [ ] Add `fly.toml` alongside `render.yaml` (don't remove either)
- [ ] Code changes in hub for `FLY_APP_NAME` origin detection + auto-skip-expose
- [ ] `scripts/deploy-to-fly.sh` for the friendly first-time path
- [ ] README updated: "Deploy to Fly" as the primary self-host path, Render as alternative
- [ ] Smoke test: fork → `./scripts/deploy-to-fly.sh` → working hub in <5min
- [ ] Aaron migrates his own hub to Fly (real-world dogfood)
- [ ] Site `/deploy` page updated to show both, Fly first

**Exit criteria**: a friend can fork + run `./scripts/deploy-to-fly.sh` + install vault from the admin SPA, in under 5 minutes, with the same UX they'd have gotten on Render.

### Phase 2 — provisioning service (~3 weeks after Phase 1)

- [ ] `parachute-cloud-provisioner` — small Fly app, exposes `/provision`, `/status`, `/teardown` endpoints
- [ ] Stripe Checkout integration (test mode first)
- [ ] DNS automation via Cloudflare API
- [ ] First test operator: Aaron provisions himself via parachute.cloud signup flow
- [ ] First real operator: a friend who's been waiting for hosted
- [ ] Admin dashboard (separate Fly app, internal-only): list operators, their app health, their billing status

**Exit criteria**: a Stripe payment kicks off provisioning that ends with the operator getting an email containing a working `https://<slug>.parachute.cloud/admin/setup` URL, end-to-end automated.

### Phase 3 — public launch (~4 weeks after Phase 2)

- [ ] Pricing page on parachute.computer
- [ ] Public signup at parachute.cloud
- [ ] Onboarding emails + support inbox
- [ ] Update orchestration: GitHub Action that rolls new hub versions across all operator apps with canary
- [ ] Backup/restore one-click export flow in admin UI

**Exit criteria**: a stranger lands on parachute.computer, clicks "Start a Parachute," pays, and is using their hub within 2 minutes. 10+ operators on the platform.

### Phase 4 — Render sunset (optional, ~3 months later)

If by this point Fly has been meaningfully better operationally and no major Render-only constituency emerged: remove `render.yaml`, deprecate the Render docs, move on. If Render still has operators we want to support: keep both, mark Fly as "recommended."

## Risks and unknowns

### Operational

- **Fly outages.** `iad` has had bad weeks. Mitigation for self-host: operator picks a different region at launch. Mitigation for hosted: support multi-region eventually (volumes are zone-pinned; needs replication strategy). Pre-launch, document that single-region is the current shape.
- **Volume snapshot consistency.** Raw volume snapshots aren't transactionally consistent against SQLite. Mitigation: backup service runs `sqlite3 .backup` before tarring; never relies on raw volume snapshots for restore-into-other-infra. (Fly's daily snapshots are fine for "hardware failed, restore the volume" — they're a different recovery path.)
- **Fly Machines API stability.** It's newer than their older Apps v1 API. Has had breaking changes. Mitigation: pin the SDK version we use in the provisioner; subscribe to their changelog.
- **Cold starts on `auto_stop_machines`.** Tempting for cost savings on self-host ($0 when idle). Cold start adds 200-2000ms. Recommendation: always-on for hosted, opt-in `auto_stop` for self-hosters who don't mind the latency.

### Strategic

- **Substrate diversification.** Putting both self-host and hosted on Fly is a single point of failure on Fly's side. If they pivot pricing or shutter, we move both at once. Mitigation: the snapshot-portability primitive means we *can* move (to Hetzner, Railway, DO App Platform, even back to Render). The fly.toml-to-other shouldn't be impossible because the image is the same.
- **Operational complexity creep.** A provisioning service + DNS automation + Stripe + admin dashboard is more code than current Render deploy. Real possibility we under-estimate the maintenance load. Mitigation: keep each piece small; resist the urge to build a "platform." We're running ~tens of apps initially, not thousands.
- **Compete-with-Render perception.** Render is in our docs; switching primary recommendation to Fly might read as "Render is bad." It's not — they're fine, Fly is just better-suited for our specific shape. Mitigation: docs honestly say "both work, here's why we recommend Fly for our use case."

### Open questions for Aaron

1. **Custom domains in the cloud tier** — Solo tier gets `<slug>.parachute.cloud`. Do operators on Plus get their own `notes.<their-domain>`? (Fly supports it; adds DNS + TLS provisioning steps per operator. Recommend: defer to Pro tier or charge extra.)
2. **Region selection at signup** — auto-pick based on IP, or let operator choose? (Recommend: auto-pick with override. Most operators don't care; some have data-residency requirements.)
3. **What happens when a hosted operator stops paying?** — Grace period? Read-only? Data export window before deletion? (Recommend: 14-day grace, then read-only for 30 days, then volume snapshot kept for 90 days for restore-on-request, then deleted. Communicate clearly at signup.)
4. **The reliability story for hosted** — if Fly `iad` has an outage, every operator hosted there is down. Acceptable for a $10/mo tier; not acceptable for a $50/mo tier with SLA. (Recommend: SLA only on Pro tier with multi-region replication, which is a Phase 4+ feature.)
5. **Aaron-as-team-of-one bandwidth** — Phase 2 + 3 is real engineering work (provisioning service, billing, admin dashboard, onboarding flow). Order of magnitude: 4-6 weeks of focused effort vs. continuing to polish hub. Is that the right priority vs other things on the docket?

## What this displaces

The cloud-offering sketch (2026-04-20) imagined subdomain-per-tenant, Postgres-backed, vault rewrite to async Store with RLS. That work is *large* — vault Store refactor is multi-week, Postgres migration is fraught (especially the SQLite-WAL → Postgres-MVCC semantic gap), and RLS configuration is the kind of thing that takes one mistake to leak data across tenants.

App-per-operator on Fly **delays all of that indefinitely**. Vault stays SQLite. No RLS to write. No async Store. Operators are isolated by infrastructure, not by application logic. We keep the option to migrate to a shared backend if/when scale demands it.

The trade-off is cost basis (~$3.50/operator vs maybe $0.30/operator on a shared backend at scale). But:
- At $3.50 vs $10-25 sticker, the margin is fine
- We're far from the scale where the difference matters
- Engineering time saved on Phase 1-3 is high-value vs the spec-uncertain cloud-offering-sketch work

**Recommendation: pursue app-per-operator on Fly. Reconsider shared-backend at 5000+ paying operators.**

## Decision Aaron needs to make

Three options, in order of commitment:

**A. Spike Phase 1 only** (~2 weeks). Add Fly track, prove it works for self-hosters, decide later whether to do hosted on Fly or via the cloud-offering-sketch shape. Minimal commitment, keeps options open.

**B. Commit to Phase 1 + 2** (~5 weeks). Self-host on Fly + provisioning service. First friend-and-family hosted operator. No public launch yet.

**C. Commit to full path** (~10 weeks). Public launch of parachute.cloud as the hosted tier alongside polished self-host.

My take: **A**, with a clear decision point at the end of Phase 1 about whether to continue. The Phase 1 work is fully reversible (we can keep Render) and gives concrete data about Fly's reliability + operator experience before committing to the larger build. If Phase 1 confirms the bet, Phase 2/3 follow as separate decisions.
