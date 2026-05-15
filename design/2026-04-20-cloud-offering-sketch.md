---
title: "Parachute Cloud — architecture sketch"
description: "Cloud deployment shape: tenant-per-subdomain, Postgres-backed, CDN-hosted Notes, pooled Scribe. A plausible north star we refine when a first cloud user materializes."
---
# Parachute Cloud — architecture sketch

**Date:** 2026-04-20
**Status:** Sketch. Aaron asked for a shape that aligns cloud with the module architecture. This is that shape — a plausible north star we refine when a first cloud user materializes.

**Companions:**
- `DESIGN-2026-04-20-module-architecture.md` — the shared ecosystem foundation
- `DESIGN-2026-04-20-hub-as-portal-oauth-and-service-catalog.md` — OAuth

## The core claim

**Cloud is a deployment target of the same ecosystem, not a separate product.** The module contracts are identical. A Notes client configured against `https://me.parachute.computer/` works the same as against `https://parachute.<tailnet>.ts.net/`. What changes is infrastructure — identity, storage, scale — not the API surface clients see.

This decision preserves Parachute's open-source story: self-hosting remains equivalent, cloud is just an operational upgrade path.

## The two axes of change

Self-hosted → Cloud differs on two axes:

1. **Scale**: one user one machine → many users, many tenants, one cluster.
2. **Operations**: user runs services → Parachute team runs services.

Everything else is invariant.

## Tenant shape

A **tenant** is one user (or team) with their own data. Each tenant gets:

- A canonical origin: `https://<subdomain>.parachute.computer` (preferred) or `https://app.parachute.computer/u/<user>/` (path-based fallback).
- Their own vault namespace.
- Their own notes UI at `<origin>/notes/`.
- Their own scribe quota / instance (shared pool, scoped by tenant).
- One OAuth identity at `<origin>/oauth/*`.

Subdomain per tenant is the cleaner shape (solves same-origin issues, matches single-user self-hosted URL shape). Path-based is a fallback when DNS automation can't be had.

## Module mapping

### Vault (cloud)

- **Storage**: SQLite per tenant → **Postgres with RLS** (row-level security scoped by tenant_id). Or Postgres-per-tenant for strong isolation at the cost of scaling complexity.
- **Interface**: HTTP + MCP unchanged. Clients can't tell local vs cloud.
- **Migration path**: vault's existing Store interface abstracts over SQLite today. Refactor to async Store (already on vault's roadmap per README). Cloud implementation of Store backs it with Postgres.
- **Attachments**: SQLite BLOBs or filesystem today → **object storage** (S3/R2/Cloudflare R2). Attachment API unchanged; clients upload via the same endpoint; implementation writes to object store.

### Notes (cloud)

- **Serving**: static `dist/` served from CDN (Cloudflare Pages, Netlify, etc). Zero stateful per-tenant cost.
- **Per-tenant customization**: Notes is stateless client; tenant-specific state lives in vault. Same static bundle serves everyone.
- **Tenant-scoped base path**: Notes is served at `<origin>/notes/` per tenant origin. Vite base stays `/notes/`, SW scope stays `/notes/`. No change.

### Scribe (cloud)

- **Compute**: transcription is bursty + CPU/GPU-heavy. Cloud hosts a pool of scribe workers; tenant requests land via a queue.
- **Providers**: cloud can expose higher-quality models (paid Whisper API, Deepgram, Gemini native audio) alongside `parakeet-mlx`. Provider selection is per-tenant config.
- **Quota / billing**: scribe usage is metered by audio-minute-seconds. Tenant tier dictates monthly ceiling and provider tier.

### Channel (cloud)

- Tricky because Telegram (or any messaging backend) requires a bot token per tenant or a shared tenant-routing proxy. **Parked** until a tenant asks.

### Hub (cloud)

- Hub is the tenant's front door at `<origin>/`.
- Same hub HTML as self-hosted, hosted from CDN.
- Configuration UI writes go through Parachute's cloud control plane (not the tenant's local filesystem).

## Identity

**Cloud uses centralized identity at `auth.parachute.computer`** — a dedicated auth service.

- User signs up once with email + password (or SSO: Google/Apple/GitHub).
- Auth service issues OAuth tokens with tenant-scoped claims.
- Each tenant's hub-origin OAuth discovery delegates to `auth.parachute.computer`.
- Post-launch refactor path: self-hosted users can optionally federate with `auth.parachute.computer` for a "cloud-lite" experience (data stays local, identity is Parachute-managed).

This mirrors the self-hosted architecture where vault *is* the IDP for its tenant (Phase 0+1). Cloud just factors the IDP out sooner because multi-tenant demands it.

## Scopes in cloud

Scopes gain tenant-awareness:
- `vault:read` → granted against the current tenant's vault only; no cross-tenant leakage possible.
- Cross-tenant access requires a separate OAuth flow into another tenant's origin (with consent).
- Admin operations on tenant billing / settings use `hub:admin` scoped to the tenant's origin.

## Data residency & portability

- **All cloud tenants can export their vault** as a zip of SQLite + attachments + vault.yaml. Drops them onto a self-hosted install with no data loss.
- **Import from self-hosted** works symmetrically: upload the export, cloud creates a new tenant from it.
- **No vendor lock.** This is Parachute's core promise.

## Billing tiers (sketch)

- **Free**: 1 GB storage, 10 min/month transcription (bring-your-own provider fallback), community support.
- **Personal** ($8/mo): 10 GB, 500 min transcription with our providers, email support.
- **Pro** ($20/mo): 100 GB, 2000 min transcription, priority support, advanced AI integrations.
- **Team** (custom): multi-user vault sharing, shared tags/links, admin controls.

Self-hosting is free forever, no tier. Cloud billing is metered against storage + transcription compute primarily.

## Deployment shape

Target stack (initial, iterate):

- **Cloudflare Workers + R2 + D1** — for vault's HTTP + attachment storage. Async Store interface lands on D1 (SQLite-compatible at the SQL level) or Postgres via Neon. R2 for attachments.
- **Cloudflare Pages** — for Notes (static).
- **Fly.io / Railway** — for scribe pool (long-running workers, CPU/GPU). Alternatively rent GPU per inference via Replicate / RunPod.
- **DNS + TLS**: Cloudflare (automates `<subdomain>.parachute.computer` per-tenant via API).

Why Cloudflare-heavy: cheap at small scale, global edge, DNS automation, object storage and D1 integrate.

Alternative: full Postgres + self-managed K8s if we outgrow Workers. Probably Year 2 problem.

## Per-tenant provisioning flow

When a user signs up:
1. Choose subdomain: `aaron.parachute.computer`.
2. Cloudflare API creates the DNS record + TLS cert.
3. Worker spawns a new vault namespace (or row in shared DB with tenant_id).
4. `/.well-known/parachute.json` for the new origin lists vault + notes + optionally scribe.
5. `auth.parachute.computer` issues an initial token for the tenant's owner.
6. User lands on `aaron.parachute.computer/` — hub renders, shows vault + notes cards.
7. User clicks Notes → OAuth flow → lands in their fresh empty vault.

Elapsed time target: under 60s from signup to first note.

## Abuse / rate-limiting

- **Per-tenant quotas** on API requests (X req/min), transcription minutes, storage.
- **Global DDoS protection** via Cloudflare.
- **Anomaly detection** on sudden spikes in storage or transcription (catches compromised API keys).

## Open questions

1. **Team / shared vaults**: when does multi-user-single-vault enter the picture? Probably Year 2 after Personal tier is validated. Requires sharing primitives in vault that don't exist yet.
2. **Offline sync for cloud PWA**: Notes already has IndexedDB sync; cloud version keeps that, just syncs to remote vault instead of local. No change.
3. **MCP access in cloud**: Claude / GPT connectors call `aaron.parachute.computer/vault/default/mcp` — cloud just routes this to the tenant's vault like any other API call. No MCP-specific cloud work needed.
4. **Per-tenant secrets** (like SCRIBE_TOKEN if a user BYOs): stored encrypted per-tenant in the control plane. Accessible only to that tenant's services.
5. **Tenant deletion + retention**: 30-day soft delete, then hard. Standard SaaS practice.
6. **Beta → GA transition**: cloud launches as paid beta (small count, curated); free tier opens after stability proven. Avoids "free tier abuse day one" problem.

## Beta path

To go from "launch of self-hosted on 2026-04-23" to "first paying cloud user":

1. **Week 1–2 post-launch**: stabilize self-hosted. Observe real usage patterns.
2. **Week 3–4**: factor vault's Store interface to async. Write Postgres (Neon) backend.
3. **Week 5–6**: stand up `auth.parachute.computer` — initially just proxy to a single cloud vault's OAuth impl, same as the self-hosted Phase 0 seam. Iterate to real multi-tenant IDP.
4. **Week 7–8**: provision flow for subdomains. Small closed beta (5–10 invited users, hand-provisioned).
5. **Week 9–12**: self-serve signup. Paid tier.
6. **Month 4+**: scale based on real demand.

## Why the module architecture matters for cloud

Because each module declares its own contracts, cloud operations can:
- **Scale modules independently**: scribe pools separately from vault Postgres.
- **Swap implementations**: replace SQLite Store with Postgres Store; module's public contract unchanged.
- **Add cloud-specific modules**: a `billing` module, a `teams` module — they just implement the contracts and plug in.
- **Let tenants self-configure**: tenant adjusts their vault's `audio_retention` setting via the hub; hub PUTs to vault's `/.parachute/config`; no special cloud admin path.

The cloud is the self-hosted architecture, run by us, at scale, with centralized identity. Same shape all the way down.

## TL;DR

- **Cloud is the self-hosted ecosystem, deployed and operated by us.**
- **Each tenant gets a subdomain** with the full self-hosted URL shape.
- **Vault gets Postgres + object storage**. Same Store interface.
- **Notes is static** on CDN.
- **Scribe is a shared pool**, metered.
- **Identity centralizes** at `auth.parachute.computer`; self-hosted can optionally federate.
- **Scopes become tenant-aware** naturally via origin scoping.
- **Export / import is lossless** both directions; no lock-in.
- **Beta path is sequential** and short — target first paying user within 3 months of launch.
