---
title: "Module architecture"
description: "Historical origin of the module protocol: info, config, services.json, .well-known/parachute.json. The hub-rendered-config-form model and kind taxonomy are retired; current ownership rules live in the hub-module boundary charter."
---
# Parachute module architecture

> **Historical foundation — superseded in part (2026-06-09)**
>
> This document is the historical origin of the Parachute module protocol. Two of its core models have since been retired:
>
> - **Hub-rendered config forms** (`GET /.parachute/config/schema` → hub renders a config UI, `PUT /.parachute/config` driven by hub) — this "thick hub" pattern is retired. Module-owned admin surfaces (e.g. `/vault/admin/`) now own their own config UX; the hub owns the identity transactions, not the form rendering.
> - **`kind` taxonomy** (`"api" | "frontend" | "tool"` in `/.parachute/info`) — retired; no current enforcement or rendering depends on it.
>
> **Current ownership rules:** [`parachute-patterns/patterns/hub-module-boundary.md`](https://github.com/ParachuteComputer/parachute-patterns/blob/main/patterns/hub-module-boundary.md) is the boundary charter — what hub owns vs what modules own.
> **Modular-UI shift:** [`parachute-patterns/design/2026-06-09-modular-ui-architecture.md`](https://github.com/ParachuteComputer/parachute-patterns/blob/main/design/2026-06-09-modular-ui-architecture.md) documents the architectural shift that retired the hub-rendered-config-form model.
>
> The module-protocol fundamentals below (`.parachute/info`, `services.json`, `module.json`, scope format, extensibility) remain accurate. The config-form contracts (§4–6 of Module contracts) and the hub-as-configuration-UI framing (§The hub as orchestrator) describe the retired model.

**Date:** 2026-04-20
**Status:** Historical foundation — see the boundary charter for current ownership rules. Launch ships with a subset; this doc defined the original target.

**Companions:**
- `DESIGN-2026-04-20-hub-as-portal-oauth-and-service-catalog.md` — OAuth architecture
- `DESIGN-2026-04-20-cloud-offering-sketch.md` — cloud deployment

## The frame

Everything in Parachute is a **module**. A module is a small, self-contained service that plugs into the Parachute Computer ecosystem by implementing a set of well-known contracts. The **hub** is the orchestrator — it discovers modules, routes to them, authenticates users against them, and surfaces their configuration.

This frame is important because it defines **how the ecosystem scales**: new services (Pendant, Daily-v2, anything a third party builds) can join by implementing the contracts. No hub-side code changes. No special-casing.

## What's a module

Conceptually, a module is anything you can:
- Install: `parachute install <name>`
- Start: `parachute start <name>`
- Configure: via the hub UI (reads/writes the module's config)
- Discover: `parachute status`, hub card, `/.well-known/parachute.json`
- Authorize: OAuth scopes grant clients access to the module

Today's modules: `vault`, `notes`, `scribe`, `channel`, plus `hub` itself.

## Module contracts

Every module MUST implement:

### 1. `GET /.parachute/info` — identity + metadata

```json
{
  "name": "parachute-vault",
  "displayName": "Vault",
  "tagline": "Agent-native knowledge graph — notes, tags, links, attachments over REST + MCP",
  "version": "0.3.0",
  "kind": "api" | "frontend" | "tool",
  "iconUrl": "/vault/default/.parachute/icon.svg",
  "capabilities": ["store-notes", "tag", "link", "search", "graph", "mcp"]
}
```

No auth. CORS `*`. 405 on non-GET.

### 2. `GET /.parachute/icon.svg` — visual

Inline SVG, small (~200 bytes), content-type `image/svg+xml`, nosniff header.

### 3. `services.json` entry — routing

Written to `~/.parachute/services.json` at install time or first boot:

```json
{
  "name": "parachute-vault",
  "port": 1940,
  "paths": ["/vault/default"],
  "health": "/vault/default/health",
  "version": "0.3.0",
  "displayName": "Vault",
  "tagline": "..."
}
```

### 4. `GET /.parachute/config/schema` — configuration shape (Phase 2)

JSON Schema describing what the module can be configured with. Example for vault:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "audio_retention": {
      "type": "string",
      "enum": ["keep", "until_transcribed", "never"],
      "default": "keep",
      "title": "Audio retention",
      "description": "What to do with audio attachments after transcription."
    },
    "scribe_url": {
      "type": "string",
      "format": "uri",
      "title": "Scribe URL",
      "description": "URL of the scribe service for transcription."
    }
  }
}
```

Hub renders this schema into a configuration form. No auth needed to READ the schema.

### 5. `GET /.parachute/config` — current values (Phase 2)

Returns the current configuration as a JSON object matching the schema. Auth: `<module>:admin` scope (or unauthenticated for certain read-only summaries — TBD).

### 6. `PUT /.parachute/config` — write config (Phase 3)

Validates input against the schema, applies it, returns the stored config. Auth: `<module>:admin` scope. Hub PUTs here when user changes config.

### 7. OAuth endpoints (Phase 0+1)

Modules that need user authentication delegate to the hub (vault included). A module:
- Receives hub-issued tokens.
- Validates them via introspection (hub's `/oauth/introspect`) OR JWT signature (hub's JWKS).
- Enforces scopes against its endpoints.

Modules that don't need auth (scribe today, with CORS `*`) can skip this until they grow one.

## The hub as orchestrator

The hub (served at `/` on the ecosystem origin) is itself a module — it happens to also orchestrate. It provides:

- **Discovery view**: cards listing all installed modules.
- **Module detail**: click a card, see info + current config (read-only for Phase 2).
- **Configuration UI**: forms rendered from each module's `/.parachute/config/schema`, PUT-ing to `/.parachute/config` (Phase 3).
- **Auth surface**: `/oauth/*` endpoints (issuer, authorize, token, register) — Phase 0.
- **Consent UI**: human-readable scope prompts at authorization time — Phase 2+.

The hub's own config schema describes CLI-managed settings: canonical origin, exposed layers, port allocations. Meta-but-consistent.

## Inter-module wiring

Modules can declare **dependencies**:

```json
{
  "dependencies": {
    "scribe": {
      "optional": true,
      "scopes": ["scribe:transcribe"],
      "configures": { "scribe_url": "{services.scribe.url}" }
    }
  }
}
```

When vault is installed, hub sees vault declares scribe as an optional dependency. If scribe is also installed, hub offers: "Auto-configure vault to use scribe for transcription?" User confirms. Hub writes `scribe_url` into vault's config via `PUT /.parachute/config`. Done.

This makes the ecosystem **self-assembling**: adding new modules that fit together requires no manual wiring.

## Scope format

`<service>:[<resource>:]<action>`

### Launch (Phase 0+1):
- `vault:read`, `vault:write`
- `scribe:transcribe`
- `hub:admin` (reserved, not yet used)
- `channel:send` (future)

### Post-launch (Phase 2+, per-resource):
- `vault:<name>:read`, `vault:<name>:write` — limit to named vault
- `vault:<name>:<path-prefix>:read` — limit to a path within a vault (future)
- `scribe:<provider>:transcribe` — limit to a transcription provider (future)

Parser rules:
- Split on `:`. First segment is service. Last is action.
- Middle segments (0 or more) are a resource hierarchy.
- `vault:read` grants "read any vault, any path." `vault:default:read` narrows to "default" vault only.
- Wildcards: `vault:*:read` is equivalent to `vault:read` (semantic parity). Useful for explicit patterns.

### Scope inheritance:
- `vault:write` implies `vault:read` (writes subsume reads).
- `<scope>` implies `<scope>:<sub-resource>` for any sub-resource. `vault:read` ⊃ `vault:default:read` ⊃ `vault:default:notes:read`.

### Scopes in practice:
- Notes requests `vault:read vault:write scribe:transcribe` on OAuth consent.
- User sees "Notes wants: read + write your vault, transcribe audio."
- Grant gives Notes a token; Notes uses it for everything.
- Step-up: Notes initially requests `vault:read` only; when user records first voice memo, Notes requests `vault:write scribe:transcribe` via a refresh flow; hub re-prompts for the new scopes.

## Module manifest (future, canonical)

A module's full declaration lives in a single document — either built from the contracts above, or exposed as `GET /.parachute/manifest`:

```json
{
  "name": "parachute-vault",
  "version": "0.3.0",
  "displayName": "Vault",
  "tagline": "...",
  "kind": "api",
  "iconUrl": "/vault/default/.parachute/icon.svg",
  "capabilities": ["store-notes", "tag", "link", "search", "graph", "mcp"],
  "endpoints": {
    "oauth": ["/oauth/authorize", "/oauth/token"],  // if module provides OAuth
    "api": "/vault/<name>",
    "mcp": "/vault/<name>/mcp",
    "info": "/vault/<name>/.parachute/info",
    "config": "/vault/<name>/.parachute/config"
  },
  "scopes": {
    "defines": ["vault:read", "vault:write", "vault:<name>:read", "vault:<name>:write"],
    "requires": []
  },
  "dependencies": {
    "scribe": { "optional": true, "scopes": ["scribe:transcribe"], "configures": { "scribe_url": "{services.scribe.url}" } }
  },
  "config": {
    "schemaUrl": "/vault/<name>/.parachute/config/schema",
    "configUrl": "/vault/<name>/.parachute/config"
  }
}
```

This is the **canonical description** of a module — machine-readable, everything hub needs, everything a third-party integration needs. Modules can compose this from their contracts or provide it directly.

## Extensibility path

**A first-class goal**: any package, any scope, any name. The ecosystem doesn't require `@openparachute/` or a `parachute-*` prefix for a module to plug in. First-party packages are just the ones the Parachute team ships; they follow the same contracts as everyone else.

A third-party wants to build a Parachute-compatible module:

1. Implement the 4 minimum contracts (info, icon, services.json registration on install, well-known reachability).
2. Ship a **`.parachute/module.json`** in the npm package describing the integration:

   ```json
   {
     "name": "my-service",
     "manifestName": "my-service",
     "displayName": "My Service",
     "tagline": "What the service does",
     "kind": "api",
     "port": 7001,
     "paths": ["/my-service"],
     "health": "/health",
     "startCmd": ["bin/my-service", "serve"],
     "scopes": { "defines": ["my-service:read", "my-service:write"] },
     "dependencies": { "vault": { "optional": true, "scopes": ["vault:read"] } }
   }
   ```

   This is the **canonical self-description** of a module — everything the CLI and hub need, declared in one file the author controls.

3. Pick a port outside the reserved Parachute range (1939–1949). CLI warns on install if you land inside it, but doesn't block.

4. Optionally implement config (`/.parachute/config/schema`, `/.parachute/config`).

5. Optionally accept hub-issued OAuth tokens with your scope namespace.

6. Publish to npm under **any** scope — `@yourorg/foo`, `something-parachute`, `my-cool-thing`, anything. The package's `module.json` is what makes it a Parachute module, not its name.

### How the CLI consumes this

`parachute install <package>` runs:

1. `bun add -g <package>` — standard npm install, no naming constraint.
2. Reads `<package>/.parachute/module.json` from the installed artifact.
3. Validates it against the module-manifest schema.
4. Writes a services.json entry using the declared `name`, `port`, `paths`, `health`, `displayName`, `tagline`, `kind`.
5. Registers the declared `startCmd` so `parachute start <name>` knows what to spawn.

The CLI's first-party `SERVICE_SPECS` record becomes a thin fallback for packages that pre-date the module.json convention (or retires entirely once all first-party packages ship module.json). Today it's hardcoded for vault/notes/scribe/channel — **that hardcoding is a first-party shortcut, not an architectural limit**.

### Scope namespacing

Third-party modules declare their own scope namespace matching the module name. A `my-service` module defines `my-service:read`, `my-service:write`, etc. Hub renders consent for these scopes the same as first-party ones. The hub-as-OAuth-issuer architecture means the hub signs tokens with these scopes and the module validates them against the hub's JWKS.

No central registry for scope names is required — names are scoped by module name, which is already unique across the ecosystem (services.json entries must have unique names).

### What this requires from the CLI before it's real

Not blocking launch, but the work items when we pick this up:

- Replace hardcoded `SERVICE_SPECS` with "discover from installed package's `module.json`."
- `parachute install` drops the `knownServices()` check; accepts any package string.
- Validation step for module.json schema at install time (reject malformed modules early).
- Hub renders any services.json entry regardless of `name` prefix. (Already true — hub doesn't inspect names.)
- Port-coherence enforcement stays as a warning (already the case per the `service-spec.ts` port-reservation table).

### Why this matters

The module protocol stays **open by construction**. Parachute's ecosystem doesn't succeed because we built enough first-party modules — it succeeds when third parties can build Parachute-compatible tools without asking us first. The contracts are the standard; the Parachute CLI + hub are the reference implementation; the ecosystem is anyone who speaks the protocol.

Comparable: the Model Context Protocol (MCP) works this way. Anthropic doesn't control who builds MCP servers — the spec controls the contract, and anyone implementing it is a first-class participant. Parachute's module protocol is the same shape.

## Phasing recap

- **Phase 0 (launch, 2026-04-23)**: OAuth issuer at hub origin, endpoints proxy to vault. services.json + `/.parachute/info` + `kind` field.
- **Phase 1 (post-launch, 1–2 weeks)**: `services` catalog in token response, notes auto-populates, consent UI reskinned in hub.
- **Phase 2 (post-launch, 2–4 weeks)**: Scope enforcement per service, `/.parachute/config` endpoints, step-up permissions, hub renders read-only config dashboards.
- **Phase 3 (post-launch, 4–8 weeks)**: `PUT /.parachute/config`, inter-module wiring auto-config, module manifest, third-party module support.
- **Phase 4+ (open-ended)**: dedicated auth service, scope-based billing entitlements, cloud deployment (see cloud sketch).

## Principles

1. **Modules are cheap.** Implementing the contracts is ~100 LOC. No framework lock-in.
2. **Hub is thin.** It orchestrates but doesn't own module logic. Module authors own module behavior.
3. **Contracts are stable.** Once published, module contract shapes don't break. Additions are optional; removals require a major version.
4. **Config is schema-first.** Every setting has a JSON Schema entry with a human-readable title + description. Hub renders from schema; no hand-coded config UIs.
5. **Scope is granular, additive, inheritable.** Users grant what clients need, no more.
6. **Local-first, cloud-native-ready.** Same contracts, same URLs, different deployment. Cloud is a hosting option, not a separate product.
7. **Self-assembling.** Modules declare dependencies; hub wires them automatically with user consent.
