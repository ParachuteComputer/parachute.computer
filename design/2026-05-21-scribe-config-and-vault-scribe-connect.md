---
title: "Scribe configuration via hub admin SPA + vault↔scribe UI connection"
description: "What scribe's `.parachute/config/schema` needs to grow so the hub admin SPA (hub#260) can configure transcription providers, per-provider credentials, and cleanup providers — including the gnarly `claude setup-token` flow. Plus the vault#343 wiring that lets a vault auto-transcribe voice uploads through that configured scribe."
---
# Scribe configuration via hub admin SPA + vault↔scribe UI connection

**Date:** 2026-05-21
**Status:** Proposed. Targets v0.6 (Part 1) and v0.6 / Phase 2 (Part 2 — see phasing). Aaron's framing on 2026-05-20: scribe needs its own config surface; vault should be able to send voice uploads to scribe automatically; *neither side should know more about the other than the HTTP contract.*

**Companions:**
- [`2026-04-20-module-architecture.md`](./2026-04-20-module-architecture.md) — module protocol (info / config / services.json / well-known). Where `dependencies.configures` lives.
- [`2026-05-18-v06-deploy-architecture.md`](./2026-05-18-v06-deploy-architecture.md) — hub-as-supervisor single-container deploy. Why loopback service-discovery is enough for v0.6.
- [`2026-05-21-parachute-runner-design.md`](./2026-05-21-parachute-runner-design.md) — sibling "module owns its config + secrets" doc; this design references its secret-storage approach and diverges deliberately for scribe's threat model.
- [`../../parachute-patterns/patterns/canonical-ports.md`](../../parachute-patterns/patterns/canonical-ports.md) — vault 1940 / scribe 1943.
- [`../../parachute-patterns/patterns/service-to-service-auth.md`](../../parachute-patterns/patterns/service-to-service-auth.md) and the `service-to-service HTTP` memory — HTTP + hub-issued JWT is canonical; loopback shared-bearer is the v0.6 stepping stone.
- vault#343 — `vault → scribe handoff: auto-transcribe voice uploads`. The upstream issue this enables.

## The two asks, in one doc

Two concerns landed in one session because they share a phasing edge:

1. **Part 1 — Scribe configuration schema for the hub admin SPA.** Scribe today exposes `GET/PUT /.parachute/config` (Draft-07 schema, PR scribe#45). The hub admin SPA (hub#260) will generically render that schema as a form. The schema covers provider *selection* but not provider *credentials*, not `claude setup-token`, and not the API-token alternatives operators want. Without those, the admin SPA form is shipped but can't fully configure scribe.

2. **Part 2 — Vault ↔ scribe UI connection (vault#343).** A friend uploading a voice memo to their vault should get it transcribed automatically. That requires vault to know scribe's URL + bearer, vault to detect audio MIME types on upload, and the UI to surface a single toggle. The mechanics are small but the binding flow is load-bearing for v0.6's friend-experience-loop.

Part 2 **depends on Part 1 being landed first** — vault can't auto-transcribe through a scribe that hasn't been pointed at a transcription provider. They're a coherent unit and ship together.

---

## Part 1: Scribe configuration schema for hub admin SPA

### What scribe's schema covers today

From `parachute-scribe/src/config-schema.ts` (live shape served at `/.parachute/config/schema`):

| Field | Type | Notes |
|---|---|---|
| `transcribeProvider` | enum (live registry) | parakeet-mlx, onnx-asr, whisper, groq, openai |
| `cleanupProvider` | enum (live registry) | claude, claude-code, ollama, openai, gemini, groq, custom, none |
| `cleanupDefault` | boolean | Run cleanup by default when caller omits the flag |
| `cleanupSystemPrompt` | string \| null | Override built-in cleanup system prompt |
| `cleanupContextTemplate` | string \| null | Template for the proper-nouns block |
| `port` | integer | Server port (restart-required) |

The wire shape is validated server-side by `config-write.ts`; the file written at `~/.parachute/scribe/config.json` is chmod 0o600 at create time (scribe#45 must-fix 2); restart-required fields are surfaced in the PUT response so the SPA can prompt for a restart.

**What's missing** for the hub admin SPA to be a complete config surface:

1. **Per-provider API keys.** `GROQ_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`. Today these come from environment variables only — there's no path to set them from the SPA.
2. **The `claude setup-token` flow.** Subscription-funded Claude (`claude-code` cleanup provider) uses an OAuth-issued token stored at `~/.claude.json`, not an API key. The SPA can't trigger an interactive CLI command from the browser. This is the gnarly bit.
3. **Per-provider model selection.** `OLLAMA_MODEL`, `CUSTOM_CLEANUP_MODEL`, plus model knobs per cloud provider.
4. **Provider-specific extras.** `OLLAMA_URL`, `CUSTOM_CLEANUP_URL` for self-hosted endpoints.

These are exactly the env vars in the README's "Environment variables" section. Today the operator has to drop into a shell, edit `~/.parachute/.env`, restart scribe. v0.6's deploy target is a single Render container — there is no shell. The schema has to absorb these knobs for the SPA to fill the gap.

### Target schema shape (v0.6)

The added structure groups credentials and per-provider knobs under their owning block (`transcribeProviders.<name>`, `cleanupProviders.<name>`). Multiple providers can be pre-populated simultaneously; the SPA collapses or hides inactive ones at render time — a UI concern, not a schema concern. Wire stays camelCase + flat at the top level (matching today's shape); the per-provider sub-objects let the schema grow without flat-namespace collisions. See "Design question 1 — discriminated-union shape" below for why we explicitly chose this over Draft-07 `oneOf` / `if`-`then`-`else` discriminators.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://parachute.computer/schemas/scribe/config.json",
  "title": "Scribe configuration",
  "type": "object",
  "properties": {
    "transcribeProvider": {
      "type": "string",
      "enum": ["parakeet-mlx", "onnx-asr", "whisper", "groq", "openai"],
      "title": "Transcription provider"
    },
    "transcribeProviders": {
      "type": "object",
      "title": "Per-provider transcription settings",
      "properties": {
        "groq": {
          "type": "object",
          "properties": {
            "apiKey": { "type": "string", "writeOnly": true, "title": "Groq API key" },
            "model":  { "type": "string", "title": "Model", "default": "whisper-large-v3" }
          }
        },
        "openai": {
          "type": "object",
          "properties": {
            "apiKey": { "type": "string", "writeOnly": true, "title": "OpenAI API key" },
            "model":  { "type": "string", "title": "Model", "default": "whisper-1" }
          }
        }
      }
    },
    "cleanupProvider": { "type": "string", "enum": ["claude", "claude-code", "ollama", "openai", "gemini", "groq", "custom", "none"] },
    "cleanupDefault": { "type": "boolean", "default": true },
    "cleanupProviders": {
      "type": "object",
      "title": "Per-provider cleanup settings",
      "properties": {
        "claude": {
          "type": "object",
          "title": "Claude (Anthropic API)",
          "properties": {
            "apiKey": { "type": "string", "writeOnly": true, "title": "Anthropic API key" },
            "model":  { "type": "string", "title": "Model", "default": "claude-3-5-haiku-20241022" }
          }
        },
        "claude-code": {
          "type": "object",
          "title": "Claude Code (subscription-funded)",
          "properties": {
            "setupTokenStatus": {
              "type": "string",
              "enum": ["configured", "not-configured", "expired", "unknown"],
              "readOnly": true,
              "title": "claude setup-token status",
              "description": "Read-only — reflects whether ~/.claude.json contains a usable token. Run `claude setup-token` on the host running scribe and click Refresh to update."
            }
          }
        },
        "ollama": {
          "type": "object",
          "properties": {
            "url":   { "type": "string", "format": "uri", "default": "http://localhost:11434" },
            "model": { "type": "string", "default": "gemma4:e4b" }
          }
        },
        "openai":  { "$ref": "#/definitions/apiKeyAndModel" },
        "gemini":  { "$ref": "#/definitions/apiKeyAndModel" },
        "groq":    { "$ref": "#/definitions/apiKeyAndModel" },
        "custom":  {
          "type": "object",
          "properties": {
            "url":    { "type": "string", "format": "uri" },
            "apiKey": { "type": "string", "writeOnly": true },
            "model":  { "type": "string" }
          }
        }
      }
    },
    "cleanupSystemPrompt":   { "type": ["string", "null"] },
    "cleanupContextTemplate": { "type": ["string", "null"] },
    "port": { "type": "integer", "minimum": 1, "maximum": 65535 }
  },
  "definitions": {
    "apiKeyAndModel": {
      "type": "object",
      "properties": {
        "apiKey": { "type": "string", "writeOnly": true, "title": "API key" },
        "model":  { "type": "string", "title": "Model" }
      }
    }
  },
  "x-scopes": {
    "scribe:transcribe": "Submit audio for transcription.",
    "scribe:admin":      "Read and write scribe configuration."
  }
}
```

The shape above is intentionally **additive** to today's schema — every existing field keeps its name, type, and semantics. New fields nest under `transcribeProviders.<name>` and `cleanupProviders.<name>`. Old PUTs keep working; the SPA renders new groups under collapsible per-provider sections.

### Design question 1 — discriminated-union shape

**Decision:** plain nested `transcribeProviders.<name>` / `cleanupProviders.<name>` objects, no `oneOf`/`if`-`then`-`else` discriminators on the top-level schema.

Draft-07 supports `oneOf` for "exactly one of these shapes" and `if/then/else` for conditional sub-schemas, and rjsf renders both. The temptation is to wire `transcribeProvider === "groq"` to *only* show `transcribeProviders.groq.apiKey`, hiding the other providers' fields. We're not going to.

**Why not:**

- The operator may want to **pre-populate credentials for multiple providers** and switch between them later. A `oneOf` discriminator deletes the non-active provider's fields from the wire shape — a switch flow becomes "type your Groq key, save; type your OpenAI key, save; switch to Groq, type your Groq key *again* because the wire dropped it." Storing all per-provider configs and letting `transcribeProvider` pick one at runtime mirrors how operators actually think.
- rjsf's `oneOf` rendering is the buggy corner of the library. Form sections collapse oddly when the active variant changes; default values disappear; field order shifts. Keeping it plain saves the SPA from a known footgun.
- The schema stays trivially writable from a curl loop, which we care about for CI smokes and CLI parity.

The visual collapse — "only show the section for the currently selected provider" — happens **in the SPA's render layer**, not in the schema. The schema says "all per-provider configs are storable simultaneously"; the SPA chooses what to *show* based on the selected provider value. Two layers, two concerns.

### Design question 2 — `claude setup-token` UX from a web SPA

**Decision: Option A** — operator runs `claude setup-token` on the host running scribe, SPA shows a status pill, "Refresh" button re-reads `~/.claude.json` via scribe, status updates.

This is the gnarliest UX question in the doc. `claude setup-token` is interactive: it opens a browser tab for an OAuth flow, the user signs in to Anthropic, the CLI writes a token to `~/.claude.json`. A web SPA can't trigger that — it can't open a process on the host, it can't poll the host filesystem from JavaScript, and we don't want to make hub a setup-token broker.

The three options Aaron's brief raised:

- **A (recommended):** SPA shows "claude setup-token status: not configured. Run `claude setup-token` on the host running scribe (cloud target: `ssh` into the Render shell tab; local: terminal) then click Refresh." Refresh hits scribe's `POST /admin/refresh-claude-token-status`, which re-reads `~/.claude.json` and returns the new status. Status pill flips green when it sees a valid token.
- **B (fallback):** SPA accepts a paste of the OAuth code (operator runs claude setup-token in `--no-browser` mode, copies the code, pastes into the form). Requires scribe to know how to redeem the code, which means coupling scribe to claude-cli's OAuth flow. Adds surface area we don't need.
- **C (overengineered):** Hub becomes a setup-token broker — admin SPA initiates the OAuth flow, hub gets the token, scribe reads it via hub. Coupling between hub and a specific external service (Anthropic's OAuth), special-cased per cleanup provider. Doesn't generalize. Out of scope for v0.6.

**Why A:** lowest coupling, simplest contract, single endpoint to ship (`POST /admin/refresh-claude-token-status`), composes with the friend-experience-loop without requiring hub to know what `claude setup-token` is. The friction — "you have to run a command on the host" — is real for the **Render** deploy target where there's no obvious shell. For Render specifically the friend uses Render's web shell, runs `claude setup-token`, returns to the admin SPA, clicks Refresh. That's documented in the SPA section as inline help text next to the status pill, with a copy-pasteable command.

**For the deploy target without a shell at all** (some future PaaS, or if Render kills shell access), the answer is "the cloud version of this offers an admin-SPA-mediated paste flow" — and we'll ship Option B *as a complement, not a replacement* at that point. v0.6 doesn't need it.

**Status field is read-only** (`"readOnly": true` in Draft-07) — operator can't PUT a status, only `refresh-claude-token-status` mutates it. This prevents the SPA from accidentally writing "configured" without verifying. Restart of scribe is not required for setup-token changes: the `claude-code` cleanup provider reads `~/.claude.json` per-call (verified in `parachute-scribe/src/cleanup/claude-code.ts`), so the next transcription request picks up the new token.

### Design question 3 — secret storage

**Decision:** API keys land in the existing `~/.parachute/scribe/config.json` at chmod 0o600, with `writeOnly: true` on the schema field. **No encrypted secrets.db for scribe in v0.6.** Different posture than parachute-runner's; the divergence is deliberate.

The Draft-07 `writeOnly: true` keyword means "this property may be set but should not be returned by GET." Hub's admin SPA respects writeOnly by **not rendering the current value** (just a "leave unchanged" placeholder); scribe's `GET /.parachute/config` respects writeOnly by **redacting** the apiKey fields to `"***"` or omitting them entirely. The on-disk file holds the plaintext but its permissions are 0o600 and the directory is `~/.parachute/scribe/` (owner-only).

Why diverge from parachute-runner's encrypted-secrets.db pattern:

- **Threat model.** Runner's bearer is a `vault:<name>:write` token — anyone who reads it can corrupt or exfiltrate the entire vault. Scribe's API keys are upstream-provider credentials — losing them is bad (billable usage, key rotation hassle) but doesn't compromise the operator's vault or other modules.
- **Single-tenant host assumption.** Both v0.6 deploy targets (Aaron's laptop; a friend's Render container) are owner-operated, single-tenant hosts. 0o600 + owner-only directory is the same protection runner gets when its `master.key` is 0o600 on the same machine. The "encryption at rest" runner adds is only meaningful in a stolen-disk scenario, which is the same scenario for both modules — and scribe's keys can be **rotated upstream** (delete the Groq key, mint a new one) in seconds, while a leaked vault `pvt_*` token can rewrite years of notes before the operator notices.
- **Complexity tax.** Runner pays the encrypted-secrets.db cost because the bearer it holds is uniquely sensitive. Scribe paying the same cost for upstream provider creds is overengineering for v0.6.
- **Phase 2 upgrade path is clean.** If we later decide to centralize secrets (one master key, all modules read through a hub-mediated secret store), scribe's 0o600 `config.json` gets migrated to that store and the schema's `writeOnly` semantics don't change. Nothing locks us out.

**What the schema does require:**

- All credential fields have `"writeOnly": true`.
- `GET /.parachute/config` omits writeOnly fields entirely, OR returns a sentinel (`"***"`) — pick one and stick with it. Recommend: **omit** (clean wire, no magic strings the SPA has to special-case).
- Scribe's existing atomic writer (`config-write.ts:writeConfigFileAtomic`) already chmods 0o600. No change needed there.
- The SPA renders writeOnly fields as a placeholder ("[stored — leave blank to keep]") and only sends the field on PUT when the operator types a new value.
- Logs and error messages never contain credential values. The existing config-load path already avoids logging config contents; the new code paths follow suit.

### Design question 4 — schema validation + "test connection"

**Decision:** server-side schema validation only on PUT (matches today). Add an **optional** `POST /admin/test-provider/{transcribe|cleanup}/<name>` action endpoint that the SPA exposes as a "Test connection" button next to each provider section. PUT itself accepts any non-empty string as an apiKey without testing it.

Why:

- **PUT validation must not be slow or have external dependencies.** Hitting Groq's `/models` endpoint with the new key on PUT means a network round-trip on every config save — and if Groq is down, the PUT fails despite the local config write being fine. Server-side validation is local-only: type-check, enum-check, range-check.
- **"Test connection" is a separate user intent.** The operator pastes a key, hits Save (PUT) — that succeeds immediately. They optionally click "Test connection" — scribe hits the provider's `/models` (or equivalent) with the new key and reports back. Failure mode shows in the SPA but doesn't block saving.
- **Test-connection endpoint is a Phase 2 nice-to-have, not v0.6.** Ship Part 1 v0.6 without test-buttons; add them in Phase 2 once the basic flow is in operators' hands. The PUT shape stays the same either way.

### Design question 5 — per-provider field structure

**Decision:** `transcribeProviders.<name>` and `cleanupProviders.<name>` are plain object properties, not `patternProperties`, not `additionalProperties`. The provider list grows by adding a new property to the schema (and a new entry in scribe's `providers.ts` registry — already the convention). Adding a provider is a one-file change.

This means the schema enumerates every supported provider by name, twice (once in the `enum` for `transcribeProvider` / `cleanupProvider` selection, once as a property of `transcribeProviders` / `cleanupProviders`). The duplication is fine — both are sourced from the same `providers.ts` registry (already done for the enum; per `config-schema.ts:buildConfigSchema`), and the new per-provider blocks generate from the same source.

Per-provider field shapes — by provider:

| Provider | Fields |
|---|---|
| `parakeet-mlx`, `onnx-asr`, `whisper` (local transcribers) | none required — no API keys, defaults work |
| `groq` (transcribe + cleanup) | `apiKey` (writeOnly), `model` |
| `openai` (transcribe + cleanup) | `apiKey` (writeOnly), `model` |
| `claude` (cleanup) | `apiKey` (writeOnly), `model` |
| `claude-code` (cleanup) | `setupTokenStatus` (readOnly) — no key field |
| `ollama` (cleanup) | `url`, `model` |
| `gemini` (cleanup) | `apiKey` (writeOnly), `model` |
| `custom` (cleanup) | `url`, `apiKey` (writeOnly), `model` |

Local providers having no required fields means the SPA shows "no configuration needed" under their per-provider section — friendly default.

### Design question 6 — migration from env vars

**Decision:** layered resolution; `PUT /.parachute/config` > env var > built-in default. Matches the hub#298 `hub_origin` precedence pattern (config-file > env > default) and the existing scribe precedence convention (`--flag` > `config.json` > env > default per `parachute-scribe/CLAUDE.md`).

On scribe boot, the resolver builds the in-memory config by:

1. Reading `~/.parachute/scribe/config.json` (the persisted SPA writes land here).
2. Falling back to environment variables for fields not set in config.
3. Falling back to built-in defaults for fields not in either.

This means:

- **Existing operators** who set `GROQ_API_KEY=...` in `~/.parachute/.env` continue to work. Their config.json doesn't grow per-provider entries until they touch the SPA. Once they save through the SPA, the config.json wins on next restart — but the env var is still a valid fallback (e.g. for ephemeral CI environments).
- **Render deploy operators** never touch env vars. They configure everything through the SPA. config.json on the persistent disk is the only source of truth.
- **CLI operators** can still edit config.json directly. The SPA is one of several writers, not the canonical one.

**Restart semantics** stay as today (`config-write.ts:RESTART_REQUIRED_FIELDS` = `transcribeProvider`, `cleanupProvider`, `port`). API key changes do **not** require a restart — they're read at request time by the per-provider transcribe/cleanup functions (see `parachute-scribe/src/transcribe/groq.ts` etc., which read `process.env.GROQ_API_KEY` per call today; after this change they'll read from the resolved config per call) — subject to confirmation that no provider module caches the key in module-scope state once the refactor lands (see open question 5). This matters for the friend-experience-loop: paste API key, click Save, the next transcription works without a restart prompt.

> **Implementation flag for the build (not design):** per-request API-key reads will need a small refactor in the transcribe/cleanup provider modules — they currently read `process.env.GROQ_API_KEY` (etc.) at call time. Moving them to read from a shared resolved-config getter that prefers PUT-written values over env is the load-bearing code change. Not blocking the design doc, but worth surfacing: this isn't pure schema work; it's schema + a small provider-module refactor in the same PR.

### Part 1 — wire shape, end to end

The wire response from `GET /.parachute/config` after this lands (illustrative, with secrets redacted):

```json
{
  "transcribeProvider": "groq",
  "transcribeProviders": {
    "groq":   { "model": "whisper-large-v3" },
    "openai": { "model": "whisper-1" }
  },
  "cleanupProvider": "claude-code",
  "cleanupDefault": true,
  "cleanupProviders": {
    "claude":      { "model": "claude-3-5-haiku-20241022" },
    "claude-code": { "setupTokenStatus": "configured" },
    "ollama":      { "url": "http://localhost:11434", "model": "gemma4:e4b" },
    "openai":      { "model": "gpt-4o-mini" },
    "gemini":      { "model": "gemini-1.5-flash" },
    "groq":        { "model": "llama-3.3-70b-versatile" },
    "custom":      { "url": "https://my-endpoint/v1", "model": "my-model" }
  },
  "cleanupSystemPrompt": null,
  "cleanupContextTemplate": null,
  "port": 1943
}
```

Note that `apiKey` is absent from every provider sub-object. The operator sees "key stored — leave blank to keep" in the SPA placeholder.

**Omit-to-keep semantics for `writeOnly` credential fields.** If a writeOnly field is omitted from the PUT body, scribe preserves the existing stored value. Sending a non-empty string replaces the stored value. Sending an empty string (`""`) also preserves — the SPA treats "no value typed" identically to "field omitted." To actually clear a stored credential, the operator uses a separate "clear this credential" admin action (a small `POST /admin/clear-credential/{transcribe|cleanup}/<name>` endpoint, Phase 2 polish), not a null-write through the PUT shape.

This is **deliberately different** from scribe's existing null-as-clear semantics for non-secret string fields like `cleanupSystemPrompt` / `cleanupContextTemplate` (see `config-write.ts:mergeIntoFileShape`), where `null` does clear. Credentials are special because the loss-of-value mode is catastrophic — an operator hitting backspace and firing PUT shouldn't wipe a production API key. Plain strings can be re-typed without side effects; credentials can't. Two semantics, justified by the asymmetry in cost-of-mistake.

---

## Part 2: vault ↔ scribe UI connection (vault#343)

The user-visible flow:

1. Friend uploads a voice memo to their vault — via Notes capture, via REST, via drag-and-drop into the vault directory.
2. Vault detects: this attachment is `audio/*`.
3. Vault calls scribe to transcribe.
4. Transcript becomes a new note in the vault, linked to the original audio attachment.

All in v0.6's single-container deploy, where vault and scribe are co-located hub-children sharing `~/.parachute/`.

### Design question 1 — trigger mechanism

**Decision:** inline at upload time (synchronous detection, asynchronous scribe call), not via a webhook system. **No new vault webhook infrastructure** in v0.6 for this.

The brief raised "vault webhook on new attachment of mime-type audio/\*" as the cleanest option. It's not wrong, but introducing a generic vault webhook surface to power one feature is the wrong order of operations. The trigger lives inline in vault's attachment-write path; when MIME-type-sniffing identifies audio, vault forks an async transcription task. No new event bus.

Why inline:

- **One feature, one code path.** Vault already has the upload pipeline (`POST /api/ingest`, the attachment-write side of `POST /vault/<name>/notes`). Inlining the audio-detect check is a 10-line change vs. building a generic webhook system that has one consumer.
- **Webhooks are a v0.7+ shape.** When vault has multiple event-driven extensions (auto-transcribe, auto-tag, auto-summarize), a generic webhook surface earns its keep. Today it has one. Build the abstraction when the second extension lands.
- **Async happens at the function-call boundary, not the network boundary.** Vault detects audio, returns the upload response to the client (no waiting for scribe), spawns an in-process async task that POSTs to scribe and writes back the transcript when done. The vault REST consumer doesn't block on scribe.

The downside: the auto-transcribe trigger is hard-coded in vault rather than configurable. That's acceptable — when v0.7+ wants webhooks, the trigger becomes "vault publishes `attachment.created` event, an event-handler module subscribes and POSTs to scribe." Same pipeline, factored.

### Design question 2 — vault → scribe service discovery + auth

**Decision:** vault reads scribe's URL from `~/.parachute/services.json` (the canonical hub-maintained registry); vault holds a scribe bearer in its own config (initially populated by hub's inter-module wiring on install). HTTP over loopback within the single-container deploy. **Hub-issued JWTs are the v0.7 path; loopback + shared bearer is v0.6.**

Three options the brief raised:

- **Hub-mediated** (vault → hub → scribe): introduces a hub-side proxy concern with no v0.6 payoff (both services are in the same container; the hub-as-proxy adds latency and an extra hop).
- **Direct loopback with no service discovery** (hardcoded `http://127.0.0.1:1943`): brittle the moment scribe moves to a non-loopback host. Works today but rots in v0.7+.
- **Service discovery via services.json + direct call** (recommended).

services.json is already the canonical registry per [`module-architecture.md`](./2026-04-20-module-architecture.md). Vault reads it on boot to discover `{name: "parachute-scribe", port: 1943, paths: ["/scribe"]}`, constructs the URL `http://127.0.0.1:1943`, holds it through the process lifetime, refreshes on file-change events (chokidar or equivalent). When scribe moves to a different host in v0.7 cloud Tier-1/2 splits, services.json grows an `origin` field; vault honors it without code change.

**Auth — loopback shared bearer for v0.6.** Scribe already supports `SCRIBE_AUTH_TOKEN` (per the README and `src/auth.ts`). At install time, hub generates a random bearer (`openssl rand -hex 32`), sets it as scribe's `SCRIBE_AUTH_TOKEN` env var, and writes it to vault's config as `scribe_bearer`. Vault sends `Authorization: Bearer <scribe_bearer>` on every transcribe call.

This bearer is:

- Generated once at install time (no key-rotation flow in v0.6 — Phase 2 polish).
- Stored in vault's config at the same 0o600 perms as scribe's own config.
- A **shared secret**, not a JWT — scribe doesn't validate scope, just compares the string. This is fine for loopback in a single-container deploy; the trust gradient is flat.
- Surfaced in vault's `/.parachute/config` schema with `writeOnly: true` (same pattern as scribe's API keys).

**The v0.7 upgrade path** is hub-issued JWT with scope `scribe:transcribe`. Scribe already has the JWT validation seam (`parachute-scribe/src/hub-jwt.ts`, `auth-hub-jwt.test.ts`). When hub-as-issuer issues service-to-service JWTs (per [`service-to-service-auth.md`](../../parachute-patterns/patterns/service-to-service-auth.md) and the `service-to-service HTTP` memory), vault swaps the bearer for a hub-issued JWT and scribe validates scope server-side. No design change required — the wire shape stays `Authorization: Bearer <token>`, only the token's contents (and issuer) change.

### Design question 3 — output shape

**Decision:** transcript lands as a new note at `<attachment-dir>/<attachment-name>.transcript.md`. Frontmatter links the transcript back to the source attachment via vault's relations system.

Concrete example. Friend uploads `Voice 2026-05-21 09-13.m4a` to their `inbox/` directory in the default vault. Vault writes:

```yaml
---
title: Transcript of Voice 2026-05-21 09-13.m4a
tags: [transcript, capture]
created_at: 2026-05-21T09:13:42Z
transcript_of: inbox/Voice 2026-05-21 09-13.m4a
transcript_status: complete
transcribe_provider: groq
cleanup_provider: claude-code
transcribe_duration_ms: 8420
---

<scribe-returned text>
```

Path convention: `<original-attachment-path>.transcript.md`. Predictable, sortable next to the source file, no special directory. The `transcript_of` frontmatter field uses vault's existing relation field type — the transcript shows up in the vault graph linked to the original audio.

Failure mode (scribe down, API key invalid, network timeout): the transcript note is still written with `transcript_status: failed` + `transcript_error: "..."` in frontmatter and an empty (or stderr-tail) body. The friend sees a placeholder note that explains the failure, can retry from the UI, and the original audio is never deleted. (See design question 5.)

### Design question 4 — where the operator enables this

**Decision:** the toggle lives on the **vault config page**, not the scribe config page. It's the friend's vault's behavior they're configuring — "when I upload audio here, transcribe it."

The vault config schema grows three fields:

| Field | Type | Notes |
|---|---|---|
| `autoTranscribe.enabled` | boolean | Master toggle. Default false. |
| `autoTranscribe.scribeUrl` | string (uri, readOnly) | Auto-populated by hub inter-module wiring from `services.scribe.url`. Read-only in the SPA — operator can't point at an arbitrary scribe. |
| `autoTranscribe.scribeBearer` | string (writeOnly) | Auto-populated by hub at install time. Writable for operators who rotate or replace it. |

**Why vault config, not scribe config:**

- The vault is the entity being configured ("auto-transcribe *my uploads*"). The scribe is the engine; multiple vaults could share one scribe with their own per-vault toggles.
- Mirrors the module-architecture inter-module-wiring shape from [`module-architecture.md`](./2026-04-20-module-architecture.md) (`dependencies.configures` block): vault declares `dependencies.scribe.optional = true`; hub auto-populates `autoTranscribe.scribeUrl` from `services.scribe.url` on install. The `dependencies.configures` mechanism is the canonical place for "hub knows how to wire vault to scribe."
- Single config surface for "what should happen to my uploads" — the friend doesn't need to context-switch to scribe's config page to set up a vault behavior.

**What the SPA shows on the vault page:**

```
[ ] Auto-transcribe voice uploads
    Transcribe audio files automatically when uploaded. Uses scribe at:
    http://127.0.0.1:1943  (configured)
```

The "(configured)" pill is green when `autoTranscribe.scribeUrl` resolves to a running scribe and `setupTokenStatus` (read through scribe's config) is `configured` or an API key is present. Otherwise the pill is grey/red with a "Configure scribe" link to scribe's admin page. This is the only place the vault SPA reaches across to scribe — a status check, no state mutation.

### Design question 5 — error handling

**Decision:** failures are visible as `transcript_status: failed` notes; no automatic retry in v0.6; original audio is never deleted (or even marked for cleanup). The friend retries from the SPA.

Failure modes vault has to handle:

- **Scribe unreachable.** Network error, process not running, port closed. Vault writes a failed transcript note with `transcript_error: "connection refused"`.
- **Scribe returns 4xx.** Bad bearer, malformed multipart, no transcription provider configured (scribe's getProvider call returns "no provider" error). Vault captures the error body and writes it to `transcript_error`.
- **Scribe returns 5xx or 200 with empty text.** Provider failure mid-call (Groq down, claude-cli panic, etc.). Same `transcript_status: failed`, `transcript_error: <body>`.
- **Timeout.** Scribe takes longer than the configured timeout (default 5min for v0.6 — most transcriptions finish in under 30s; 5min is generous for long captures). `transcript_status: failed`, `transcript_error: "scribe timeout"`.

**Retry:** the vault SPA shows a "Retry transcription" button on any `transcript_status: failed` note. Clicking it re-POSTs the original audio to scribe and overwrites the transcript note with the result. **No automatic retry on a timer.** Reasons: avoids surprise billable usage (each retry potentially costs API quota); avoids fighting whatever upstream issue caused the original failure; gives the friend control.

Audit trail: every transcription attempt (success or failure) is recorded — failed attempts as the note's content, with stderr-tail / error message in frontmatter. The friend can query `tag:transcript transcript_status:failed` to see all failures in their vault. Same audit substrate, same query language, same surface as everything else vault stores.

### Design question 6 — multi-vault, multi-scribe

**Decision:** v0.6 = one vault, one scribe per install. Multi-scribe / multi-vault is parachute-cloud territory (Phase 3+). Acknowledged, not designed.

The single-container v0.6 deploy ([`2026-05-18-v06-deploy-architecture.md`](./2026-05-18-v06-deploy-architecture.md)) is explicit: hub supervises *one* vault, *one* scribe, *one* notes. Multiple vaults or multiple scribes within one install are out of scope.

What this means for the design:

- vault's `autoTranscribe.scribeUrl` is a single URL, not a list. The SPA UI is a single status pill, not a picker.
- scribe doesn't grow a "which vault is allowed to call me" allowlist. Its `SCRIBE_AUTH_TOKEN` is a single bearer.
- Hub's inter-module wiring assumes 1:1. The `services.json` entries for scribe and vault are single instances.

If a single operator wants two vaults on one host, they run two parachute installs (different `PARACHUTE_HOME`, different install slug). Same answer as runner's same question, same trust-gradient logic. Cloud-multi-tenant adds the necessary infrastructure (per-tenant service binding, scoped JWTs per tenant) when that demand materializes; not v0.6.

---

## Phasing

### v0.6 ship

- **Part 1 full:** scribe schema extension covering per-provider apiKey/model/url/setupTokenStatus, `POST /admin/refresh-claude-token-status` endpoint, writeOnly redaction in GET, env-var fallback for unset fields. The hub#260 generic admin form renders the new shape without hub-side changes (the whole point of the generic-form approach).
- **Part 2 basic flow:** vault grows `autoTranscribe.{enabled,scribeUrl,scribeBearer}` config fields, hub inter-module wiring populates them on install, vault inlines the audio-detect + transcribe-and-write path, failed transcripts surface as `transcript_status: failed` notes with a "Retry" button.
- Both ship in v0.6 because Part 2 depends on Part 1 and the friend-experience-loop ("upload voice → see transcript") is a load-bearing v0.6 demo. Shipping Part 1 without Part 2 means the friend can configure scribe but has nothing to send to it through the SPA. Shipping Part 2 without Part 1 means vault tries to send to an unconfigured scribe and gets failures end-to-end.

### Phase 2 (v0.7+)

- **Test-connection buttons** next to each provider section in scribe's SPA. POST `/admin/test-provider/...`.
- **Hub-issued JWT for vault → scribe** replacing the shared bearer. Scribe validates scope server-side. No SPA change.
- **Auto-retry on transient failures** (scribe 5xx, network errors), with backoff and a per-attempt cap, surfaced as `transcript_retry_count` in frontmatter.
- **Live-tail of transcription progress** in the vault SPA (websocket or SSE from scribe). Today's flow is fire-and-write-when-done; live progress is polish.
- **Per-provider fine-grained config:** Whisper model selection in detail (large-v3 / large-v3-turbo / etc.), language defaults, prompt biasing per provider.
- **Audio retention policy:** "keep / until_transcribed / never" — the vault config field from [`module-architecture.md`](./2026-04-20-module-architecture.md)'s example. Defaults to keep for v0.6.

### Phase 3 (deferred)

- Multi-vault / multi-scribe within one install.
- Multi-tenant cloud (parachute-cloud).
- Per-vault provider selection ("vault A uses Groq, vault B uses local whisper") — only meaningful when there are multiple vaults.
- Plain webhook surface in vault (`attachment.created` event) once a second extension wants it.

---

## Open questions flagged for Aaron

These are flagged for the build, not blockers to start:

1. **claude-code provider rename / merge with `claude`.** Scribe today has both `claude` (Anthropic API) and `claude-code` (subscription-funded via `claude setup-token`). The naming is confusing — `claude-code` reads like "the Claude Code IDE / CLI" which it kind of is. Is there a cleaner pair like `anthropic-api` + `claude-subscription`? Touches the wire shape (provider enum names), so worth deciding before this lands.

2. **What scribe does on first boot with no providers configured.** If neither a default API key nor `claude setup-token` is set up and the friend hasn't touched the SPA yet, what's the default `transcribeProvider`? Today it falls back to `parakeet-mlx` which only works on Macs. For the Render deploy target, the friend hits a 500 the first time they upload audio. Options: (a) ship `parakeet-mlx` as default and let the SPA's "Test connection" flag the mismatch loudly, (b) detect platform at scribe boot and default to a cloud provider on Linux containers if any API key is in env, (c) hard-require provider selection in the first-boot wizard before allowing audio upload. Recommend (c) — surface the requirement up-front, refuse to silently ship a broken transcribe path.

3. **vault's `scribe_bearer` rotation.** Today's design: hub generates it once at install, never rotates. If the bearer leaks or the operator wants to invalidate it, they have to manually regenerate and re-paste in two places (vault config + scribe `SCRIBE_AUTH_TOKEN` env). A "rotate scribe bearer" button in the hub admin SPA is Phase 2 polish but a friend might hit the need in v0.6 if they accidentally share their config. Filed as a known gap; not blocking.

4. **The "claude setup-token on Render" friction is real.** Render's web shell works for this but the friend has to find it, run the command, watch a browser tab open (in their local browser, not in the Render web shell context — they sign in to Anthropic, then the CLI catches the redirect back). This is the gnarliest part of the friend-experience-loop for the claude-code provider specifically. Worth a dedicated section in the deploy docs (`parachute.computer/deploy/`) once the flow is verified end-to-end on Render. If it turns out claude setup-token's OAuth flow doesn't terminate cleanly in Render's web shell (no callback URL available?), we need to fall back to either Option B (paste OAuth code) or API-only on Render — a real concern, not a hypothetical, since I haven't smoked it.

5. **scribe restart semantics on apiKey writes.** I claimed apiKey changes don't require a restart because the per-provider modules read env vars per call today. Verifying: `parachute-scribe/src/transcribe/groq.ts`, `cleanup/claude.ts`, etc. all currently `process.env.GROQ_API_KEY` at call time — moving that read to a config getter is the small refactor I flagged. If the refactor is bigger than expected (some providers cache the key in module-scope state), restart-required might need to expand. Worth eyeballing in the implementation PR before promising no-restart-on-key-change in the release notes.

---

## Places where the design surfaced needed code work

Two things this design needs that aren't pure schema/wire-shape changes — flagged so the build PR scope is clear:

1. **Per-request API-key reads in scribe's provider modules.** Today `groq.ts`, `openai.ts`, `claude.ts` (cleanup), and the rest read `process.env.X_API_KEY` directly at call time. After this design lands, they need to read from a shared resolved-config getter that prefers PUT-written values over env vars. Small, ~20-line refactor per provider module, but it's load-bearing for the no-restart-on-apiKey-change UX claim. (Design question 6, with explicit callout in question 5 of the open-questions section.)

2. **Vault's inline audio-detect + async transcribe pipeline.** Vault doesn't currently MIME-sniff uploads beyond what's in its existing attachment-handling code. Adding the `audio/*` detect + fork-to-async-task is new code in vault. Estimated ~150 lines including the `transcript_status: failed` write path, the SPA "Retry" button wiring, and the inter-module-wiring hookup for `autoTranscribe.scribeUrl`. Not a design issue, but it's the code that this design unblocks — worth tracking in vault as a single issue, not split across many.

Neither is a design blocker — both are clear enough to brief into the build PRs as soon as this doc lands. Flagging here so the next session knows the doc isn't sufficient on its own.

---

## Why the architecture is right

Two equivalences make these two parts a coherent whole:

**Schema-first config is the same equivalence the rest of the ecosystem uses.** Scribe owns its config schema. Hub renders it generically. The SPA never knows what a "transcription provider" is — it knows how to render a JSON Schema. When a new provider lands, scribe's `providers.ts` grows an entry, the schema's `enum` grows a value, the SPA picks it up for free. The friend never has to wait for hub to learn about it. Same shape as `module-architecture.md` describes for every module's config.

**Stateless scribe + orchestrating vault is the same equivalence the 0.3.0 stateless-scribe initiative cemented.** Scribe takes audio + context, returns text. Vault decides when to call it, what context to push, where to file the result. The two services know nothing about each other's internals — scribe doesn't know "vaults exist," vault knows nothing about Groq's API. They share a multipart contract and a bearer. That keeps the trust gradient flat (one service can't escalate the other's privileges), keeps the upgrade path clean (vault gains hub-issued JWT without scribe changing), and keeps the doc-set small (one contract to document, two consumers of it).

Both parts are small on purpose. Schema additions are additive. Vault's pipeline is one inline trigger and one async write-back. The cleverness lives in *not* doing the things that would feel obvious to overbuild — no webhook surface, no encrypted secrets store for scribe, no `oneOf` discriminator gymnastics, no hub-as-OAuth-broker for setup-token. v0.6 ships the simplest shape that makes the friend-experience-loop work end-to-end; Phase 2 adds polish; Phase 3 adds the cloud-shaped multi-tenancy when there are tenants to multiplex.
