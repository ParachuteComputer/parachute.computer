---
title: "Hub as portal — OAuth and the service catalog"
description: "OAuth architecture with the hub as issuer — still canonical. One ecosystem sign-in, tokens carrying a service catalog, scoped access. (The config-portal half of this doc was retired 2026-06-09.)"
---
# Hub as portal, OAuth, and the service catalog

> **Partially superseded (2026-06-09) — two halves, different fates**
>
> This document merged two architectural threads. They have diverged since:
>
> - **OAuth-issuer half (hub-as-issuer):** remains canonical and load-bearing. Hub is the ecosystem OAuth issuer; modules accept hub-issued JWTs; the hub JWKS + `/oauth/*` surface is the live, enforced contract. Nothing here has changed.
>
> - **Config-portal half (hub renders config dashboards / privileged writes via `PUT /.parachute/config`):** this is the "thick hub" pattern that seeded the architectural debt the 2026-06-09 shift retired. Hub driving `PUT /.parachute/config` forms is no longer the target shape. Module-owned admin surfaces (e.g. `/vault/admin/`) now own their config UX; hub owns the provisioning transaction, not the form rendering. See the boundary charter and the modular-UI design doc for the current model.
>
> **Current ownership rules:** [`parachute-patterns/patterns/hub-module-boundary.md`](https://github.com/ParachuteComputer/parachute-patterns/blob/main/patterns/hub-module-boundary.md)
> **Modular-UI shift:** [`parachute-patterns/design/2026-06-09-modular-ui-architecture.md`](https://github.com/ParachuteComputer/parachute-patterns/blob/main/design/2026-06-09-modular-ui-architecture.md)

**Date:** 2026-04-20 (launch week — launch target 2026-04-23)
**Context:** Aaron is out walking, has two related architectural thoughts that converge.

## The two threads that converged

### Thread 1: Hub click-through is dead for API-only services

Aaron clicks the Vault card on the hub and lands on a raw API response. Not useful for humans. Notes has a real UI; Vault doesn't. He wants the hub to do more — become a configuration surface for the whole ecosystem so users don't have to use the CLI for every setting.

### Thread 2: OAuth architecture — where should it live?

Originally proposed: vault as ecosystem identity provider (vault already has OAuth 2.1 + PKCE + DCR — just reuse it). Aaron pushed back: that conflates data service with identity. The hub is the front door; identity belongs at the front door. His proposal: hub-as-OAuth-issuer, vault and other services accept hub-issued tokens.

Aaron is right. Vault-as-IDP was expedient, not clean. Extracting identity from the data layer is the architecturally correct move. Services shouldn't inherit auth from a sibling; they should inherit from a shared source above them.

## Core design

**Hub is the ecosystem front door.** It owns three things:
1. The landing page and service directory (exists today)
2. The OAuth issuer surface (`/.well-known/oauth-authorization-server`, `/oauth/authorize`, `/oauth/token`, `/oauth/register`)
3. The configuration portal (future — phase 2+)

**Vault, Notes, Scribe, and future services are OAuth clients of the hub.** Services accept hub-issued tokens, validate scopes.

**Scopes per service**: `vault:read`, `vault:write`, `scribe:transcribe`, `hub:admin`, `channel:send`. Clients declare what they need at authorization; hub consent UI shows "Notes wants: read your vault, write notes, transcribe audio."

**Token response carries the service catalog** (ecosystem extension):
```json
{
  "access_token": "...",
  "scopes": ["vault:read", "vault:write"],
  "services": {
    "vault": { "url": "https://parachute.x.ts.net/vault/default", "version": "0.3.0" },
    "scribe": { "url": "https://parachute.x.ts.net/scribe", "version": "0.2.0" }
  }
}
```

Notes never asks the user for a vault URL. It does OAuth against the hub, gets a token + the service catalog, auto-populates everything.

**Step-up permissions**: Notes initially requests `vault:read`. User tries voice memo. Notes requests `scribe:transcribe + vault:write` via refresh; hub re-prompts consent for new scopes. No full re-login.

## Phasing

### Phase 0 — launch seam (pre-2026-04-23)
Small PR, low risk:
- Hub serves `/.well-known/oauth-authorization-server` with `issuer = hub origin`, endpoints advertised at `/oauth/*` paths on the hub.
- Hub proxies `/oauth/authorize`, `/oauth/token`, `/oauth/register` to vault's current implementation.
- Clients (Notes, MCP AI connectors) OAuth against the hub URL from day one. Vault's OAuth becomes an internal implementation detail; public contract lives at the hub.
- Vault adjusts its `issuer` metadata to match the hub origin (don't advertise itself as issuer anymore).

**Net effect**: clients from launch day onward never know vault is the auth implementation. When we later extract or rewrite auth, zero client changes.

### Phase 1 — catalog in token response (post-launch, 1–2 weeks)
- Extend token response with the `services` catalog (drawn from `/.well-known/parachute.json`).
- Notes drops its "enter vault URL" prompt — auto-populates from the token response.
- Consent UI rehosted/reskinned in the hub (instead of vault's current OAuth pages).

### Phase 2 — real scope enforcement (post-launch, 2–6 weeks)
- Scope enforcement in vault (`vault:read` vs `vault:write`), scribe (`scribe:transcribe`), etc.
- Step-up permission flow in the hub.
- Consent UI lives fully in the hub. Vault's auth becomes a pure backend with no UI.

### Phase 3 — full extraction (post-launch, open-ended)
- Auth factored out of vault into a dedicated `parachute-auth` service, or stays in vault as an internal module. Public shape is unchanged.
- Decision deferred until Phase 1 + 2 reveal the real constraints.

## Hub as config portal (Thread 1 resolution)

Orthogonal to OAuth but benefits from it:

- **Pre-launch (minimum)**: hub cards for API-only services (vault, scribe) show a detail panel in place instead of navigating. Panel shows: MCP endpoint, OAuth discovery link, "Open in Notes" deep-link, version. No writes. No OAuth needed (hub runs on loopback for local installs).

- **Post-launch Phase 1**: each service exposes `GET /.parachute/config` (read-only, returns current settings as JSON schema). Hub renders a read-only config dashboard. Still no writes; no OAuth needed.

- **Post-launch Phase 2+**: `PUT /.parachute/config` on each service. Now the hub is doing privileged writes — OAuth from Phase 0/1 gates this. User logs in via hub OAuth, hub's token carries `hub:admin` scope, services accept.

## Why this shape is right

1. **Separation of concerns**: identity is cross-cutting, data services are data services. Don't conflate.
2. **Front door UX**: "Log into Parachute" (via hub) is more natural than "log into your vault." Users see one door.
3. **Single sign-on, automatically**: one OAuth flow against the hub grants access to every installed service. No per-service login.
4. **Auto-discovery**: services learn about each other through the token response. Notes stops asking for vault URLs. New services plug in without clients being reconfigured.
5. **Scope-based permissions**: users can grant fine-grained access per client app. Notes gets read; some future AI agent gets read-only; an admin tool gets full.
6. **Clean extraction path**: auth implementation can move (vault → hub → dedicated service) without ever breaking a client, because the client only sees the hub as the issuer.

## Open questions

- **Where does password + 2FA actually live?** Probably still inside vault for Phase 0 (existing implementation). Phase 1 proxies UI through hub. Phase 3 extracts. Password hashing stays identity-service-side.
- **How do AI connectors (Claude MCP) get tokens?** They register as OAuth clients of the hub via DCR, same as Notes. User consents via hub consent UI. AI gets hub-issued token scoped to `vault:read` + `vault:write`. AI calls vault's MCP endpoint with token. Vault introspects against hub or validates JWT signature.
- **What about scribe having its own auth eventually?** Scribe is internal-only today (CORS `*`, no auth). Once it's hub-OAuth-gated, the CORS becomes less permissive and scribe validates hub tokens. Scope: `scribe:transcribe`.
- **Multi-vault**: vault supports N vaults; scopes might need to be `vault:<name>:read` or similar. Decide with Phase 2.
- **Running without the hub**: what if someone runs vault standalone, no hub? Either vault retains its own OAuth as a fallback, or we declare hub required. Probably the former — vault can advertise itself as issuer when standalone, advertise hub when hub is installed.

## Decisions made

- **Hub will be the ecosystem OAuth issuer.** Vault's implementation continues to power it behind the scenes until extraction.
- **Launch ships Phase 0 seam** — public URL is hub, implementation is vault, zero behavior change for humans but clean contract for future.
- **Token response will include the service catalog** (Phase 1 priority — enables zero-config clients).
- **Config portal evolves from click-through-detail (pre-launch) → read-only dashboards (Phase 1) → write surfaces (Phase 2, gated by hub OAuth).**

## Why this note exists

We're 3 days from launch. This is a significant architectural direction that we can't fully build pre-launch but whose public shape matters from day one. The launch Phase 0 seam is the commitment that keeps the post-launch door open without painting us into a corner.

Revisit this note when starting Phase 1 work — likely within 2 weeks of launch.
