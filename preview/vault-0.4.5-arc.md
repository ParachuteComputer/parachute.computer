---
layout: base.njk
title: "Vault 0.2.4 → 0.4.5 — Architectural arc & migration guide (preview)"
description: "Synthesis of what shipped in Parachute Vault between launch (0.2.4, 2026-04-23) and the 0.4.5 stable on 2026-05-15: portable export, file-extension support, upsert semantics, hub-minted auth, case-insensitive filesystem disambiguation, schema inheritance maturity, and the operator migration path."
permalink: /preview/vault-0.4.5-arc/
eleventyExcludeFromCollections: true
---
<style>
/* Preview-page typography — leans on .post-content but adds tables + suppresses
   the drop-cap on the preview-notice. */
.preview-notice {
    max-width: var(--content-width);
    margin: 2.5rem auto 3.5rem;
    padding: 1.1rem 1.4rem;
    border: 1px solid var(--border);
    border-left: 3px solid var(--accent);
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.6);
    font-size: 0.93rem;
    line-height: 1.65;
    color: var(--fg-muted);
}
.preview-notice strong {
    color: var(--accent);
    font-family: var(--mono);
    font-size: 0.74rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    display: inline-block;
    margin-right: 0.5rem;
    vertical-align: 0.05em;
}
.preview-hero {
    max-width: var(--content-width);
    margin: 4rem auto 0;
    text-align: left;
}
.preview-hero h1 {
    font-family: var(--serif);
    font-size: clamp(2rem, 3.2vw, 2.6rem);
    font-weight: 400;
    letter-spacing: -0.02em;
    line-height: 1.15;
    color: var(--fg);
    margin-bottom: 0.5rem;
}
.preview-hero p.preview-subhead {
    color: var(--fg-muted);
    font-family: var(--mono);
    font-size: 0.78rem;
    letter-spacing: 0.04em;
    text-transform: uppercase;
}
/* Suppress drop-cap on the synthesis body (it's a doc, not a blog post). */
.post-content > p:first-of-type::first-letter {
    font: inherit;
    color: inherit;
    float: none;
    padding: 0;
    font-size: inherit;
    line-height: inherit;
}
/* Tables — the synthesis has four of them; .post-content doesn't style tables. */
.post-content table {
    width: 100%;
    border-collapse: collapse;
    margin: 1.75rem 0 2rem;
    font-size: 0.92rem;
    line-height: 1.55;
}
.post-content th,
.post-content td {
    border-bottom: 1px solid var(--border);
    padding: 0.65rem 0.85rem;
    text-align: left;
    vertical-align: top;
    color: var(--fg);
}
.post-content th {
    font-family: var(--mono);
    font-size: 0.74rem;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--fg-muted);
    font-weight: 500;
    border-bottom: 1px solid var(--fg-dim);
    background: rgba(243, 240, 234, 0.5);
}
.post-content td code {
    font-size: 0.84em;
    padding: 0.08em 0.32em;
    background: var(--bg-soft);
    border-radius: 4px;
    color: var(--fg);
}
/* Inline code outside tables — slightly stronger than the bare default. */
.post-content p code,
.post-content li code {
    background: var(--bg-soft);
    padding: 0.08em 0.32em;
    border-radius: 4px;
    font-size: 0.87em;
    color: var(--fg);
}
/* Section heading anchor: make h2/h3 anchorable by giving them generated IDs.
   11ty by default emits markdown headings without ID; we rely on visitors
   to ⌘+click a heading and copy the URL. Skip the in-page-anchor library
   for now — keep the page lean. */
</style>

<main>
    <header class="preview-hero fade-up fade-up-1">
        <p class="preview-subhead">Preview · Parachute Vault</p>
        <h1>Vault 0.2.4 → 0.4.5</h1>
        <p class="preview-subhead">Architectural arc &amp; migration guide</p>
    </header>

    <aside class="preview-notice fade-up fade-up-2">
        <p><strong>Preview draft</strong> Not yet linked from anywhere on the public site. If you got here via a direct link, your feedback is welcome &mdash; reach out to the team however you usually do. A final published version is on its way.</p>
    </aside>

    <div class="post-content fade-up fade-up-3">

## § 1. The Arc

Between 0.2.4 (launch, 2026-04-23) and 0.4.5 (stable, 2026-05-15), Parachute Vault moved from a working prototype to a substrate-grade platform. The arc was substrate-first: lossless portable export (vault#308, with sidecar-based metadata for non-markdown content), schema inheritance maturity (vault#270, parent tag resolution + conflict warnings), and strict multi-writer auth semantics (vault#212 Phase 4 with hub-revocation enforcement). Concurrently, file-format support expanded beyond markdown (vault#328: CSV, YAML, JSON, MDX all as first-class, with schema-aware round-trip guarantees). Single-writer sync ergonomics completed the cycle (vault#309–321: upsert semantics, JSON type coercion, link-apply symmetry). The stable 0.4.5 release marked a 22-day sprint of primarily *maturation*—closing the lossy-export gap, disambiguating path resolution under case-insensitive filesystems, and validating the entire platform against a 2296-note real-world vault with zero silent loss.

## § 2. Themed Changes

### Theme: Portable Export & Lossless Round-Trip (Vault#308)

Users gain the ability to version control their vault as git-tracked markdown—notes, schemas, relationships all survive export/import without loss of IDs, metadata, or attachment binaries. `parachute-vault export <dir>` now writes a portable-markdown format with `.parachute/vault.yaml` marker, per-tag schema files, and note-level frontmatter that round-trips byte-identically when unchanged. `parachute-vault import <dir> --blow-away` replays exported vaults into a clean target. Export-side attachment handling copies binaries into `.parachute/attachments/<id>/<name>`; import restores them to `<assetsDir>` with path-traversal guards. The invariant is pinned in integration tests: vault → export → blow-away-import → re-export produces byte-identical files.

- **PR 1 (0.4.4-rc.9, vault#308)**: Portable-markdown export with fixed frontmatter key order (id → path → tags → metadata → links → attachments → created_at → updated_at), alpha-sorted nested objects, hand-rolled YAML quoting for type-safety.
- **PR 1 follow-up (0.4.4-rc.10, vault#317)**: Fixed silent corruption on multi-line metadata (quoting logic for `\n\r\t`), tautology in idempotency test (parse → re-emit, not in-memory twice), and path-traversal gate.
- **PR 2 (0.4.4-rc.11, vault#308 + vault#318)**: Attachment export/import, `--blow-away` disaster-recovery wipe-and-replay, schema + typed-link restoration, `Store.restoreNoteTimestamps` for historical timestamp preservation.

### Theme: Non-Markdown Content as First-Class (Vault#328)

Vaults can now contain CSV, YAML, JSON, MDX, .txt, and custom-extension notes alongside markdown. Each note carries an `extension` field (default `md` for backward-compat). Frontmatter-compatible formats (`.md`, `.mdx`) embed metadata inline; sidecar-required formats (everything else) store metadata in `.parachute/notes-meta/<id>.yaml` with path-traversal guards. Path uniqueness is now `(path, extension)` so `Recipes/pasta.md` and `Recipes/pasta.csv` coexist. Wikilink ambiguity is resolved by explicit extension: `[[Foo.md]]` vs `[[Foo.csv]]`; bare `[[Foo]]` is refused when ambiguous.

- **DB schema (0.4.5-rc.1, vault#328)**: Schema v17 → v18, `ALTER TABLE notes ADD COLUMN extension TEXT NOT NULL DEFAULT 'md'`, widened uniqueness index to `(path, extension)` for multi-format support.
- **API surface (0.4.5-rc.1, vault#328)**: MCP `create-note`, `update-note`, `query-notes` all gain optional `extension` field. REST `POST /notes` and `PATCH /notes/:id` gain symmetric field + validation (`/^[a-z0-9]{1,16}$/`, reserved `parachute` prefix guard). REST `GET /notes` accepts `?extension=csv&extension=yaml` (single or array).
- **Export/import (0.4.5-rc.1, vault#328)**: `toPortableMarkdown` and `toSidecarYaml` both extension-aware. Import walks all content files (not just `.md`), parses inline frontmatter or looks up sidecars, skips orphaned files with warnings.

### Theme: Case-Insensitive Filesystem Support & Disambiguation (Vault#327)

On macOS APFS and Windows NTFS, notes whose paths differ only by case (e.g. `Foo` vs `foo`) would silently collide into one file. The fix probes filesystem case-sensitivity at export time; on case-insensitive disks, colliding notes get on-disk filename suffixes (`<path>__<id-prefix>.<ext>`) while canonical paths in frontmatter stay unchanged. Import recovers truth from frontmatter via three-tier fallback: exact-case match → first remaining bucket → id-prefix. Sidecars are now multi-value `Map<key, sidecar[]>` so case-collided sidecars coexist.

- **Export detection (0.4.5-rc.2, vault#327)**: `probeCaseSensitive` writes a tempfile with lowercase name, tests uppercase reachability, cleans up. Defaults to conservative `true` on probe failure. Builds lowercased index during export walk; collisions auto-disambiguate deterministically.
- **API (0.4.5-rc.2, vault#330 S1)**: New `AmbiguousPathError` (distinct from `PathConflictError`), carries `candidates` array listing `(path, extension)` pairs. REST returns 409 with `error_type: "ambiguous_path"`. `getNoteByPath(path, extension?)` throws when >1 row and no extension hint.
- **Import (0.4.5-rc.2, vault#330 S2)**: Orphaned sidecars (sidecar present, content file missing) land in `ImportStats.skipped_sidecars` with `console.warn` per entry.

### Theme: Upsert Semantics & Sync Ergonomics (Vault#309, Vault#321)

Previously, syncing external systems (like Gitcoin) had to query-then-create on 404, adding latency. `update-note` now accepts `if_missing: "fail" | "create"` (default `"fail"`, preserving current behavior). On `"create"`, treat the update payload as a create payload. Response carries `created: true|false` so sync loops know which path fired without a second query. This is idempotent: repeated calls with the same id + payload produce the same state.

- **Upsert (0.4.4-rc.12, vault#309)**: `update-note if_missing: "create"` on MCP + REST PATCH. ID-vs-path heuristic: if id looks path-shaped and path isn't set, use id as path (matches Gitcoin's `Inbox/2026-05-13-meeting` canonical keys). Response `created` field on both branches. Schema defaults + validation_status fire on create branch.
- **Link consistency (0.4.4-rc.13, vault#321 F2)**: REST PATCH `if_missing=create` now applies `links.add` (was missing); mirrors MCP exactly.
- **Schema conflict testing (0.4.4-rc.13, vault#321 F3/F4)**: New tests pin `schema_conflict` warning on both MCP and REST when two tags declare the same field with conflicting types; first-tag-wins precedence.

### Theme: Schema Validation Maturity (Vault#310, Vault#286)

JSON type coercion and constraint validation hardened. Integer-typed fields now accept both `5` and `5.0` (zero fractional). HTTP bracket-style metadata filters (`?meta[field][op]=value`) expose the engine's full operator set (`eq`, `ne`, `gt`, `gte`, `lt`, `lte`, `in`, `not_in`, `exists`). `dateFilter` recognizes `updated_at` alongside `created_at`, unblocking incremental-rebuild workflows. Tag schema inheritance (vault#270) chains effective fields across parent-child hierarchies; `_default` is an implicit universal parent; conflict resolution is first-in-walk-wins with advisory `schema_conflict` warnings.

- **Integer coercion (0.4.4-rc.12, vault#310)**: `SchemaField.type` union extended to `"integer"`. `valueMatchesType` accepts `5` and `5.0` (zero fractional); rejects `5.5`, `"5"` (string), non-zero fractional. Gitcoin JSON diffs pass validation cleanly.
- **HTTP metadata filter (0.4.3-rc.2, vault#289)**: Bracket-style `?meta[field][op]=value` with `eq/ne/gt/gte/lt/lte/in/not_in/exists`. Multiple `meta[...]` params AND together. Shorthand `?meta[field]=value` is JSON-scan fallback (no index required). Bridge for `created_at`/`updated_at` columns (real columns, not metadata; only `gte` and `lt` operators allowed).
- **Deprecation path (0.4.3-rc.2, vault#288)**: Flat date params (`?date_field=`, `?date_from=`, `?date_to=`) remain functional through 0.5.x; planned removal 0.6.0. Bracket-style is canonical.
- **Tag inheritance (0.4.2-rc.2, vault#270)**: Child tag's effective fields = its own ∪ all ancestors' (recursive, cycle-safe). Multi-inheritance via `parent_names`; first-in-walk wins with advisory `schema_conflict` warning. `_default` tag is implicit universal parent.
- **`updated_at` in dateFilter (0.4.3-rc.1, vault#286)**: `dateFilter.field` recognizes `updated_at` as a real column. Unblocks incremental-rebuild pattern: `{ field: "updated_at", from: lastBuildISO }`.

### Theme: Multi-Writer Auth & Hub Integration (Vault#212, Vault#281)

Hub-issued JWTs replace vault-minted tokens as the canonical auth path. Hub revocation enforcement (vault#212 Phase 4) checks every JWT against the hub's revocation list on every request with 60-second local caching and fail-open semantics during hub outage. Client-facing revocation-related 401s are sanitized; full diagnostics go to the server-side audit log. The `pvt_*` opaque-token path remains for self-hosted-without-hub setups but is deprecated. `--install-scope user|local|project` gives operators fine-grained control over which `.claude.json` or `.mcp.json` entry the vault server lands in. Tag-scoped tokens compute effective tag set via descendant expansion, with `_default` as universal parent.

- **Hub revocation (0.4.1-rc.6, vault#212 Phase 4 + vault#281)**: JWTs checked against hub's revocation list on every request. 60s local cache TTL, fail-open with last-good during outage, fail-closed on first-fetch failure. Sanitized client 401s; full diagnostics in server-side audit log via `console.warn`.
- **Install scope expansion (0.4.4-rc.3, vault#293)**: Three MCP scopes now first-class: `user` (global `~/.claude.json`), `local` (directory-private `projects[<cwd>].mcpServers` in `~/.claude.json`), `project` (repo-checked `.mcp.json`). Default changed from `user` to `local`; interactive walkthrough always prompts, defaulting based on project markers.
- **Interactive mcp-install (0.4.4-rc.2, vault#292)**: Bare `parachute-vault mcp-install` (TTY, no flags) walks through vault choice, install location, auth mode (mint vs token vs legacy), scope narrowing, and preview before any network call. Smart defaults informed by vault count, hub reachability, project markers, existing entries.
- **Hub-mint as default (0.4.4-rc.1, vault#212 Phase A)**: `--mint` (read `~/.parachute/operator.token`, POST to hub mint endpoint) is the new default. `--token <bearer>` pastes an existing bearer. `--legacy-pat` mints vault-DB `pvt_*` with deprecation notice. `--scope vault:read|vault:write|vault:admin` narrows minted token's scope.

### Theme: Import Reliability & Empty-Note Handling (Vault#323)

The round-trip import smoke test on a real 2290-note, 12-schema, 298-attachment vault revealed two blockers: empty-content notes were rejected; daemon-on-write-lock scenarios left vaults partially replayed. Empty notes (skeletons, drafts, capture-then-fill) are now a valid state—the `EMPTY_NOTE` guard is dropped entirely. Daemon detection on import probes health before touching the database and exits with a clear error if a server is running.

- **Empty notes valid (0.4.4-rc.14, vault#323)**: Dropped `EmptyNoteError` class and all pre-validators in MCP/REST that rejected `content + path both absent`. Empty-content creates + clears now succeed end-to-end.
- **Daemon detection on import (0.4.4-rc.14, vault#323)**: `cmdImport` probes `checkHealth(port)` after vault verification. If healthy/unhealthy (port bound, any HTTP response), exits 1 with actionable error pointing at `parachute stop vault` workaround. WAL/concurrent-writer story is a separate follow-up.

### Theme: Response Shape Flexibility & Lean Representations (Vault#286, Vault#287)

Agents and SSG builders working with large notes need smaller response footprints. `include_content: false` on `update-note` (MCP + REST) swaps the full `Note` for lean `NoteIndex` (drops `content`, keeps `byteSize`, `preview`, `validation_status`), cutting response cost by an order of magnitude. HTTP create/update now attach `validation_status` symmetrically with MCP, so schema warnings surface at write time without a re-read. The response-shape contract is unified across both transports.

- **Lean response (0.4.3-rc.1, vault#286)**: `update-note include_content: false` returns `NoteIndex` instead of full `Note`.
- **Validation status on HTTP (0.4.4-rc.8, vault#287)**: HTTP `POST /api/notes` and `PATCH /api/notes/:id` now attach `validation_status` to responses (single + batch). Mirrors MCP contract exactly; exported from `core/src/mcp.ts` so both transports share one source of truth.

### Theme: Tag Lifecycle & Schema Cascading (Vault#240, Vault#247)

Tag rename now cascades across every surface in a single transaction: tags, sub-tags, `note_tags`, `parent_names` JSON arrays, `tokens.scoped_tags`, `indexed_fields.declarer_tags`, note body references (`#oldname` / `[[_tags/oldname]]`), and `_tags/<old>` config-note paths. Tokens that scoped to the renamed tag are updated in place—the prior `tag_in_use_by_tokens` 409 is dropped; callers now receive `200` with per-surface cascade counts. Breaking change for callers expecting the 409, but enables multi-vault management where tag renames are common.

- **Tag rename cascade (0.4.2-rc.4, vault#240 + vault#247)**: `renameTag(old, new)` rewrites all surfaces in `BEGIN IMMEDIATE` transaction. Returns `200` with cascade stats; replaces the prior `tag_in_use_by_tokens` 409. Breaks callers expecting 409, but enables transparent token rewrite.
- **Schema v17 migration (0.4.2-rc.1, vault#267)**: `note_schemas` + `schema_mappings` tables drop (zero rows in real vaults). Six MCP tools retire: `list-note-schemas`, `update-note-schema`, `delete-note-schema`, `list-schema-mappings`, `set-schema-mapping`, `delete-schema-mapping`. `/api/note-schemas` endpoints removed. `tags.fields` is sole schema surface.

### Theme: Vault Info & Agent Self-Orientation (Vault#271, Vault#274)

`vault-info` now projects a comprehensive schema description—schema-bearing tags with effective inheritance paths, indexed-fields catalog, query-hints array—that an agent uses to self-orient on first connect. The MCP `initialize` response carries a structured markdown rendering. Stats distinguish note-usage tag count from schema-bearing count (`100 tags total, 5 with schemas`), resolving the ambiguity agents hit when many ad-hoc tags lived alongside few schema-bearing ones. Output is token-budgeted for ~5K bytes at 50 schema-bearing tags. Tag-scoped tokens filter the projection to their effective tag set via descendant expansion.

- **vault-info projection (0.4.2-rc.3, vault#271)**: Returns comprehensive schema description with effective inheritance, indexed-fields catalog, query-hints. MCP `initialize` carries markdown projection. Token-scoped filtering via tag descendant expansion.
- **Stats line distinction (0.4.2-rc.5 + 0.4.1-rc.5, vault#274)**: `vault-info` and connect-time stats distinguish `100 tags total, 5 with schemas` instead of conflating tag-count. Closes agent ambiguity.

## § 3. Breaking Changes for 0.2.4 Operators

| Issue | Version | Change | Action Required |
|-------|---------|--------|-----------------|
| vault#267 | 0.4.2 | `note_schemas` / `schema_mappings` tables removed; six MCP tools (`list-note-schemas`, etc.) retired; `/api/note-schemas` REST endpoints gone. `tags.fields` is sole schema surface. | Migrate any callers using the retired MCP tools to use `list-tags`/`update-tag` with the `fields` surface (automatic schema v17 migration handles DB). |
| vault#240, vault#247 | 0.4.2 | Tag rename no longer returns 409 `tag_in_use_by_tokens`; instead returns 200 with cascade stats and transparently rewrites token scopes. | Callers expecting 409 on token conflict must adapt to 200 + inspect cascade result. Token rewrite happens automatically; no operator action. |
| vault#328 | 0.4.5 | Path uniqueness changed from `(path)` to `(path, extension)`. Wikilink ambiguity policy: explicit extension required when paths differ only by case/extension (e.g. `[[Foo.md]]` vs `[[Foo.csv]]`). | Existing vaults auto-migrate (schema v18 adds extension column, defaults all rows to `md`). If you manually create CSV/YAML/JSON notes, supply `extension` field. Wikilinks to ambiguous paths (`[[Foo]]` when `Foo.md` and `Foo.csv` exist) are refused and recorded as unresolved. |
| vault#308 | 0.4.4-rc.9 | Portable-markdown export changed format from flat obsidian shape to nested `metadata:` block with fixed key order (id → path → tags → metadata → links → attachments → created_at → updated_at). Old `toObsidianMarkdown` still available for callers that want it. | No operator action—export is projection, regeneratable. If you store legacy export output, re-run `parachute-vault export` to get new format. Programmatic callers using `toObsidianMarkdown` directly can continue or switch to `toPortableMarkdown`. |
| vault#309 | 0.4.4-rc.12 | `update-note if_missing` parameter added; default `"fail"` (current behavior). No breaking change for callers that omit it. | None required—defaults preserve existing semantics. Callers wanting upsert must opt-in with `if_missing: "create"`. |
| vault#293 | 0.4.4-rc.3 | Non-interactive `parachute-vault mcp-install` default changed from `user` scope (`~/.claude.json` global) to `local` scope (`projects[<cwd>].mcpServers` in `~/.claude.json`). Interactive walkthrough always prompts. | Scripted installs: add `--install-scope user` explicitly to retain global behavior. Interactive installs: prompts appear; operator selects scope. One-line consequence callout printed on `local` default for visibility. |
| vault#212 Phase A | 0.4.4-rc.1 | Hub-mint (`--mint`, default) replaces vault-minted `pvt_*` as canonical auth path. `--legacy-pat` falls back to `pvt_*` with deprecation notice. | `parachute-vault mcp-install` (fresh or re-run) defaults to `--mint`; requires operator token + configured hub origin. For self-hosted-without-hub, pass `--legacy-pat` explicitly (deprecation warning expected). |

## § 4. New CLI Commands & Surface Area

| Command/Parameter | Version | Description |
|---|---|---|
| `parachute-vault export <dir>` | 0.4.4-rc.9 | Export vault to portable-markdown format (`.parachute/vault.yaml` + schemas + notes + attachment binaries). See also `--since <iso>` for incremental exports. |
| `parachute-vault export <dir> --since <iso>` | 0.4.4-rc.9 | Incremental export: only notes with `updated_at >= iso`. For git-projection cadences and SSG rebuilds. |
| `parachute-vault import <dir> --blow-away` | 0.4.4-rc.11 | Disaster-recovery import: wipe vault, replay from portable-markdown export. `--yes` skips confirm; `--dry-run` simulates. |
| `parachute-vault import <dir>` (format detection) | 0.4.4-rc.11 | Auto-detects portable-md vs legacy Obsidian via `.parachute/vault.yaml`. Lossless path if present; legacy parser otherwise. |
| `--install-scope user\|local\|project` | 0.4.4-rc.3 | MCP install scope: `user` (global `~/.claude.json`), `local` (directory-private `projects[<cwd>].mcpServers`), `project` (repo-checked `./.mcp.json`). |
| `parachute-vault mcp-install` (interactive) | 0.4.4-rc.2 | TTY-only walkthrough: vault choice, install location, auth mode (mint/token/legacy), scope, confirm. Non-TTY falls back to flags. |
| `update-note if_missing: "create"\|"fail"` | 0.4.4-rc.12 | MCP + REST: upsert semantics. Create payload from update on missing note. Response includes `created: true\|false`. |
| `create-note extension: "<ext>"` | 0.4.5-rc.1 | MCP + REST: optional file extension for non-markdown content (csv, yaml, json, mdx, txt, etc.). Validation: `/^[a-z0-9]{1,16}$/`, reserved `parachute` prefix guard. |
| `update-note extension: "<ext>"` | 0.4.5-rc.1 | MCP + REST: change note's extension. Wikilink resolution respects explicit-extension form on ambiguity. |
| `query-notes extension: "<ext>"\|["<ext>", ...]` | 0.4.5-rc.1 | Filter by extension (single string or array). Case-insensitive matching. |
| REST `GET /notes?meta[field][op]=value` | 0.4.3-rc.2 | Bracket-style metadata filter with operators: `eq`, `ne`, `gt`, `gte`, `lt`, `lte`, `in`, `not_in`, `exists`. Also `meta[created_at][gte]=…` for real columns. |
| REST `GET /notes?extension=csv&extension=yaml` | 0.4.5-rc.1 | Filter by extension (single or array, comma-separated or repeated param). |
| REST `PATCH /notes/:id include_content: false` | 0.4.3-rc.1 | Return lean `NoteIndex` instead of full `Note` (drops `content`, keeps `byteSize`, `preview`, `validation_status`). |
| MCP `update-note` response `created: true\|false` | 0.4.4-rc.12 | Indicates whether the note was created (if_missing path) or updated. Lets sync loops avoid a follow-up query. |
| REST `PATCH /notes/:id if_missing: "create"\|"fail"` | 0.4.4-rc.12 | Upsert semantics in REST. Creates on missing if `if_missing: "create"`. Response includes `created` field. |
| HTTP `validation_status` in create/update responses | 0.4.4-rc.8 | REST `POST /notes` and `PATCH /notes/:id` now include `validation_status` block (schema warnings, conflicts, type mismatches). Mirrors MCP contract. |
| `--skip-daemon` on `parachute-vault uninstall` | 0.4.4-rc.5 | Test-only flag: bypasses launchd/systemd/backup-agent uninstall. Full path (wrapper, MCP cleanup) still runs. Prevents tests from touching operator state. Undocumented. |

## § 5. Work Still In Flight / Coming Soon

### Attachment ID Restoration (vault#308, PR 2 limitation)

Round-trip import currently re-mints attachment IDs on import. `addAttachment` generates a fresh id; the `Store` interface doesn't yet expose `restoreAttachment(id, ...)`. Frontmatter refs resolve by `(note_id, path)` tuple, so the note-level round-trip is unbroken, but a full round-trip with attachments produces byte-different `attachments[].id` values. A follow-up matching the surface to `restoreNoteTimestamps` is queued but not yet shipped.

### Concurrent-Writer & WAL Story (vault#323)

`parachute-vault import` detects daemon-on-write-lock and exits with a clear error, but the underlying problem (single-writer SQLite under contention) is deferred. WAL mode + proper concurrent-writer support is a separate follow-up, tracked separately from import reliability.

### Cross-Client MCP Support (vault#292, Phase C)

`mcp-install --client claude-code` is the only wired target. Cross-client support (Cursor, Claude Desktop, Codex, Zed, Goose, Cline) + client auto-detection are Phase C, still deferred. The flag surface is future-proof but only Claude Code is implemented.

### Tunable Preview Length

`NoteIndex` returns a 120-character preview; a tunable knob is deferred until a real consumer hits a wall. The default has held through the current release cycle.

### URL-Safe Slug Generation (vault#285 friction point 1.6)

Design pending on stability under rename (derive from id vs path, how to prevent collisions). Deferred until a renderer concretely needs it.

### Flat Date-Param Deprecation (vault#288)

`?date_field=`, `?date_from=`, `?date_to=` remain functional through 0.5.x. Bracket-style metadata filters (`?meta[field][op]=value`) are canonical. Planned removal in 0.6.0 (tracked at vault#288). No operator action needed yet; new code should use bracket-style.

### OR Composition in Metadata Filters

The engine's `metadata` JSON shape doesn't expose OR; all metadata filters AND together. Engine-level work required to support OR; deferred as a future design decision.

### Hub Multi-User UX & Dashboard SDK

Hub-side multi-user capabilities (team collaboration, shared vaults, invite flows) are in-flight on the hub team but not yet reflected in vault's surface. Vault's token/scope machinery is designed for future compatibility; the SDK / admin dashboard are follow-ups on the hub's timeline.

## § 6. Most User-Noticeable Changes

Ranked by user-visible impact:

### 1. Portable, Lossless Export/Import (vault#308)

The single biggest shift: vault is no longer opaque on disk. `parachute-vault export <dir>` produces git-tractable markdown + YAML that can be committed, diffed, and re-imported without losing a single ID, relationship, or timestamp. This unblocks version control, collaboration, and disaster recovery at the system level. Real-world smoke test on a 2296-note vault proved zero silent loss.

### 2. File-Extension Support for Non-Markdown Content (vault#328)

Notes can now be CSV, YAML, JSON, MDX, plaintext—whatever format fits the content. Metadata lives inline (markdown, MDX) or in sidecars (everything else). Path uniqueness is now `(path, extension)` so `Recipes/pasta.md` and `Recipes/pasta.csv` coexist without collision. The wikilink resolution is explicit when ambiguous: `[[Foo.md]]` vs `[[Foo.csv]]`. This is substrate-level: the vault doesn't impose markdown; it handles what you give it.

### 3. Upsert on Update (vault#309)

External systems (Gitcoin, drift detectors, syncs) can now say "create if missing" in a single call, eliminating the query-then-create dance on every nightly sync. `update-note if_missing: "create"` is idempotent: first call creates (with `created: true`), subsequent calls update (with `created: false`). Sync loops know which path fired without a follow-up query.

### 4. Hub-Minted Auth & Revocation Enforcement (vault#212 Phase 4)

JWTs from the hub are now the canonical auth path (vault-minted `pvt_*` tokens deprecated). Hub revocation list is checked on every request with local caching and fail-open semantics. Operators can now revoke compromised tokens at the hub level; vault enforces the revocation within 60 seconds. Self-hosted-without-hub can opt into `--legacy-pat` but get a deprecation notice.

### 5. Interactive MCP Install with Smart Defaults (vault#292)

`parachute-vault mcp-install` from a TTY now walks you through a short, contextual conversation instead of silent defaults. Project markers inform the default install location; hub reachability informs auth-mode defaults; existing entries prompt for update vs fresh. The preview shows exactly what JSON will be written before any network call. Vastly improves the onboarding UX.

### 6. Schema Inheritance & Tag Relationships (vault#270)

Tags can now declare parent-child relationships. A child tag's effective schema fields = its own ∪ all ancestors'. `_default` is the implicit universal parent of every note. Conflict resolution on field overlap is first-in-walk-wins with an advisory `schema_conflict` warning. This enables tag hierarchies that scale from ad-hoc tags to managed schemas.

### 7. Case-Insensitive Filesystem Disambiguation (vault#327)

On macOS and Windows, notes with paths that differ only by case no longer silently collide into one file. Export probes filesystem case-sensitivity; on case-insensitive disks, colliding notes get on-disk filename suffixes while canonical paths in frontmatter stay unchanged. Import recovers truth from frontmatter. Round-trip survives case collisions losslessly.

## Appendix: Schema Migrations

| Version | From | To | Action | Backward-Compat |
|---------|------|-----|--------|-----------------|
| v18 | v17 | v17 → v18 | `ALTER TABLE notes ADD COLUMN extension TEXT NOT NULL DEFAULT 'md'`; widen uniqueness index to `(path, extension)`. | Automatic. All existing rows default to `md`; new composite-index uniqueness collapses to prior behavior on existing data. |
| v17 | v16 | v16 → v17 | Drop `note_schemas` and `schema_mappings` tables (zero rows in real vaults). Retire six related MCP tools and REST endpoints. `tags.fields` becomes sole schema surface. | Automatic. Existing `tags.fields` data is preserved. Callers using dropped MCP tools must migrate to `list-tags`/`update-tag` with the `fields` surface. |

---

*Document compiled 2026-05-15 from CHANGELOG entries 0.2.4 (2026-04-18) through 0.4.5 (2026-05-15). Version span covers: 0.2.4, 0.2.3, 0.2.2, 0.2.1, 0.2.0 (launch), then 0.4.0-rc.2 through 0.4.5-rc.2 and stable 0.4.5. Operators upgrading from 0.2.4 should reference § 3 for breaking changes and § 4 for new surfaces. This synthesis is suitable for both blog-post narrative (§ 1, § 6) and operator migration guide (§ 2, § 3, § 4).*

    </div>
</main>
