---
layout: base.njk
title: "Parachute Vault 0.4.5 — What changed"
description: "Parachute Vault 0.4.5 closes a substrate cycle that started at launch. Lossless round-trip to disk, non-markdown notes, hub-mediated auth, surgical update-note edits, and a real upgrade path from 0.2.4. Includes a detailed reference for integrators with commit SHAs and PR refs at every claim."
permalink: /preview/vault-0.4.5-arc/
eleventyExcludeFromCollections: true
---
<style>
.arc-hero {
    max-width: var(--content-width);
    margin: 4rem auto 2.5rem;
    text-align: left;
}
.arc-hero p.arc-eyebrow {
    color: var(--accent);
    font-family: var(--mono);
    font-size: 0.78rem;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    margin-bottom: 0.6rem;
}
.arc-hero h1 {
    font-family: var(--serif);
    font-size: clamp(2.25rem, 3.6vw, 2.9rem);
    font-weight: 400;
    letter-spacing: -0.025em;
    line-height: 1.12;
    color: var(--fg);
    margin-bottom: 0.8rem;
}
.arc-hero p.arc-lead {
    font-size: 1.08rem;
    line-height: 1.65;
    color: var(--fg-muted);
    max-width: 38rem;
}
/* Suppress drop-cap on the page body — this is a doc, not a blog post. */
.post-content > p:first-of-type::first-letter {
    font: inherit;
    color: inherit;
    float: none;
    padding: 0;
    font-size: inherit;
    line-height: inherit;
}
.post-content h2 {
    margin-top: 2.5rem;
}
.post-content h2:first-of-type {
    margin-top: 1.5rem;
}
/* Numbered action list — same shape as .post-content ul but readable as steps. */
.post-content ol {
    list-style: decimal;
    margin: 0 0 1.5rem 1.5rem;
    padding: 0;
}
.post-content ol li {
    color: var(--fg);
    padding: 0.55rem 0;
    line-height: 1.65;
}
.post-content ol li::marker {
    color: var(--accent);
    font-family: var(--mono);
    font-size: 0.92em;
}
/* Reference section — collapsible. Style the disclosure summary to feel
   intentional, not browser-default. */
details.arc-reference {
    margin: 3.5rem 0 2rem;
    padding: 0;
    border: 1px solid var(--border);
    border-radius: 12px;
    background: rgba(255, 255, 255, 0.5);
}
details.arc-reference > summary {
    padding: 1.1rem 1.5rem;
    cursor: pointer;
    list-style: none;
    color: var(--fg);
    font-family: var(--sans);
    font-size: 1rem;
    font-weight: 500;
    line-height: 1.55;
    display: flex;
    align-items: center;
    gap: 0.6rem;
    transition: background 0.15s ease;
}
details.arc-reference > summary::-webkit-details-marker { display: none; }
details.arc-reference > summary::before {
    content: "▸";
    font-family: var(--mono);
    color: var(--accent);
    font-size: 0.85em;
    transition: transform 0.15s ease;
    display: inline-block;
}
details.arc-reference[open] > summary::before {
    transform: rotate(90deg);
}
details.arc-reference > summary:hover {
    background: rgba(243, 240, 234, 0.5);
}
details.arc-reference[open] > summary {
    border-bottom: 1px solid var(--border);
    background: rgba(243, 240, 234, 0.4);
}
.arc-reference-note {
    padding: 0 1.5rem;
    font-size: 0.92rem;
    color: var(--fg-muted);
    line-height: 1.6;
    margin-top: 1rem;
    font-style: italic;
}
.arc-reference-body {
    padding: 0.5rem 1.5rem 1.5rem;
}
/* Tables inside the reference body — same as prior passes. */
.arc-reference-body table {
    width: 100%;
    border-collapse: collapse;
    margin: 1.5rem 0 2rem;
    font-size: 0.9rem;
    line-height: 1.55;
}
.arc-reference-body th,
.arc-reference-body td {
    border-bottom: 1px solid var(--border);
    padding: 0.6rem 0.8rem;
    text-align: left;
    vertical-align: top;
    color: var(--fg);
}
.arc-reference-body th {
    font-family: var(--mono);
    font-size: 0.72rem;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--fg-muted);
    font-weight: 500;
    border-bottom: 1px solid var(--fg-dim);
    background: rgba(243, 240, 234, 0.5);
}
.arc-reference-body td code {
    font-size: 0.84em;
    padding: 0.08em 0.32em;
    background: var(--bg-soft);
    border-radius: 4px;
    color: var(--fg);
}
.arc-reference-body h2 {
    font-family: var(--serif);
    font-size: 1.45rem;
    font-weight: 400;
    margin-top: 2.5rem;
    margin-bottom: 1rem;
    padding-bottom: 0.4rem;
    border-bottom: 1px solid var(--border);
    color: var(--fg);
}
.arc-reference-body h3 {
    font-family: var(--serif);
    font-size: 1.1rem;
    font-weight: 400;
    margin-top: 1.75rem;
    margin-bottom: 0.6rem;
    color: var(--accent);
}
.arc-reference-body p,
.arc-reference-body li {
    color: var(--fg);
    line-height: 1.7;
}
.arc-reference-body p {
    margin-bottom: 1rem;
    font-size: 0.95rem;
}
.arc-reference-body ul {
    list-style: none;
    margin-bottom: 1.25rem;
    padding-left: 0;
}
.arc-reference-body ul > li {
    padding: 0.3rem 0 0.3rem 1.4rem;
    position: relative;
    font-size: 0.94rem;
}
.arc-reference-body ul > li::before {
    content: "›";
    position: absolute;
    left: 0.2rem;
    color: var(--accent-light);
    font-size: 1.05em;
}
.arc-reference-body p code,
.arc-reference-body li code {
    background: var(--bg-soft);
    padding: 0.08em 0.32em;
    border-radius: 4px;
    font-size: 0.87em;
    color: var(--fg);
}
/* CTAs at the foot of the lead — quiet, inline. */
.arc-footnote {
    margin-top: 2.5rem;
    padding-top: 1.5rem;
    border-top: 1px solid var(--border);
    font-size: 0.92rem;
    color: var(--fg-dim);
    line-height: 1.65;
}
.arc-footnote a {
    color: var(--fg-muted);
}
.arc-footnote a:hover { color: var(--accent); }
</style>

<main>

<header class="arc-hero fade-up fade-up-1">
    <p class="arc-eyebrow">Parachute Vault</p>
    <h1>0.4.5 — What changed</h1>
    <p class="arc-lead">Parachute Vault 0.4.5 closes the substrate cycle that started at launch. Your vault now round-trips to a directory of markdown files losslessly. Non-markdown notes are first-class. Auth is hub-mediated with real revocation. <code>update-note</code> grew a surgical edit surface. And there's a clear path from 0.2.4 to here that auto-migrates everything except a few small things you actively touch.</p>
</header>

<div class="post-content fade-up fade-up-2" markdown="1">

## What's new

- **Your vault rounds-trips to disk losslessly.** `parachute-vault export <dir>` writes the whole vault as git-tractable markdown with frontmatter; `parachute-vault import <dir> --blow-away` replays it back to byte-identical state. IDs, typed links, tag schemas, and attachment binaries all survive. Disaster recovery is real; Obsidian round-trip works; partner teams can build dashboards off the directory shape.
- **Non-markdown notes work.** CSV, YAML, JSON, MDX, plaintext — first-class citizens, with metadata inline for markdown-shaped formats and a small sidecar at `.parachute/notes-meta/<id>.yaml` for the rest. `Recipes/pasta.md` and `Recipes/pasta.csv` coexist; the vault doesn't impose markdown anymore.
- **Auth lives at the hub.** Hub-issued JWTs are the canonical path; scopes (`vault:read` / `write` / `admin`) are enforced for real at both HTTP and MCP. Revoking a compromised token at the hub propagates everywhere within ~60 seconds, fail-open during outage. The vault-DB `pvt_*` path stays available for self-hosted-without-hub.
- **`update-note` is a real edit surface now.** SQL-atomic `append` / `prepend` (concurrent appends never overwrite each other), surgical `content_edit { old_text, new_text }` with multi-match guard, frontmatter-aware prepend that skips the YAML block. No more "read the whole doc, edit in memory, write the whole doc back."
- **Sync is faster.** Pass `if_missing: "create"` on `update-note` and external systems can express "create if missing" in a single call. The response carries `created: true|false`, so sync loops know which path fired without a follow-up query. Saves a round-trip per missing note on nightly drift detectors.
- **Indexed queries.** Declare a tag field `indexed: true` and `query-notes` gets the full operator set (`eq`, `ne`, `gt`, `gte`, `lt`, `lte`, `in`, `not_in`, `exists`), `order_by` on indexed fields, plus `has_tags` / `has_links` presence filters. Roughly 5× the query expressiveness 0.2.4 offered.
- **Tag schemas inherit.** Declare `parent_names` on a tag and its effective fields = its own ∪ all ancestors'. `_default` is the implicit universal parent of every note. Set up a hierarchy once; descendants pick up the rules with advisory `schema_conflict` warnings on field overlap.

## To upgrade from 0.2.4 → 0.4.5

Schema migrations and filesystem migrations both run automatically on first post-upgrade boot — they're idempotent, target-wins on conflict, and walk the full `v9 → v18` jump in one init. Your data lands intact. The active work below is short.

1. **Stop the daemon, install, restart.** Schema + filesystem migrations run automatically on first post-upgrade boot. Verify with `parachute-vault status` afterward.
2. **Rename CLI references.** `parachute` → `parachute-vault`. Update shell aliases, shebangs, CI scripts, README files. The new `parachute` (dispatcher) and the renamed CLI's own arg-parser both accept `parachute vault <cmd>` as a forward, so existing launchd / systemd wrappers keep working.
3. **Re-install MCP integration.** Run `parachute-vault mcp-install`. This rewrites `~/.claude.json` to point at the new URL surface (`/vault/<name>/...`) and picks up the new hub-mint auth default. OAuth clients (Claude Desktop, custom integrations) need to remove + re-add their integration so OAuth can re-handshake; curl scripts need hardcoded URLs rewritten.
4. **Audit `config.yaml` for the priv-esc fix.** Open `~/.parachute/vault/config.yaml` and look for `api_keys[].scope: read` entries. Pre-upgrade those silently escalated to full access (vault#233); upgrading is the fix, the audit confirms whether you were affected. Aaron's own deployment found zero affected keys, but the bug existed because the bug existed.
5. **Update scripted JWT minting (if you have it).** JWT audience is now per-vault `aud: vault.<name>`, and hub-issued JWTs reject broad `vault:<verb>` scopes — narrow to `vault:<name>:<verb>`. `pvt_*` tokens are unaffected.

If you bump into something unexpected, [open an issue](https://github.com/ParachuteComputer/parachute-vault/issues).

<p class="arc-footnote">Need more depth? The expandable reference below cites every change to a commit SHA + PR number. For agents / integrators / anyone building on Parachute, that's the audit-grade view. For human upgraders, the section above is enough.</p>

</div>

<details class="arc-reference">
<summary>Detailed reference — every change, with sources</summary>

<p class="arc-reference-note">For builders, integrators, and AI assistants helping someone navigate the upgrade. Cites issues (<code>vault#N</code>), PRs (<code>#NNN</code>), commits (SHA), schema versions, and code paths throughout. If you're a human upgrading, you don't need to read this — the section above is enough.</p>

<div class="arc-reference-body" markdown="1">

## The Arc

Between 0.2.4 (commit `752367b`, 2026-04-18) and 0.4.5 (`66ddd70`, 2026-05-15), Parachute Vault crossed three distinct phases. The CHANGELOG narrative compresses Phase 1 into "0.3.6-rc.1 was the load-bearing release," but the git log shows the load-bearing "release" is a *cluster* of 29 PRs (#128 through #258) across ~16 days under `0.3.6-rc.N` versioning. The CHANGELOG narrates rc.1 and rc.30–rc.39 explicitly; rc.2 through rc.29 are silently absent despite carrying substantive work (catalogued in the "what the CHANGELOG missed" subsection below).

**Phase 1: launch & ecosystem-fit (2026-04-18 → 2026-05-05, v0.2.4 → 0.4.0).** Four overlapping waves:

- *Pre-launch tail (PRs #128–#133).* DELETE on attachments by id (#128); atomic tag rename + multi-source merge (#131); transcription worker with `transcribe: true` (#132); audio-retention API + `"never"` mode (#133).
- *Launch wave (PRs #134–#150).* CLI rename (#134); services.json self-registration (#135); indexed metadata fields (#136); `updated_at = created_at` invariant + backfill (#137, schema v11); URL migration (#138); `has_tags`/`has_links` (#139); operator objects + `order_by` (#141); filesystem moves (#142, #144); `/.parachute/info` + icon.svg (#143); `PARACHUTE_HUB_ORIGIN` + services catalog + `kind: "api"` (#147); module-config endpoints (#148); RFC 8414 path-insertion discovery (#149, #152); help reshape (#150).
- *Auth-substrate wave (PRs #153–#159).* Optimistic-concurrency safe-by-default (#153). Scope enforcement at HTTP + MCP boundary (#154, schema v12). Scribe context provider (#156). `.env` loaded before `SCRIBE_URL` check (#158). Event-driven transcription (#159).
- *Pre-launch operator-UX wave (PRs #160–#168).* MCP-config confirm (#160); `docs/auth-model.md` (#161); loopback bind + `--scope` (#162, #164); README + init prompts reshape (#165, #166); docs sweep `@openparachute/cli` → `@openparachute/hub` (#170); vault-name prompt (#168). 0.3.5 cuts (#171).
- *Hub-JWT through 0.4.0 (PRs #172–#264).* Hub-issued JWT dual-validation (#172, `59add712`) — 0.3.6-rc.1. Then: narrowed scopes + per-vault audience (#180, rc.2); `--json` flag on create (#184, rc.3); five cleanup batches (#187, #188, #190, #193, #194); synthesize-notes (#198, net zero); update-note operations bundle (#200); notes-as-config (#204 — convention shipped then retired); REST token endpoints (#205); 9-nit cleanup (#206); `init --no-autostart` (#207); `create` re-registers services.json (#209); scope-guard library (#212); camelCase aliases + store-routing (#224); pvt_* banner beforeunload (#225); generalized date_filter (#230); FTS routing fix (#231); typecheck cleanup (#232); **priv-esc fix** (#233); empty-note + batch-cap (#235); tag-scoped tokens (#241, schema v13, rc.30); single-row tag identity (#245, schema v14, rc.31); `note_schemas`+`schema_mappings` tables (#249, schema v15, rc.32); v14 wrap (#251, rc.34); admin SPA A/B/C (#219, #220, #222); per-vault mount + three follow-ups (#252, #254, #255, #256); per-vault token storage (#258, schema v16, rc.39); batch atomicity (#260); `.changes` → `RETURNING` (#262). 0.4.0 cuts (#264).

**Phase 2: maturation (PRs #269–#286, 2026-05-09 → 2026-05-10).** Audit-driven retirement of `note_schemas`/`schema_mappings` + 6 MCP tools + `synthesize-notes` (#269, schema v17). Tag schema inheritance + `_default` (#272). `vault-info` projection (#273). Full tag rename cascade (#275). Stats-line distinction (#280). Hub revocation list (#281, scope-guard 0.2.0). MCP tool count drops 16 → 9. 0.4.2 cuts. `dateFilter` recognizes `updated_at` + `include_content: false` (#286).

**Phase 3: substrate completion (PRs #289–#332, 2026-05-10 → 2026-05-15).** HTTP bracket-style metadata filter (#289); 0.4.3 cuts; hub-mint default + project-level + multi-vault (#291, 0.4.4-rc.1); interactive walkthrough (#292); preview-accuracy pin (#301); `uninstall --skip-daemon` (#303); `bun test` web/ui exclusion (#304); MCP-install plan close (#305); HTTP `validation_status` symmetry (#307); portable-markdown PR 1 (#317) + PR 2 (#319); Gitcoin ergonomics (#320); REST `if_missing=create` link symmetry (#322); empty-notes-valid restoration + daemon-busy detection (#324); file-extension support (#329, schema v18); case-collision + ambiguity (#331). 0.4.5 stable cuts (#332).

The headline shape: 0.2.4 was a single-host vault with OAuth + backup + tokens. 0.4.5 round-trips losslessly to git (vault#308), handles non-markdown as first-class (vault#328, schema v18), lives behind a hub that issues / scopes / revokes its tokens (vault#212 Phases 0–4 + Phase A), validates against a 2296-note real vault with zero silent loss, has 9 MCP tools (peaked at 16), sits at schema v18 (from v9 — nine migrations: v10 indexed-fields scaffold, v11 `updated_at` backfill, v12 scopes, v13 scoped_tags, v14 single-row tag identity, v15 note_schemas/schema_mappings, v16 per-vault tokens, v17 retire v15, v18 extension column).

## Themed changes

### URL Surface & Naming Migrations (PRs #134, #138, #142, #144, #170)

The single biggest upgrader-facing change in the entire arc.

- **URL migration (PR #138, `7372a7da`).** One URL shape: API at `/vault/<name>/api/...`, MCP at `/vault/<name>/mcp`, OAuth at `/vault/<name>/oauth/{register,authorize,token}`, discovery at `/vault/<name>/.well-known/oauth-*`, published notes at `/vault/<name>/view/:id`. Unscoped `/api`, `/mcp`, `/oauth/*`, `/view/*` (single-vault auto-default) and previous **plural** `/vaults/<name>/...` prefix are gone (404). Cross-vault `GET /vaults`, `/vaults/list`, `/health` unchanged. Unified MCP endpoint that fanned tool calls across vaults dropped; each MCP session pins to one vault by URL. `list-vaults` MCP tool retired. RFC 9728 `WWW-Authenticate: Bearer resource_metadata="..."` header on every MCP 401.
- **CLI rename (PR #134, `8b1f1cab`).** `parachute` → `parachute-vault`. Frees the `parachute` name for the dispatcher. Dispatcher transparently forwards `parachute vault <cmd>` to `parachute-vault <cmd>`. CLI's own arg-parser accepts leading `vault` prefix (`parachute-vault vault init`), so existing launchd/systemd wrappers continue working.
- **Filesystem restructure (PRs #142 + #144, `8600555` + `9e9764c7`).** Move 1: vault state moves from `~/.parachute/` into `~/.parachute/vault/`. Ecosystem root (`~/.parachute/`) hosts multiple sibling services; `services.json` + `well-known/` stay there, CLI-owned. Move 2: `vault/vaults/` → `vault/data/`; daemon logs into `vault/logs/`. Both moves auto-migrating, idempotent, target-wins. EXDEV mount-boundary failures surface a hint (PR #146).
- **Docs sweep (PR #170, `b804a4d8`).** `@openparachute/cli` → `@openparachute/hub`. Upstream rename on 2026-04-26.

Combined effect: a 0.2.4 user typing `parachute vault status` against `/vaults/work/api/notes` now types `parachute-vault status` against `/vault/work/api/notes`, state under `~/.parachute/vault/data/work/`.

### Hub Integration & Multi-Writer Auth (vault#212 Phase 0–4, Phase A; PRs #147, #172, #180, #194, #205, #212, #233, #258, #265, #281, #291)

Vault becomes a pure OAuth resource server. Trust boundary moves from "vault mints and validates its own tokens" to "vault accepts hub-issued JWTs alongside legacy `pvt_*`, with the hub as canonical issuer."

- **Phase 0 — hub as advertised issuer (PR #147, `86dce9ec`).** `PARACHUTE_HUB_ORIGIN` env makes vault advertise a hub as the OAuth AS. Discovery is origin-aware: hub-origin requests get `issuer = $HUB` with `${HUB}/oauth/*`; other origins (loopback) get vault-rooted. RFC 8414 §2 consistency on both views. Token response includes `services` catalog. `/.parachute/info` returns `kind: "api"`.
- **Phase 1 — hub-issued JWT validation (PR #172, `59add712`, 0.3.6-rc.1).** Dual-validation: JWT-shaped tokens (`eyJ` prefix) route through `src/hub-jwt.ts` — `jose.createRemoteJWKSet` (5-min cache, 30s cooldown), `jwtVerify` checks RS256 + claims, `iss` MUST equal configured hub origin (the **load-bearing trust check**). `pvt_*` callers untouched. `authenticateVaultRequest`/`authenticateGlobalRequest` become async; await ripples through 5 routing call sites + `isViewAuthenticated`.
- **Phase 1.5 — scope narrowing + per-vault audience (PR #180, `5ee65ac1`, 0.3.6-rc.2).** Hub JWT path **rejects broad** `vault:<verb>` scopes — forces picker semantics. Per-vault audience strict-checked. Cross-vault routes (`/vaults`, global `/mcp`) reject hub JWTs (no single audience to bind). `pvt_*` unaffected.
- **Phase 2 — scope enforcement (PR #154, `ed08a2dd`, schema v12).** OAuth-standard whitespace-separated `scopes`. HTTP: reads → `vault:read`, mutations → `vault:write`, `/.parachute/config` → `vault:admin`. Inheritance `admin ⊇ write ⊇ read`. MCP: read tools require `vault:read`; mutation tools require `vault:write`. Read-only tokens only see read tools in `tools/list`; mutation `tools/call` returns 403 `insufficient_scope`. Pre-v12 NULL-scope rows fall back to `legacyPermissionToScopes(permission)` for one release.
- **Phase 3 — per-vault audience binding (PR #180 lands this too).** JWT audience switches from hardcoded `"hub"` to per-vault `aud: vault.<name>`. Tokens minted for `vault.work` can't replay at `vault.personal`. Old `aud: "hub"` claims validate during rolling-update window.
- **Phase 4 — hub revocation enforcement (PR #281, `6b73b867`, 0.4.1-rc.6).** JWTs checked against `<hub-origin>/.well-known/parachute-revocation.json`. Bumps `@openparachute/scope-guard` `^0.1.0` → `^0.2.0`. **60s TTL**. **Fail-open** with last-good cache during outage; **fail-closed** on cold-start. Client-facing 401s for revocation codes are sanitized; full diagnostics route to server-side audit log. Inheritable pattern across vault/scribe/agent.
- **scope-guard library adoption (PR #212, `e3216ef2`; stable in #265).** Replaces vault's JWKS fetch + jwtVerify + cache + audience check + error-classifying glue with one thin adapter around `createScopeGuard({ hubOrigin })`. Public surface preserved.
- **Phase A — hub-mint as default install (PR #291, `225174f`, 0.4.4-rc.1).** `mcp-install` default flips: `--mint` reads `~/.parachute/operator.token`, POSTs to hub. `--token <bearer>` pastes existing; `--legacy-pat` falls back to `pvt_*`. `--scope` expands to `vault:<vault-name>:<verb>`.
- **Cross-vault token rejection (PR #258, `9b39758d`, 0.3.6-rc.39, schema v16).** `tokens.vault_name TEXT` + index. New mints bind to minting vault. Cross-vault use returns 403. Pre-v16 NULL-bound rows authenticate server-wide (legacy compat).
- **OAuth rate-limiter + scope binding (PR #194, `c85ccb90`).** Per-vault rate limiter + memory cap with FIFO eviction; server-side scope binding at `/oauth/authorize`, validated against requested scope at `/oauth/token` per RFC 6749 §3.3.
- **Privilege-escalation fix (PR #233, `a342098d`).** Global `config.yaml`'s `api_keys` parser dropped the `scope` field, leaving `globalKey.scope` undefined. Auth check `globalKey.scope === "read"` then resolved any non-"read" value (including undefined) to "full" — silently escalating user-authored `scope: read` global keys to full access. Mirror the vault-level parser. CHANGELOG buries this as "smaller fixes worth naming"; that undersells it.

### MCP Update-Note Operations Bundle (PRs #200, #320, #322)

The `update-note` MCP tool evolves from blunt full-document replacement into a surgical edit surface.

- **Append + prepend + content_edit + if_updated_at baseline (PR #200, `753ed930`).** Closes vault#79/#80/#81. SQL-atomic append/prepend (avoids RMW race); `content_edit` with mutual-exclusion + multi-match guard (`error_type: "no_match"` / `"multiple_matches"`); `if_updated_at` integration. Wikilink sync correctly reads back post-write. Followups in #193 (typed `409 path_conflict`, PDF+mp4 allowlist) and #206 (frontmatter-aware prepend, `content_edit` returns 422 not 404 on no-match, `isAppendOnly` excludes tags/links). **This PR is absent from any CHANGELOG version entry** — a significant new MCP capability.
- **Upsert via `if_missing: "create"` (PR #320, `f92e9fff`, 0.4.4-rc.12).** `update-note if_missing: "fail" | "create"` (default `"fail"`). On `"create"`: if `resolveNote` returns null, treat update payload as create; `if_updated_at` skipped. Response carries `created: true|false`. Idempotent. ID-vs-path heuristic: if `id` looks path-shaped and `path` isn't explicitly set, use `id` as path — matches canonical-key shapes like Gitcoin's.
- **REST `if_missing=create` link symmetry (PR #322, `c709388e`, 0.4.4-rc.13).** MCP create-on-missing branch processed `links.add`; REST PATCH create-on-missing branch didn't. REST now mirrors MCP. Schema-conflict warning pin on both MCP and REST; MCP `links.add` on create-branch pinned in tests.
- **JSON integer coercion (vault#310, in PR #320).** `SchemaField.type` adds `"integer"`. `Number.isInteger` accepts `5` and `5.0`; rejects `5.5`, `"5"`, non-zero fractional, `NaN`, `Infinity`. Fixes false-positive `type_mismatch` warnings from JSON-emitting drift detectors.

### Indexed Metadata & Query Maturity (PRs #136, #141, #139, #224, #230, #231, #286, #289)

- **Indexed metadata fields (PR #136, `1971fe55`, schema v10 scaffold).** `update-tag` field specs gain `indexed: boolean`. Any tag declaring a field as indexed adds VIRTUAL generated column `meta_<field>` + B-tree index. Index is **universal across notes**, not partitioned by tag. `type` and `indexed` are global; `description` and `enum` per-tag. `indexed_fields` table is the SSOT; column + index drop when last declarer releases the flag. Field-name pattern `[A-Za-z_][A-Za-z0-9_]{0,62}` for SQL-identifier safety.
- **Operator objects + `order_by` (PR #141, `f5b5f736`).** `query-notes metadata` accepts operator objects: full set `eq`, `ne`, `gt`, `gte`, `lt`, `lte`, `in`, `not_in`, `exists`. Multiple ops on one field AND. `order_by` sorts by metadata field (`created_at` tiebreaker). Both paths require `indexed: true` — route through `meta_<field>` to stay O(log n). Loud errors: `UNKNOWN_OPERATOR`, `FIELD_NOT_INDEXED`, `INVALID_OPERATOR_VALUE`.
- **`has_tags` / `has_links` presence filters (PR #139, `969c28ae`).** Booleans on `query-notes`. Correlated `EXISTS`/`NOT EXISTS`. When `tag` is set, `has_tags` is ignored.
- **camelCase alias fix + store-routing (PR #224, `b15b3697`).** Closes vault#214. JSON-RPC drops unknown keys; `excludeTags`/`exclude_tag` previously vanished silently. Now normalized through `normalizeTags`. Routes through `store.queryNotes` so tag-hierarchy expansion is honored. FTS routing fix follows in PR #231 (`f146b06b`).
- **Generalized `date_filter` (PR #230, `72324a09`).** Legacy `date_from`/`date_to` always filtered on `n.created_at` (ingestion time). Now `date_filter: { field, from, to }`. `field` defaults to `created_at`; non-default fields must be `indexed: true`.
- **HTTP bracket-style metadata filter (PR #289, `39acbf38`, 0.4.3-rc.2).** Stripe/JSON:API convention `?meta[field][op]=value`. Array form `meta[field][in][]=v1&meta[field][in][]=v2`. Bridge for `created_at`/`updated_at` accepts only `gte`/`lt`. Parser hardens three silent-data-loss classes: cross-column date filter, shorthand-vs-operator on same field, `[]` array syntax outside `in`/`not_in`.
- **`updated_at` in `dateFilter` (PR #286, `1997b54`, 0.4.3-rc.1).** Real column; no B-tree today, sequential scan fine. Flat date-param deprecation lands here too — bracket-style canonical; planned removal 0.6.0.

### Tag Lifecycle & Schema Cascading (PRs #131, #204, #241, #245, #249, #251, #269, #272, #275)

Tag identity reshapes from a name-only enrolment row into the SSOT for everything *about* a tag — and every reference is made cascade-safe.

- **Atomic tag rename + merge endpoints (PR #131, `1bd38053`).** `POST /api/tags/{name}/rename` rewrites the tag in one transaction. `POST /api/tags/merge` retags every note carrying any source tag onto the target. Retires the prior N+1 PATCH stopgap.
- **Notes-as-config shipped then retired (PR #204, `4797ae44`).** Promoted `_tags/<name>` and `_schemas/<name>` notes as SSOT for tag parents + path-prefix default-schema bindings. Critical reviewer fix: GLOB instead of LIKE (leading underscore in LIKE was a wildcard). The convention that #245 (single-row tag identity) and #249 (note_schemas table) immediately migrated away from into first-class tables — convention shipped and started retiring inside ~5 days.
- **Tag-scoped tokens Phase 1 (PR #241, `2d54a2ee`, schema v13).** `tokens.scoped_tags TEXT NULL`. A `pvt_*` token can carry an immutable root-tag allowlist. Out-of-scope reads return 404 (no existence leak). Hub-issued JWTs always carry `scoped_tags: null`. Use case: per-purpose bots slicing one vault.
- **Tag identity reshape (PR #245, `71af0367`, schema v14).** Six new columns on `tags`: `description`, `fields` (JSON array), `relationships` (JSON object, cardinality vocabulary `"one"|"optional"|"many"|"many-required"`), `parent_names`, `created_at`, `updated_at`. Hierarchy resolver swaps from notes-as-config to `tags.parent_names`. `tag_schemas` sidecar drops; rows fold into `tags`. Legacy `_tags/*` notes left as inert audit trail.
- **`_schemas/*` table form (PR #249, `98b7d049`, schema v15).** `note_schemas` + `schema_mappings` tables. Six new MCP tools (`list-note-schemas`, etc.). Tool count 10 → 16.
- **v14 transaction wrap (PR #251, `7b92d4c5`).** vault#248. Body wrapped in `BEGIN IMMEDIATE / COMMIT` so a crash mid-migration leaves DB in either pre-v14 or post-v14 state.
- **Tag schema inheritance + `_default` (PR #272, `fc8db55b`, 0.4.1-rc.2).** `parent_names` drives schema inheritance: child's effective `fields` = its own ∪ all ancestors'. `_default` implicit universal parent. **First-in-walk wins**; losers surface as `schema_conflict` advisory warnings. Reviewer-fold: `tagMatch: "any"` + `_default` drops the tag filter; `searchNotes` honors `_default` filter-strip.
- **`note_schemas`+`schema_mappings` retire (PR #269, `f7c47f17`, schema v17, 0.4.1-rc.1).** Audit revealed zero rows in real vaults. Schema v17 drops both tables; six MCP tools retire; `/api/note-schemas` REST endpoints removed. **MCP tool count drops 16 → 9**. `synthesize-notes` retires alongside under vault#268.
- **Tag rename cascade (PR #275, `5a278cc0`, 0.4.1-rc.4).** `renameTag(old, new)` rewrites every surface in one `BEGIN IMMEDIATE` transaction: tags PK + sub-tag rows; `note_tags.tag_name`; `tags.parent_names`; `tokens.scoped_tags` (replaces fail-closed 409 stopgap); `indexed_fields.declarer_tags`; note body refs; `_tags/<oldname>` config-note paths. **Breaking** for callers relying on 409. LIKE wildcards (`%`, `_`) inside tag names escaped at every pre-filter site — tag named `task_` was producing `LIKE 'task_%'` matching `taskX`.

### Transcription Integration (PRs #132, #133, #156, #158, #159)

- **Server-side transcription on attachment upload (PR #132, `be8d34ec`).** `POST /api/notes/{id}/attachments {transcribe: true}` stamps `transcribe_status: "pending"` and `transcribe_stub: true`. Background worker (enabled by `SCRIBE_URL`) drains queue FIFO, POSTs audio to `${SCRIBE_URL}/v1/audio/transcriptions`. Exponential backoff up to 3 attempts. Queue is the `attachments` table — restart resumes pending work.
- **Audio retention API (PR #133, `8e145d69`).** `config.audio_retention`: `"keep"` (default), `"until_transcribed"`, `"never"`.
- **Vault is scribe context provider (PR #156, `5340058a`).** Webhook triggers and the dedicated worker share `include_context: [{tag, exclude_tag?, include_metadata?}]`. Only whitelisted `include_metadata` keys surfaced. `SCRIBE_AUTH_TOKEN` canonical; `SCRIBE_TOKEN` deprecated alias for one release.
- **`.env` ordering hotfix (PR #158, `907a9114`).** `SCRIBE_URL` gate ran before `loadEnvFile()` — worker silently stayed off when env was in `~/.parachute/vault/.env` rather than shell.
- **Event-driven transcription (PR #159, `d1e0b3ad`).** `core/src/hooks.ts` grows `attachment:created` event. Generic: any feature can listen.

### Portable Export & Lossless Round-Trip (vault#308; PRs #317, #319)

- **PR 1 — portable-markdown export (PR #317, `f0bd5f9e`, 0.4.4-rc.9).** `core/src/portable-md.ts` canonical home. Fixed top-level frontmatter key order (`id` → `path` → `tags` → `metadata` → `links` → `attachments` → `created_at` → `updated_at`) with alpha-sorted nested objects. Re-exporting unchanged vault produces byte-identical files. Hand-rolled YAML emitter with strict quoting for type-ambiguous values. Legacy `core/src/obsidian.ts` becomes back-compat shim.
- **PR 1 review fold (0.4.4-rc.10).** F1 (silent corruption): multi-line metadata strings truncated by single-quoted YAML — `needsQuote` detects control chars, switches to double-quoted with escape sequences. F2 (tautology test): rc.9's "byte-identical re-emit" called `toPortableMarkdown` twice on same in-memory object; fixed to parse emitted markdown back, reconstruct, re-emit, compare bytes. F3 (path traversal): `exportVaultToDir` joined without verifying resolved path under `outDir`; now refuses with `console.warn`.
- **PR 2 — attachments + import + round-trip (PR #319, `c71b02df`, 0.4.4-rc.11).** `importPortableVault` upserts by frontmatter `id`. `--blow-away` wipes target first then replays (confirm defaults NO). Attachment binaries: `.parachute/attachments/<id>/<basename>`; path-traversal guards both ends. `Store.restoreNoteTimestamps` import-only setter. Round-trip byte-equivalent integration test pins the load-bearing invariant.
- **Known limitation: attachment IDs re-minted on import.** Frontmatter refs resolve by `(note_id, path)` — note-level round-trip unbroken, but full round-trip with attachments produces byte-different `attachments[].id`. Future enhancement.

### Non-Markdown Content as First-Class (vault#328; PR #329)

- **Schema v17 → v18 (PR #329, `7acdf6ac`, 0.4.5-rc.1).** `ALTER TABLE notes ADD COLUMN extension TEXT NOT NULL DEFAULT 'md'`; uniqueness index widens from `(path)` to `(path, extension)`. Backward-compat by construction.
- **API surface.** MCP and REST create/update/query all gain symmetric `extension` field. Validation `/^[a-z0-9]{1,16}$/` + reserved `parachute` prefix guard.
- **Export/import.** `supportsInlineFrontmatter(ext)` splits extensions: frontmatter-compatible (`md`, `mdx`) → metadata inline; sidecar-required → metadata in `.parachute/notes-meta/<note-id>.yaml`. Import builds `(path, extension) → sidecar` index, walks every content file. Frontmatter `extension` OMITTED for `md` (default) so pre-vault#328 markdown-only exports produce byte-identical bytes before/after upgrade.
- **Wikilink ambiguity.** `[[Foo]]` refused when ambiguous; `[[Foo.md]]`/`[[Foo.csv]]` resolve unambiguously.

### Case-Insensitive Filesystem Disambiguation (vault#327, vault#330; PR #331)

On macOS APFS and Windows NTFS, notes whose paths differ only by case silently collide on export. Aaron's real default vault hit this.

- **Export detection (PR #331, `7bdb75e5`, 0.4.5-rc.2).** `probeCaseSensitive` writes a hidden tempfile, tests case-sensitivity. Defaults conservative `true` on probe failure. On case-insensitive FS, collisions auto-disambiguate to `<path>__<id-prefix>.<ext>` (deterministic across runs). Stored `path` stays canonical; only on-disk filename munged.
- **API (vault#330 S1).** New `AmbiguousPathError` (distinct from `PathConflictError`) carries `candidates: [{id, extension}, ...]`. `getNoteByPath(path, extension?)` throws when >1 row with no hint. REST 409 with `error_type=ambiguous_path`.
- **Import (vault#330 S2).** Orphaned sidecars land in `ImportStats.skipped_sidecars`. Multi-value `Map<key, sidecar[]>` so case-collided sidecars coexist. Three-tier fallback: exact-case → first remaining bucket → id-prefix.

### Response Shape Flexibility & Self-Orientation (PRs #273, #280, #286, #307)

- **Lean response (PR #286, `1997b54`, 0.4.3-rc.1).** `update-note include_content: false` returns `NoteIndex` (drops `content`, keeps `byteSize`, `preview`, `validation_status`).
- **Validation status on HTTP (PR #307, `d0e685f1`, 0.4.4-rc.8).** HTTP `POST`/`PATCH /notes` attach `validation_status` to responses (single + batch). Mirrors MCP contract.
- **`vault-info` projection (PR #273, `4ca781f3`, 0.4.1-rc.3).** Comprehensive description: schema-bearing tags with `effective_fields`/`effective_parents`, `indexed_fields` catalog, `query_hints` array. MCP `initialize` carries markdown projection. Token budget verified under ~5K at 50 schema-bearing tags.
- **Stats line distinction (PR #280, `8173ade0`).** `100 tags` → `100 tags total, 5 with schemas`.

### Import Reliability & Empty-Note Handling (PRs #235, #324)

- **Empty-note + 500-cap batches guard (PR #235, `d363b2b7`).** Empty-note invariant enforced at Store boundary. Three legit shapes accepted (content-only, path-only, both); only empty+empty rejected. POST batches now 413 over 500 items.
- **Empty-note guard dropped (PR #324, `a1a2019c`, 0.4.4-rc.14).** Aaron's real default vault tripped on empty-content rows during round-trip import smoke. Skeletons/drafts/organizing notes are valid state. Dropped `EmptyNoteError` class. Batch atomicity + `MAX_BATCH_SIZE` untouched. **Net of #235 + #324: cap remains; empty-note rejection rolled back.**
- **Daemon detection on import (vault#323, PR #324).** Import opens its own bun:sqlite connection. `cmdImport` probes `checkHealth(port)` after vault verification; healthy/unhealthy prints clear error pointing at `parachute stop vault`, exits 1. Proper WAL is a separate follow-up.

### Admin SPA — Scaffold + Per-Vault Mount (PRs #219, #220, #222, #252, #254, #255, #256)

- **Scaffold + Phases A/B/C (PRs #219, #220, #222).** Vite + React + TypeScript SPA at `/admin/`. Reads hub-issued `vault:<name>:admin` JWT from URL fragment, stashes module-scoped, strips visible URL. `lib/scope.ts` client-side JWT payload decode. Mint one-time plaintext `pvt_*` exactly once; hide mutate UI from read-only tokens. Forward-pointing Permissions link to hub.
- **Per-vault mount (PR #252, `bb0abab0`).** Three layers in lockstep — server static-file dispatch, React Router runtime basename, Vite asset-base — so the same compiled bundle works at any per-vault mount without rebuild. Mount regex `/^\/vault\/([^/]+)\/admin(?=\/|$)/`. Bare `/vault/<name>/admin` redirects to `/vault/<name>/admin/` (301).
- **Mount-mode route table (PR #254).** Switch on mount mode instead of `<Navigate>` (was resolving to doubled `/vault/<name>/admin/vault/<name>`).
- **JWT fragment preservation (PR #255).** Trailing slash on `module.json`'s `managementUrl` so hub-issued JWT fragments (`#token=…`) survive the click-through.
- **Stats wire-shape alignment (PR #256).** SPA `VaultStats` interface used short field names not present in wire payload. Aligned; `attachmentCount` added server-side.

### Optimistic Concurrency & Correctness (PRs #137, #153, #260, #262)

- **`updated_at = created_at` on insert + backfill (PR #137, schema v11).** Clients using `updatedAt ?? createdAt` were 409'd on first edit.
- **Safe-by-default `update-note` (PR #153).** Requires `if_updated_at` or `force: true`. MCP returns `InvalidParams` with `error_type: "precondition_required"`; REST 428.
- **Batch atomicity (PR #260, `04d0c3ce`).** Three public batch entry points wrap loops in `BEGIN`/`COMMIT`/`ROLLBACK`. Mid-batch failure no longer leaves prefix items written.
- **`.changes` → `RETURNING` (PR #262, `11be1830`).** Inside multi-statement transactions, `Statement.run().changes` could carry stale values, silently bypassing `if_updated_at`. Six sites migrated.

### Services.json & Module Protocol (PRs #135, #140, #143, #147, #148, #188, #207, #209)

- **`init` registers in `~/.parachute/services.json` (PR #135).** Writes `{name, port, paths, health, version}` into shared manifest. Atomic write via temp + rename.
- **services.json `paths[0]` is `/vault/<default_vault>` (PR #140).** Post URL migration, init was still writing `paths: ["/"]`.
- **`/.parachute/info` + `icon.svg` (PR #143).** Two public no-auth CORS-* endpoints. `info` returns `name/displayName/tagline/version/iconUrl`; `icon.svg` placeholder with `X-Content-Type-Options: nosniff`.
- **Module-config endpoints (PR #148).** `src/module-config.ts` builds schema + values: `audio_retention`, `scribe_url` (read-only until Phase 3), `scribe_token` (`writeOnly` — never returned by GET), `port` (informational). `PUT /.parachute/config` returns 405 — explicitly Phase 3.
- **`.parachute/module.json` (PR #188).** Closes vault#175. Ships in package: name, manifestName, displayName, tagline, kind=api, port, paths, health, startCmd, scopes.defines. Companion fix: services-manifest merge upsert preserves hub-stamped `installDir`.
- **`create` re-registers (PR #209).** Multi-vault setups stay in sync.
- **`init --no-autostart` (PR #207).** Closes vault#113. Skips daemon registration.

### MCP-Install Walkthrough & Smart Defaults (PRs #291, #292, #295, #301, #303, #304, #305)

- **Phase A+B (PR #291).** New flag surface: `--mint`/`--token <bearer>`/`--legacy-pat` (mutually exclusive); `--scope`; `--install-scope user|project`; `--vault <name>`; `--client claude-code`.
- **Interactive walkthrough (PR #292).** Bare `mcp-install` (TTY, no flags) walks through vault target, install location, auth mode + scope, preview + confirm. Smart defaults from ambient context.
- **Local install scope + always-prompt (PR #295).** Added `local` (`projects[<absolute-cwd>].mcpServers`). **Breaking**: non-interactive default changed `user` → `local`.
- **Preview-accuracy pin (PR #301).** Extract `buildMcpEntryPlan` as SSOT for `(entryKey, url)`. Both preview and writer call it.
- **Plan close on writer side (PR #305).** `InstallMcpConfigOpts` now requires `url` from caller. `installMcpConfig` is pure file-writer.
- **`uninstall --skip-daemon` (PR #303).** Test-only undocumented flag. Bypasses launchd/systemd/backup-agent uninstall.
- **`bun test` exclusion for `web/ui/` (PR #304).** Root cause: vitest's `vi.mock("path")` single-arg form. `bunfig.toml` adds `pathIgnorePatterns = ["web/ui/**"]`.

### Pre-Launch Polish & Operator UX (PRs #150, #160–#168, #184)

Loopback bind by default + `--scope` flag (#162); auth-model reference doc (#161); README reshape + matrix-summary + password-echo fix (#165); explicit token + MCP prompts (#166); vault-name prompt at init (#168); `--json` flag on create (#184); CLI help reshape (#150); VAULT_BIND display fix (#164).

### Cleanup Bundles (PRs #187, #188, #190, #193, #194, #206)

Five cleanup batches + one 9-nit bundle across 24 hours, bumping rc chain rc.2 to rc.8. The CHANGELOG framed these as nits; substantive items inside:

- **PR #187 (`3ecb84c4`).** Array `aud` handling per RFC 7519; e2e integration test for `authenticateHubJwt` full request path.
- **PR #188 (`e23d9539`).** `.parachute/module.json` ships. services-manifest merge upsert preserves hub-stamped `installDir`.
- **PR #190 (`d0f4c7c1`).** **`query-notes near` SQL WHERE fix** — pre-fix `ORDER BY + LIMIT` against full table silently dropped neighborhoods beyond first N. `GET /auth/status` public unauthenticated discovery.
- **PR #193 (`f84cc959`).** Graceful stop via filesystem sentinel `~/.parachute/vault/stop.signal`. Typed `409 path_conflict`. PDF + mp4 attachment allowlist.
- **PR #194 (`c85ccb90`).** OAuth per-vault rate limiter + memory cap with FIFO eviction; server-side OAuth scope binding per RFC 6749 §3.3.
- **PR #206 (`038ade73`).** `/auth/status` rate-limit eligibility; frontmatter-aware prepend; `content_edit` 422 not 404; `isAppendOnly` excludes tags/links.

### Synthesize-Notes Tool (Promoted + Retired) — PRs #198, #269

`synthesize-notes` MCP tool shipped in PR #198 (`360170e9`) — graph-aware neighborhood for an agent — and retired in PR #269 (0.4.1-rc.1) when audit revealed zero production invocations. Replicable with `query-notes(near={note_id, depth: 2})` + `find-path` + agent aggregation. Net for an upgrader: never in v0.2.4, not in v0.4.5.

## Breaking changes for 0.2.4 operators

Sourced to PR # / commit.

| Issue | Version | PR | Change | Action Required |
|-------|---------|-------------|--------|-----------------|
| URL migration | 0.3.6-rc.1 | #138 | Every vault-touching route → `/vault/<name>/...`. Old URLs 404. Unified cross-vault MCP endpoint + `list-vaults` MCP tool retired. | Claude Code: run `parachute-vault mcp-install`. Other OAuth clients re-handshake. curl/scripts: rewrite URLs. Permalinks: `/view/<id>` → `/vault/<name>/view/<id>`. Tokens keep working. |
| CLI rename | 0.3.6-rc.1 | #134 | `parachute` → `parachute-vault`. | Update shell aliases / shebangs / CI / README refs. Dispatcher and CLI's arg-parser accept `parachute vault <cmd>` forward — wrappers keep working. |
| Filesystem restructure | 0.3.6-rc.1 | #142 + #144 | Vault state → `~/.parachute/vault/`; `vault/vaults/<name>/` → `vault/data/<name>/`; logs → `vault/logs/`. | Auto-migrating, idempotent, target-wins. EXDEV failures surface a hint. Update backup scripts pointing at old paths. |
| Bind change | 0.3.6-rc.1 | #162 | Server bound 0.0.0.0 → 127.0.0.1. | Set `VAULT_BIND=0.0.0.0` if topology relies on wide bind (Docker bridge, LAN). |
| Scope enforcement | 0.3.6-rc.1 | #154 | `vault:read`/`write`/`admin` enforced at HTTP + MCP. `tokens create --read` is now enforcement-real. | Audit `--read` callers writing. Pre-v12 NULL-scope rows fall back to legacy permission for one release. |
| Hub JWT scopes + audience | 0.3.6-rc.2 | #180 | Hub JWT rejects broad `vault:<verb>` scopes. Audience: hardcoded `"hub"` → per-vault `aud: vault.<name>`. Cross-vault routes reject hub JWTs. | Scripted JWT minting must narrow to `vault:<name>:<verb>`. Old `aud: "hub"` validates during rolling-update window. |
| Priv-esc fix | 0.4.0 chain | #233 | Global `config.yaml` `scope: read` rows previously silently inflated to full access. Now correctly resolve to read-only. | Audit `~/.parachute/vault/config.yaml` for `scope: read` rows; impact scan locally found zero affected. |
| Cross-vault tokens | 0.3.6-rc.39 | #258 | `pvt_*` tokens bind to minting vault (schema v16). Cross-vault use rejected 403. | Pre-v16 NULL-bound tokens authenticate server-wide (legacy compat). New mints default vault-bound; `tokens create --all` opts back into server-wide. |
| Optimistic concurrency | 0.3.6-rc.1 | #153 | `update-note` requires `if_updated_at` or explicit `force: true`. | Either supply the conditional (now returned by `query-notes` and `create-note`) or pass `force: true`. |
| Empty-note rejection + reversal | 0.3.6-rc.x → 0.4.4-rc.14 | #235, #324 | #235 rejected empty content+empty path notes + capped batches at 500. #324 reversed the empty-note rejection. | The 500-cap stays. Empty-note rejection rolled back; callers don't need to special-case `{}` anymore. |
| `note_schemas` family + `synthesize-notes` retire | 0.4.2 | #269 | `note_schemas` + `schema_mappings` tables + six MCP tools + `/api/note-schemas` REST endpoints removed. `synthesize-notes` MCP tool removed. | Migrate retired-tool callers to `list-tags`/`update-tag` with `fields`. Schema v17 migration is automatic. |
| Tag rename cascade | 0.4.2 | #275 | Tag rename returns 200 with cascade stats (was 409 `tag_in_use_by_tokens` stopgap). | Callers expecting 409 must adapt. Token rewrite is automatic. |
| Hub-mint default | 0.4.4-rc.1 | #291 | Hub-mint replaces vault-minted `pvt_*` as `mcp-install` default. `--legacy-pat` falls back with deprecation. | Fresh installs default `--mint`. Self-hosted-without-hub: pass `--legacy-pat`. |
| Install scope default | 0.4.4-rc.3 | #295 | Non-interactive `mcp-install` default `user` → `local`. Interactive walkthrough always prompts. | Scripted installs add `--install-scope user` for prior behavior. `local` default prints a consequence callout. |
| Portable-md format change | 0.4.4-rc.9 | #317 | Export shape changed from flat Obsidian to nested `metadata:` block with fixed key order. `toObsidianMarkdown` still available. | No operator action — export is projection. Re-run `export` if you store output. |
| `if_missing` parameter | 0.4.4-rc.12 | #320 | `update-note if_missing` parameter; default `"fail"`. Response carries new `created: boolean`. | None required — defaults preserve semantics. Sync consumers must accept the additive `created` field. |
| File extension uniqueness | 0.4.5 | #329 | Path uniqueness `(path)` → `(path, extension)`. Wikilink ambiguity requires explicit extension. | Auto-migrate (schema v18). Manual CSV/YAML/JSON: supply `extension`. Wikilinks to ambiguous bare paths return unresolved. |
| AmbiguousPathError | 0.4.5-rc.2 | #331 | New error distinct from `PathConflictError`. `getNoteByPath(path, extension?)` throws when >1 row with no hint. REST 409 with `error_type: "ambiguous_path"`. | Callers fetching by path may need to handle the new error shape on case-collision or extension-collision vaults. |

## New CLI commands & surface area

### CLI

| Command/Parameter | Version | PR | Description |
|---|---|---|---|
| `parachute-vault <cmd>` | 0.3.6-rc.1 | #134 | **Binary renamed** from `parachute`. All subcommands carry over. Dispatcher and CLI arg-parser both accept `parachute vault <cmd>` as a forward. |
| `parachute-vault stop` | 0.3.6-rc.x | #193 | Graceful shutdown via filesystem sentinel `~/.parachute/vault/stop.signal`, polled every 500ms. |
| `parachute-vault export <dir> [--since <iso>]` | 0.4.4-rc.9 | #317 | Portable-markdown export. Byte-identical re-export. `--since` for incremental. |
| `parachute-vault import <dir> [--blow-away] [--yes] [--dry-run]` | 0.4.4-rc.11 / rc.14 | #319, #324 | Auto-detects portable-md vs legacy Obsidian. `--blow-away` wipes before replay. Daemon-busy detection probes `checkHealth(port)`. |
| `parachute-vault create --json` | 0.3.6-rc.3 | #184 | Single-line JSON `{name, token, paths, set_as_default}` for orchestrator integration. |
| `parachute-vault init` flags: `--vault-name`, `--no-autostart`, `--mcp`/`--no-mcp`, `--token`/`--no-token` | 0.3.2–0.4.0 | #168, #207, #160, #166 | Non-interactive overrides for first-run prompts. |
| `parachute-vault mcp-install` (interactive walkthrough) | 0.4.4-rc.2 | #292 | TTY walkthrough: vault target, install location, auth mode + scope, preview + confirm. |
| `parachute-vault mcp-install` flags: `--mint` / `--token <bearer>` / `--legacy-pat`; `--scope`; `--install-scope user\|local\|project`; `--vault <name>`; `--client claude-code` | 0.4.4-rc.1 / rc.3 | #291, #295 | Hub-mint default. Per-vault entry key `parachute-vault-<name>`. Default `--install-scope` changed `user` → `local`. |
| `parachute-vault tokens create --scope vault:read\|write\|admin` | 0.3.0 | #162 | Comma-separated or repeated. Precedence `--scope` > `--read` > `--permission` > default. |
| `parachute-vault tokens create --vault <name>\|--all`, `tokens list --vault <name>` | 0.3.6-rc.39 | #258 | Per-vault binding (default); `--all` opts in to server-wide. |
| `parachute-vault uninstall --skip-daemon` | 0.4.4-rc.5 | #303 | Test-only undocumented flag. |
| `VAULT_BIND` env | 0.3.0 | #162 | Override 127.0.0.1 default bind. |

### MCP & REST surface

| Surface | Version | PR | Description |
|---|---|---|---|
| `update-tag fields.<name>.indexed: true` / `.type: "integer"` / `.parent_names` / `.relationships` | 0.3.6-rc.1, rc.31; 0.4.4-rc.12 | #136, #245, #320 | Indexed: VIRTUAL `meta_<field>` + B-tree index. Type integer: accepts `5`/`5.0`. Hierarchy + typed-link declarations. |
| `update-note` ops: `append`/`prepend`/`content_edit`/`if_updated_at`/`force`/`if_missing`/`include_content` | 0.3.6-rc.1 → 0.4.4-rc.12 | #200, #153, #320, #286 | SQL-atomic append/prepend; content_edit with multi-match guard; safe-by-default optimistic concurrency; upsert with `created` response; lean `NoteIndex` when `include_content: false`. |
| `query-notes metadata: {field: {op: value}}` / `order_by` / `has_tags` / `has_links` / aliases / `date_filter` / `near` SQL fix | 0.3.6-rc.1 → 0.4.0 chain | #141, #139, #224, #230, #190 | Full operator set; sort + presence filters; camelCase/singular alias acceptance; generalized `date_filter`; near pushed into SQL WHERE. |
| `create-note`/`update-note`/`query-notes`/`POST /notes`/`PATCH /notes/:id`/`GET /notes`: `extension` field | 0.4.5-rc.1 | #329 | Optional. Validation `/^[a-z0-9]{1,16}$/`. Query accepts single or array, case-insensitive. |
| MCP tool count: 10 → 16 → 9 | 0.3.6-rc.32 / 0.4.1-rc.1 | #249, #269 | Six tools added schema v15 (note_schemas family); all six retired schema v17 alongside `synthesize-notes`. End state: 9 tools. |
| REST `POST /api/tags/{name}/rename`, `/tags/merge` | 0.3.6-rc.1 | #131 | Atomic. Rename returns 200 with cascade stats post-#275. |
| REST `DELETE /api/notes/:id/attachments/:attId` | 0.2.4 tail | #128 | Scoped delete; unlinks file when no other row references path. |
| REST `POST /api/notes/{id}/attachments {transcribe: true}` | 0.3.6-rc.1 | #132, #159 | Server-side transcription queue. Event-driven via `attachment:created`. |
| REST `GET /api/notes?meta[field][op]=value` / `?extension=...` | 0.4.3-rc.2 / 0.4.5-rc.1 | #289, #329 | Bracket-style metadata filter (full op set); extension filter (single, array, comma, repeated). |
| REST `PATCH /notes/:id` (`include_content: false`, `if_missing`, `validation_status`) | 0.4.3-rc.1 → 0.4.4-rc.12 | #286, #320, #307 | Lean response shape; upsert with `created`; validation status mirrored from MCP. |
| REST `POST/GET/DELETE /vault/<name>/tokens` (+ `{tags: [...]}`) | 0.3.6-rc.x / rc.30 | #205, #241 | Token mint/list/revoke with hub-JWT `vault:<name>:admin` auth. Tag-scope allowlist (root tags only, subset of caller's). |
| REST `GET /auth/status` | 0.3.6-rc.x | #190, #206 | Public unauthenticated discovery. Boolean-only token presence. |
| REST `PATCH /api/vault {audio_retention}` | 0.3.6-rc.1 | #133 | Mutable: `"keep"`, `"until_transcribed"`, `"never"`. |
| REST `GET /.parachute/{info,icon.svg,config,config/schema}` | 0.3.6-rc.1 | #143, #148 | Module protocol surface. `info` locked card shape with `kind: "api"`. |
| `.parachute/module.json` (ships in package) | 0.3.6-rc.x | #188 | Vendored manifest for hub's `FIRST_PARTY_FALLBACKS` registry. |
| OAuth services catalog + rate-limiter + scope binding | 0.3.6-rc.1 / rc.x | #147, #194 | Token endpoint includes `services` catalog. Per-vault rate limit + FIFO eviction. Server-side scope binding per RFC 6749 §3.3. |
| Env `PARACHUTE_HUB_ORIGIN`, `SCRIBE_AUTH_TOKEN`, `SCRIBE_URL` | 0.3.6-rc.1 | #147, #156 | Hub OAuth advertisement + JWT issuer validation; scribe bearer + worker enablement. |
| Event bus: `attachment:created` hook | 0.3.6-rc.1 | #159 | Generic event alongside note `created`/`updated`. |
| PDF + MP4 attachment allowlist | 0.3.6-rc.x | #193 | Added to allowlist. SVG/HTML still excluded. |
| Typed `409 path_conflict` on create/rename | 0.3.6-rc.x | #193 | `error_type: "path_conflict"`. |
| `vault-info` projection | 0.4.1-rc.3 | #273 | Schema-bearing tag records + indexed_fields + query_hints. |
| Admin SPA at `/vault/<name>/admin/*` | 0.4.0 | #219, #220, #222, #252–#256 | Per-vault dashboard. Hub-proxied. Three-layer mount. |

## Work still in flight

- **Phase 3 module config write path.** `PUT /vault/<name>/.parachute/config` returns 405; Phase 3 gates by `vault:admin` to let hub write settings without operator shell.
- **Attachment ID restoration.** `addAttachment` mints fresh ids on import; `Store` doesn't yet expose `restoreAttachment(id, ...)`. Frontmatter refs resolve by `(note_id, path)` so note-level round-trip unbroken.
- **Concurrent-writer & WAL.** Import detects daemon-on-write-lock and exits cleanly; single-writer SQLite contention deferred.
- **Cross-client MCP support (Phase C).** Only `claude-code` wired. Cursor, Claude Desktop, Codex, Zed, Goose, Cline + client auto-detection deferred.
- **Tunable preview length, URL-safe slug, OR in metadata filters, section/diff/line-range edits, streaming exporter for >1M-note vaults, path-prefix-mapped schemas.** Deferred until a real consumer hits a wall.
- **Flat date-param deprecation (vault#288).** Functional through 0.5.x; planned removal 0.6.0.
- **`pvt_*` deprecation (vault#212 Phase 6).** Opaque-token path remains for self-hosted-without-hub.
- **Hub multi-user UX & dashboard SDK.** In-flight on the hub team. Vault's token/scope machinery is forward-compatible.
- **`updated_at` indexing.** No B-tree today; sequential scan fine for current sizes.

## What the CHANGELOG missed

The CHANGELOG narrates `0.3.6-rc.1` and `0.3.6-rc.30` through `rc.39` explicitly; **`0.3.6-rc.2` through `0.3.6-rc.29` are missing**. That's a 28-RC window spanning 2026-04-26 → 2026-05-03 — eight days during which 13 PRs landed. None are in any CHANGELOG version entry. Below, per PR, for audit completeness:

- **PR #172** — Hub JWT dual-validation. Actual rc.1; CHANGELOG conflates rc.1 with the larger ecosystem-fit cluster.
- **PR #179** — Vault config + scope semantics design doc. Five open questions resolved.
- **PR #180** — Narrowed scopes + per-vault audience enforcement. Bumps to rc.2.
- **PR #184** — `create --json` flag. Bumps to rc.3.
- **PRs #187/#188/#190/#193/#194** — Cleanup batches 1–5. Substantive items: `.parachute/module.json` ships, services-manifest hub-field preservation, `query-notes near` SQL WHERE fix (a real bug), `GET /auth/status`, graceful stop sentinel, typed `409 path_conflict`, PDF + mp4 allowlist, OAuth rate limiter, server-side scope binding per RFC 6749 §3.3.
- **PR #198** — `synthesize-notes` MCP tool added; retired 11 days later in #269.
- **PR #200** — `update-note` operations bundle. SQL-atomic append/prepend + `content_edit` + `if_updated_at` baseline. Closes vault#79/#80/#81. Significant new MCP capability.
- **PR #204** — Notes-as-config convention. Shipped → migrated to first-class tables ~5 days later (#245, #249). One-week shelf life.
- **PR #205** — REST endpoints for vault token mint/list/revoke. Surface the admin SPA uses.
- **PR #206** — 9-nit cleanup. `/auth/status` rate-limit eligibility, frontmatter-aware prepend, `content_edit` 422 not 404, `isAppendOnly` excludes tags/links.
- **PRs #207, #209** — `init --no-autostart`; `create` re-registers services.json. Mentioned in 0.4.0 summary; no own version entries.
- **PR #210/#211** — init-as-repair pin + cmdInit stderr.
- **PR #212** — scope-guard library adoption. Step 2 of 4 in cross-ecosystem trust-kernel consolidation.
- **PR #224** — `query-notes` camelCase aliases + store-routing fix. Two distinct bugs.
- **PR #225** — `beforeunload` warning while pvt_* banner showing.
- **PR #230** — Generalized `date_filter`. Unblocks Prism's semantic-date workflow.
- **PR #231** — FTS routing fix. Same class as #224.
- **PR #232** — Canonical `bun run typecheck`. Drops 339 error lines without papering.
- **PR #233** — **Priv-esc fix on `readGlobalConfig`.** CHANGELOG 0.4.0 summary buries this as "smaller fixes worth naming" — undersells a real privilege-escalation bug.
- **PR #235** — Empty-note rejection + 500-cap batches. Reversed in part by #324 11 days later.

## Appendix: schema migrations

The full migration ladder a 0.2.4 vault (schema v9) traverses to reach 0.4.5 (schema v18). Nine migrations. Each idempotent, wrapped in `BEGIN IMMEDIATE`/`COMMIT`/`ROLLBACK` post-#251 (v14 wrap was the subject of vault#248 hardening; v15–v18 follow the same shape).

| Version | Release | PR / Commit | Change | Backward-Compat |
|---------|---------|-------------|--------|-----------------|
| v9 | starting point | — | OAuth codes carry `vault_name`. (At v0.2.4.) | — |
| v10 | 0.3.6-rc.1 | PR #136 / `1971fe55` | `indexed_fields` table as SSOT for indexed metadata fields. `CREATE TABLE IF NOT EXISTS`. No data migration. | Automatic. Fresh vaults pick up via SCHEMA_SQL. |
| v11 | 0.3.6-rc.1 | PR #137 / `917ff6ec` | Backfill `updated_at = created_at` for notes that never received an update. Pre-v11 inserts left `updated_at` NULL. | Automatic. Idempotent. |
| v12 | 0.3.6-rc.1 | PR #154 / `ed08a2dd` | `tokens.scopes TEXT` added. OAuth-standard whitespace-separated scope string. | Automatic. Pre-v12 NULL rows fall back to legacy permission for one release. |
| v13 | 0.3.6-rc.30 | PR #241 / `2d54a2ee` | `tokens.scoped_tags TEXT NULL` added. Tag-scoped tokens — root-tag allowlist. JSON array. | Automatic. Existing rows untouched (= unscoped). |
| v14 | 0.3.6-rc.31 | PR #245 / `71af0367` | Six new columns on `tags` (description, fields, relationships, parent_names, created_at, updated_at). Drop `tag_schemas` sidecar. Hierarchy resolver swaps to `tags.parent_names`. | Automatic. Idempotent. v14 transaction wrap added in 0.3.6-rc.34 (PR #251). |
| v15 | 0.3.6-rc.32 | PR #249 / `98b7d049` | Two new tables: `note_schemas` + `schema_mappings`. Replace `_schemas/*` notes-as-config. | Automatic. Short-circuit fix in 0.3.6-rc.33. |
| v16 | 0.3.6-rc.39 | PR #258 / `9b39758d` | `tokens.vault_name TEXT` + `idx_tokens_vault_name`. Per-vault token storage. | Automatic. Existing rows get NULL (= legacy server-wide); new mints default to vault-bound. |
| v17 | 0.4.1-rc.1 | PR #269 / `f7c47f17` | Drop `note_schemas` + `schema_mappings` tables. Six MCP tools retire. `synthesize-notes` removed. `tags.fields` is sole schema surface. | Automatic. Logs warning naming any dropped schemas/mappings (zero in real vaults). |
| v18 | 0.4.5-rc.1 | PR #329 / `7acdf6ac` | `ALTER TABLE notes ADD COLUMN extension TEXT NOT NULL DEFAULT 'md'`. Widen uniqueness index from `(path)` to `(path, extension)`. | Automatic. All existing rows default to `md`. |

---

*Compiled 2026-05-16 from primary sources: git log (106 non-merge commits `752367b`/v0.2.4 → `66ddd70`/main), 87 merged PRs, CHANGELOG cross-referenced against both.*

</div>
</details>

</main>
