---
title: "v0.6 deploy architecture — single Render container, hub-as-supervisor"
description: "v0.6 self-host on Render runs one container; hub supervises vault/notes/scribe as child processes; modules install at runtime via the admin SPA and persist on a single mounted disk. The deploy mirror of the local model."
---
# v0.6 deploy architecture — single Render container, hub-as-supervisor

**Date:** 2026-05-18
**Status:** Locked in. Supersedes the multi-container exploration in [`2026-04-20-cloud-offering-sketch.md`](./2026-04-20-cloud-offering-sketch.md) for the **self-host** path; that sketch remains the north star for a future Parachute-operated hosted offering.

**Companions:**
- [`2026-04-20-module-architecture.md`](./2026-04-20-module-architecture.md) — module protocol (info / config / services.json / well-known)
- [`2026-04-20-hub-as-portal-oauth-and-service-catalog.md`](./2026-04-20-hub-as-portal-oauth-and-service-catalog.md) — OAuth architecture with hub-as-issuer
- [`2026-04-20-cloud-offering-sketch.md`](./2026-04-20-cloud-offering-sketch.md) — multi-tenant cloud sketch (long-horizon, separate axis from v0.6 self-host)

## The decision

v0.6 ships **one Render container** running hub-as-supervisor. Vault, Notes, Scribe (and any other modules) run as child processes spawned by hub, sharing one persistent disk mounted at `/parachute/`. Modules install at runtime via the admin SPA — not baked into the container image.

This is **the deploy mirror of the local model**: locally, `parachute serve` runs hub, hub spawns vault/notes/scribe as children, all share `~/.parachute/`. Cloud is the same process group, in a container.

## Why we got here

Earlier exploration (mid-May) sketched a multi-service `render.yaml` — separate Render services for hub, vault, notes, scribe, each with its own disk. Cleaner failure isolation, separate per-service logs, independent scaling.

The cost picture broke it. Render bills $7/month per service on the Starter plan. A four-module deploy is $28/month before any traffic. A six-module deploy is $42. **Modular pricing was an explicit goal — the user should pay roughly the same whether they run two modules or six.** Multi-service pricing inverts that.

Aaron's framing 2026-05-18: *"If we're paying $7 for each one that is not an acceptable orientation."*

Single-container fixes the cost shape and keeps modularity at the level it matters — code, versions, dependencies, repos. Runtime process-group co-location is an implementation detail of the deploy target, not an architectural commitment.

## What "single container" actually means

**Image layer (baked into the container):**
- Bun runtime
- `@openparachute/hub` (the supervisor + admin SPA + OAuth issuer)
- Nothing else

**Runtime layer (installed onto the persistent disk):**
- Modules the user picks via the admin SPA: `@openparachute/vault`, `@openparachute/notes`, `@openparachute/scribe`, third-party modules later.
- Module install uses `BUN_INSTALL=/parachute/modules` so packages persist on the mounted disk rather than the ephemeral image filesystem.
- Hub maintains a `services.json` recording which modules are installed + spawn-config per module.

**On container start:**
1. Hub boots, reads `/parachute/services.json`.
2. For each registered module: `bun run /parachute/modules/node_modules/<pkg>/bin/<svc>` (or the module's declared entry point).
3. Hub mounts each module's HTTP routes under its assigned path-prefix (`/vault`, `/notes`, `/scribe`).
4. Hub's `/admin/*` SPA renders against the live module list.

**On admin "install module":**
1. SPA calls the hub module-install API.
2. Hub runs `bun install <pkg>` with `BUN_INSTALL=/parachute/modules`.
3. Hub records the install in `services.json`.
4. Hub supervises the new module — spawns it, adds it to the route table.
5. SPA refreshes to show the new module.

**On container restart** (Render redeploy, scale event, OOM, etc.):
- Hub reads `services.json` from disk → re-spawns each registered module from `/parachute/modules/node_modules/`.
- No re-install, no friend-rerunning-the-wizard.

## The trade-off

Shared process group means one module's OOM, hang, or panic can affect siblings.

**Mitigations:**
- Hub supervises with restart-on-crash per module (already implemented locally).
- Render Starter has 512MB. Hub + vault + notes + scribe at v0.6 scale fit comfortably — vault is the biggest at idle (SQLite in-process), still well under 200MB across typical workloads.
- If a real user hits the limit, we can split that one module into its own container later — without redesigning anything else. The module's HTTP interface is identical whether it's a co-located child process or a separate service hub forwards to.

The trade-off is explicit and acknowledged: **simpler operation now, headroom later**. Splitting a single service out of the co-located group is a smaller change than building a multi-service deploy template from day one.

## Why not just bake all the modules into the image?

Two reasons:

1. **Modular install is a feature, not a chore.** v0.6's value proposition includes "install the modules you want." A friend who doesn't need transcription shouldn't get scribe running just because we baked it in. The admin SPA gives them a real choice.
2. **Image churn vs disk durability.** Modules update on different cadences than hub. Baking them in means re-deploying the entire container every time vault publishes a patch. Persisting modules on disk lets users `upgrade-on-unsupervised` (or wait for hub's `parachute upgrade <module>` SPA path) without a redeploy cycle.

## v0.6 release bar

**No partial ship.** v0.6 ships only when the **friend-experience-loop** is complete end-to-end:

1. Friend forks the deploy repo (or clicks Deploy-to-Render from `parachute.computer/deploy`).
2. Render provisions one container with a persistent disk.
3. Friend opens the deployed URL → first-boot wizard at `/admin/setup`.
4. Wizard collects admin credentials + initial config.
5. Wizard step 3 prompts: which modules? Friend picks vault + notes + scribe.
6. Hub installs all three at runtime (`BUN_INSTALL=/parachute/modules`), supervises them.
7. Friend is taken to the admin dashboard showing all three running.
8. Friend opens `/notes`, writes a note, transcribes audio — all working.

**Target time-to-working: under 5 minutes from "click Deploy" to "wrote a working note."**

## Issues + phasing

Phase 1 (critical-path to v0.6 ship):

- **hub#258** — Dockerfile + render.yaml + env-driven boot for Render self-host. [✓ landed as 0.5.10-rc.1]
- **hub#262** — admin module mgmt API + supervisor + container-mode runtime install. [in flight, rc.4]
- **hub#259** — first-boot web wizard at `/admin/setup`. Vault install in step 3 calls the hub#260 module-install API.
- **hub#260** — admin SPA module management surface (install / upgrade / configure via UI). **Promoted Phase 2 → Phase 1** because without it, deployed hub is stuck empty — friend can't install anything.
- **parachute.computer#42** — `/deploy` page with one Deploy-to-Render button, hub-only target. Modules installed post-deploy via admin SPA.

Phase 2 (post-v0.6 polish, not gating ship):

- **hub#263 / #264 / #265** — supervisor await-on-exited, SIGKILL fallback, upgrade-on-unsupervised test gap (from #262 reviewer follow-ups).
- Per-module log multiplexing in the admin SPA (live tail).
- VPS / Docker Compose path for friends wanting non-Render self-host.

Phase 3 (later):

- Multi-tenant hosted offering operated by Parachute — see [`2026-04-20-cloud-offering-sketch.md`](./2026-04-20-cloud-offering-sketch.md). Depends on multi-user UX (hub#252) and is a separate substantive build.

## What this changes about earlier docs

- **`2026-04-20-cloud-offering-sketch.md`** describes a multi-tenant Parachute-operated cloud (tenant-per-subdomain, Postgres-backed, CDN-hosted Notes). That north star is unchanged for the long horizon. v0.6 is the **self-host** path — a friend running Parachute on their own Render account. Cloud-self-host and Parachute-operated-cloud are two orientations of the same ecosystem (see memory: `project_parachute_ecosystem_shape.md`); this doc covers only the first.
- **Multi-service `render.yaml` exploration (vault#339, mid-May)** is set aside as the primary path. The vault Dockerfile remains useful (CI builds, future hub-spawns-vault-as-image flows). The standalone vault `render.yaml` is deprecated as a v0.6 deploy target — tracked at vault#341.

## Why the architecture is right

The criterion that locked option A in: **the local-host model and the cloud-self-host model are operationally identical.** Hub supervises modules, modules share one persistent directory, admin SPA installs and configures. The friend deploying to Render isn't learning a new architecture — they're getting the same thing that already runs on Aaron's laptop, in a container, with a public URL.

That equivalence makes the deploy path easy to reason about, easy to document, and easy to support. It also means future hardening (better supervisor, richer admin SPA, log multiplexing) lands once and helps both deploy targets.
