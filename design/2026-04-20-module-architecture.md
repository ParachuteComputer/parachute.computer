# Parachute module architecture

**Date:** 2026-04-20
**Status:** Canonical architecture north-star for post-launch evolution. Launch ships with a subset; this doc defines the target.

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

A third-party wants to build a Parachute-compatible service:

1. Implement the 4 minimum contracts (info, icon, services.json, well-known availability).
2. Pick a canonical port outside the reserved Parachute range (1939–1949).
3. Optionally implement config (`/.parachute/config/schema`, `/.parachute/config`).
4. Optionally accept hub-issued OAuth tokens with your scope namespace.
5. Publish to npm as `@yourorg/parachute-<name>`.

The CLI's `install` command works the same way:

```
parachute install @yourorg/foo
```

If the package implements the contracts, the hub renders it automatically. No special blessing required.

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
