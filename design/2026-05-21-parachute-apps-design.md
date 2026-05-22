---
title: "parachute-apps — UI host module for custom UIs, MVP shape"
description: "A new module that supervises a directory of small custom SPAs (Gitcoin Brain, Unforced Brain, …) without each becoming a full npm-published module. The mount-many-UIs-under-one-supervisor primitive."
---
# parachute-apps — UI host module for custom UIs, MVP shape

**Date:** 2026-05-21
**Status:** Proposed. Targets v0.7. The Gitcoin Brain UI (shipped May 2026) and Aaron's about-to-start Unforced Brain UI collectively name the audience this module serves; this doc settles its shape.

**Companions:**
- [`2026-05-21-parachute-runner-design.md`](./2026-05-21-parachute-runner-design.md) — closest precedent (one supervisor, many discovered units); apps mirrors its shape on the UI axis
- [`2026-04-20-module-architecture.md`](./2026-04-20-module-architecture.md) — module protocol apps must comply with
- [`2026-04-20-hub-as-portal-oauth-and-service-catalog.md`](./2026-04-20-hub-as-portal-oauth-and-service-catalog.md) — OAuth architecture each hosted UI integrates against
- [`../../parachute-patterns/patterns/trust-gradient-isolation.md`](../../parachute-patterns/patterns/trust-gradient-isolation.md) — the owner-operated principle that justifies the shape
- [`../../parachute-patterns/patterns/canonical-ports.md`](../../parachute-patterns/patterns/canonical-ports.md) — port table apps slots into
- [`../../parachute-patterns/patterns/module-self-registration.md`](../../parachute-patterns/patterns/module-self-registration.md) — registration pattern apps follows
- [`../../parachute-patterns/patterns/mount-path-convention.md`](../../parachute-patterns/patterns/mount-path-convention.md) — Vite-base / BrowserRouter discipline each hosted UI must respect
- [parachute-patterns#74](https://github.com/ParachuteComputer/parachute-patterns/issues/74) — the issue this design resolves

## The decision

parachute-apps is a new module: a small Bun HTTP service that supervises a directory of pre-built static UI bundles. Each bundle is a self-contained SPA living under `~/.parachute/apps/uis/<name>/`, with a `dist/` (the bundle) and a `meta.json` (mount path, OAuth scopes, display props). apps mounts each declared UI at its declared subpath, serves the bundle with SPA-routing fallback, and auto-registers each as an OAuth client of the hub on add.

The module name is **parachute-apps**; the binary is **`parachute-apps`**; the npm package is **`@openparachute/apps`**. CLI verbs:

- `parachute-apps serve` — long-running Bun process, hub-supervised, watches the `uis/` directory
- `parachute-apps add <path-to-dist> --name <name> --path <mount-path>` — copy a built bundle into `uis/<name>/`, register it
- `parachute-apps list` — what's installed, status, mount path, auto-registered OAuth client_id
- `parachute-apps remove <name>` — uninstall
- `parachute-apps reload <name>` — re-read meta.json + bundle without restarting the daemon

The unit is the UI bundle (a directory of static files + meta.json). The module is the host. They are explicitly separate, and they stay separate.

## Why we got here

Three observations pinned the shape:

**1. The Gitcoin Brain UI established the use case.** Aaron's May 2026 UI for the Gitcoin team's vault is a vanilla SPA — three files (`index.html`, `main.js`, `style.css`), hash-based routing, talks to vault REST via a `pvt_*` bearer the operator pastes on first visit. No build step; no framework. It runs today at `https://unforced-dev.github.io/gitcoin-brain-ui/` and the connection model is "paste vault URL + token." The UX wants to evolve to OAuth-against-hub, and Aaron is about to build a second UI of the same shape (Unforced Brain). The pattern is real: small, operator-curated SPAs that read + write one vault and live as part of a Parachute deployment.

**2. Each-UI-as-its-own-module is too much ceremony for this audience.** A first-class module today means: own git repo, `.parachute/module.json`, port reservation, npm package + RC versioning chain, services.json self-registration, hub install path. That ~all-of-it for *every* small SPA puts a tax on the next custom UI Aaron writes. He'll do this twice in a month then resist building a third. The trust-gradient pattern is explicit about not paying complexity tax that doesn't earn its keep.

**3. The runner-design pattern absorbs this cleanly.** parachute-runner is the supervisor for "many job notes in vault" — the unit (job) is lightweight, the supervisor is the module. parachute-apps mirrors that exactly on the UI axis: many UI bundles in a directory, one supervisor module. Same audience (owner-operated, flat trust gradient), same shape (supervisor + discovered units), same module-protocol surface. The cost of a second supervisor is small; the reuse of the mental model is high.

## What "apps" means precisely

A UI is a directory under `~/.parachute/apps/uis/<name>/` containing:

- `dist/` — the built static bundle (HTML, JS, CSS, assets)
- `meta.json` — declarative metadata: mount path, display name, OAuth scopes required, optional icon URL, version

The apps daemon polls `uis/` on startup and on `reload`. For each declared UI:

1. Parse `meta.json`, validate against schema. Malformed → log, skip, surface as `status: invalid` in `parachute-apps list`.
2. Mount the bundle at `meta.path` under the hub origin (via hub's reverse proxy, same as notes today).
3. Serve `index.html` for any unmatched path under the mount (SPA fallback).
4. On first add, register the UI as an OAuth client of the hub via DCR (RFC 7591) using `meta.scopes_required` and `meta.path` as the redirect-URI base. Persist the resulting `client_id` (no secret — public client, PKCE) in apps' own state.
5. Expose the OAuth `client_id` and discovery doc per-UI at `/apps/<name>/oauth-client` so the UI's JS can read it at boot.

There is no per-UI sandbox, no per-UI origin, no iframe. All UIs share the hub origin. The trust gradient is flat: the operator put the bundles in `uis/`, the operator owns the vault those UIs read, the operator runs the host. Isolation is a parachute-cloud (TBD) concern.

## The 15 design landings

### 1. Naming — `parachute-apps`

**Decision:** the module is `parachute-apps`, npm `@openparachute/apps`, binary `parachute-apps`. Each unit is "an app."

The candidates were `parachute-apps`, `parachute-pages`, `parachute-display`, `parachute-host`, `parachute-mount`, `parachute-surfaces`, `parachute-canvas`, `parachute-deck`. The patterns#74 issue (filed by Aaron) preferred `parachute-pages` — "doesn't conflict with the 'frontend' kind, matches Notion vocabulary."

I'm pushing back: the things we'll host are **apps**, not pages. The Gitcoin Brain UI has hash-based routing, an OAuth dance, state in localStorage, a search input wired to vault full-text — it's not a page. "Pages" undersells what these are and frames them as static content (which biases the audience toward "this is for tiny snippets" rather than "this is for real SPAs"). The Notion-vocabulary echo is real but Notion pages are user-editable content, not bundled SPAs against a backend; the analogy doesn't transfer.

The counter — "apps implies app-store/marketplace" — is real but doesn't bite the owner-operated audience. Apps is the operator's directory of operator-curated UIs; there's no publishing model, no third-party submission, no marketplace UI. The connotation is harmless because the surface contradicts it. (`parachute-canvas` and `parachute-surfaces` overlap with existing vocabulary; `parachute-host` is too generic; `parachute-deck` is interesting but undersold compared to "apps.")

Trade-off accepted: if the audience eventually grows a third-party publishing model, "apps" carries an app-store vibe that we'd need to actively neutralize. The right time to revisit naming is when (if) that model materializes. For v0.7, `parachute-apps` is the most accurate name.

### 2. Shape — B (UI host module supervises many UIs in a directory)

**Decision:** Option B. With Option A as a documented escape hatch when a hosted UI grows its own backend services.

Stress-testing against Aaron's actual two use cases (Gitcoin Brain + Unforced Brain):

**Option A (each UI is its own module).** Each becomes a `.parachute/module.json`-bearing npm package with its own port reservation, services.json row, install command, RC chain, hub install path. For two ~500-line vanilla-JS SPAs that talk to vault REST, this is the ceremony of three committed-core modules to ship two reading rooms. Aaron would do this twice and then resist building the third UI — the friction discourages the use case.

**Option B (host module supervises many UIs).** One module ships once. Adding a UI is `parachute-apps add <path-to-dist> --name <name> --path <mount-path>`. Each UI is a directory + meta.json — no npm, no port, no module.json, no RC chain. The ceremony is paid once (apps itself); marginal cost per UI is the directory copy.

**Option C (vault stores UIs as content as `tag:ui` notes).** Clever but breaks: how does vault serve an SPA bundle? Either vault grows a static-server mode (a new vault responsibility that crosses the data-vs-presentation boundary) or each UI lives as a single HTML note (no multi-file bundle, no real SPA shell, no build tooling). The Gitcoin Brain UI is three files served from a directory — that doesn't fit as a single note. C is right for "tiny widgets stored as content" but wrong for "real SPA bundles."

B wins decisively. The escape-hatch matters: if a future UI grows server-side dependencies (not just vault reads), it graduates to its own module (A). Apps doesn't try to be a backend host. The continuum is clean: B for client-only-against-vault UIs (most things); A for UIs with real backend services.

This also resolves a question the issue left open: **does Notes move into apps?** No. Notes stays as its own module because (a) it's committed-core with its own release cadence and team commitment, (b) it has deep cross-cutting integration (per-vault TagRoles settings, OAuth flow specific to Notes, PWA install + service worker scope), and (c) the canonical first-party UI deserves a first-party module. Apps internally **adopts the same pattern** as hub's `notes-serve.ts` shim (per-UI mount handler, port-and-mount derived from services.json) — that's an implementation kinship, not a merge.

### 3. Repository shape for UIs themselves — each UI is its own project

**Decision:** each UI is its own project / git repo. Operators clone, build, and either run `parachute-apps add <dist>` or symlink/copy the `dist/` into `uis/<name>/`.

Alternatives: a single monorepo of UIs (one repo with `apps/gitcoin-brain/`, `apps/unforced-brain/`, etc.). Rejected because:

- Different UIs are owned by different teams (Gitcoin Brain is for Aaron's Gitcoin work; Unforced Brain is for Aaron's `unforced.org` work; a future UI might be third-party). Monorepo coupling forces shared tooling on parties who don't share infrastructure.
- Different UIs have different build tooling (Gitcoin Brain is vanilla three-file; the next UI might be Vite + React; a third might be Svelte). Monorepo wants a unified build; that fight isn't worth it.
- Independent versioning matters. Each UI ships when its operator wants it to ship, not on a shared cadence.

Trade-off accepted: discoverability — there's no canonical place to find "all UIs hostable by apps." An optional convention "publish your UI as a git repo named `<scope>/parachute-app-<name>`" is fine as a docs note; not enforced.

### 4. Distribution mechanism — CLI `add` for primary path; manual `cp` supported

**Decision:** the primary surface is `parachute-apps add <path-to-dist> --name <name> --path <mount-path>`. Manual `cp -r dist/ ~/.parachute/apps/uis/<name>/` works equivalently as a fallback for the operator who wants to script around it. Git-clone-and-build is deferred to Phase 2; npm-publish is explicitly out of scope.

The `add` flow:

1. Validate `<path-to-dist>` has at least an `index.html` (otherwise reject + warn).
2. Copy the directory contents to `~/.parachute/apps/uis/<name>/dist/`. Reject if `<name>` collides with an existing UI unless `--force` is passed.
3. If a `<path-to-dist>/../parachute-app.json` (or `<path-to-dist>/meta.json`) is present, copy it as `~/.parachute/apps/uis/<name>/meta.json`. Otherwise scaffold a minimal `meta.json` with the `--name` and `--path` flags + sensible defaults, and warn the operator to fill in the rest.
4. Run the OAuth DCR registration against hub for this UI. Persist the resulting `client_id`.
5. Touch the apps daemon's reload signal (or POST `/apps/<name>/reload`) so the running daemon picks up the new mount without a restart.

The manual `cp` path skips step 1 + 2 + 3 (operator does it themselves) and triggers steps 4 + 5 on the next `parachute-apps reload <name>` call.

**Why not git-clone-and-build at MVP:** apps would need a build sandbox per UI, language detection, node/bun version handling, build-tool detection, network access for `npm install`. That's a whole second product. Operators who want git-clone-and-build can shell-script it (`git clone && cd <repo> && bun run build && parachute-apps add ./dist --name <n> --path <p>`). Phase 2 can fold the convenience in.

**Why not npm-publish:** the whole point of apps is to avoid per-UI npm ceremony. If a UI is npm-published with a `module.json`, it's option A, not option B — install it as its own module instead.

### 5. Per-UI metadata schema — `meta.json` (Draft-07)

**Decision:** each UI ships a `meta.json`. Required fields locked in early so they're the operator-facing API.

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["name", "displayName", "path"],
  "properties": {
    "name": {
      "type": "string",
      "pattern": "^[a-z][a-z0-9-]*$",
      "description": "Stable identifier. Becomes the uis/<name>/ directory and OAuth client name."
    },
    "displayName": {
      "type": "string",
      "description": "Human label rendered on hub discovery."
    },
    "tagline": {
      "type": "string",
      "description": "One-line description; rendered under displayName on hub discovery."
    },
    "path": {
      "type": "string",
      "pattern": "^/[a-z0-9-]+$",
      "description": "Mount path under the hub origin (e.g. '/brain'). No trailing slash."
    },
    "version": {
      "type": "string",
      "description": "Bundle version. Free-form; rendered for diagnostics."
    },
    "iconUrl": {
      "type": "string",
      "description": "Path to icon (relative to the UI bundle, e.g. 'icon.svg'). Hub discovery + apps admin SPA render it."
    },
    "scopes_required": {
      "type": "array",
      "items": { "type": "string" },
      "default": ["vault:read"],
      "description": "OAuth scopes the UI requests during DCR registration."
    },
    "vault_default": {
      "type": "string",
      "description": "Optional default vault name (e.g. 'default', 'gitcoin') the UI prefers to read from on first visit. UI can override via its own UX."
    }
  }
}
```

The required-vs-optional split:

- **Required:** `name`, `displayName`, `path`. The minimum apps needs to host the UI.
- **Optional with defaults:** `scopes_required` (defaults to `["vault:read"]` — the least-privilege starting point), `version`, `iconUrl`, `tagline`, `vault_default`.

Validation runs at `add` time and on every daemon poll. Invalid `meta.json` → UI marked `status: invalid`, mount skipped, error surfaced in `parachute-apps list`. Validation failures don't bring down the daemon or affect other UIs.

**Why `name` is constrained to `^[a-z][a-z0-9-]*$`:** it becomes the directory name, the OAuth client identifier, and the URL-safe lookup key in `parachute-apps list`. Same constraint as `module.json`'s `name` field for symmetry.

**Why `path` is constrained:** mount-path conflicts (two UIs at `/brain`) need a deterministic rejection rule. The pattern `^/[a-z0-9-]+$` forces single-segment paths (no `/brain/sub`) at MVP — keeps routing simple. Multi-segment can be a Phase 2 relaxation if real UIs need it.

### 6. Auth model — option A (each UI is its own OAuth client, DCR-registered on add)

**Decision:** each UI is its own OAuth client of the hub, registered via DCR (RFC 7591) at `parachute-apps add` time. The UI does its own OAuth dance against hub using the registered `client_id`. apps does NOT pre-issue tokens or proxy them.

Scopes: default `["vault:read"]`. Operators can override via `meta.scopes_required` (e.g., a UI that creates notes declares `["vault:read", "vault:write"]`). The DCR registration submits exactly those scopes; hub consent UI shows them; user grants; UI gets tokens.

**Why A over B (apps pre-issues tokens):**

- A matches the Notes pattern. Notes is a public OAuth client of the hub with PKCE; the hub's DCR machinery already handles this shape. Reusing it costs apps nothing.
- A keeps apps **out of the credential path**. apps never holds a UI's tokens; never sees a user's grant. Compromising apps doesn't compromise any UI's data access. Compare to B, where apps would be a token-holder for every UI and a juicy single target.
- A makes scope-grant per-UI explicit and revocable in the standard hub admin UI. The user revokes UI-X's token; that's the existing flow.
- A matches the scope-guard pattern used elsewhere in the ecosystem — UI is the resource consumer, hub is the issuer, vault is the resource server.

The trade-off: each UI has to ship OAuth-against-hub JS. For Gitcoin Brain, this is already true (`oauth.js` in the bundle). For future UIs, the operator copies a small bootstrap. A documented snippet + Phase 2 helper library would smooth this, but it's not blocking — Gitcoin Brain's working OAuth implementation is ~150 lines of vanilla JS, copyable.

**Scope default = `vault:read` only:** least-privilege starting point. UIs that genuinely need write declare it. Avoids "every UI gets full vault access by default" — a real attack-surface narrowing without much friction (the operator who knows their UI writes notes adds the scope explicitly).

The per-UI OAuth client lookup endpoint apps exposes — `GET /apps/<name>/oauth-client` returning `{ client_id, scopes, discovery_url }` — lets the UI read its own client_id at boot without baking it into the build (so the same dist bundle can be deployed against different hubs / different `client_id`s).

### 7. Discovery + supervision

**Decision:** apps scans `uis/` at daemon startup and on explicit `reload`. No file watcher in MVP — operators run `parachute-apps reload <name>` or restart the daemon to pick up changes. Phase 2 can add a watcher if friction is real.

**Why no watcher at MVP:** file watching is fiddly across OSes (FSEvents vs. inotify vs. ReadDirectoryChangesW), and the operator action ("I just added a UI") is exactly when they're already at the CLI. The cost-of-cron isn't worth it for MVP.

**What happens to broken UIs:**

- Missing `index.html` in `dist/` → UI marked `status: invalid`, log, skip mount, surface error to `parachute-apps list`. Other UIs unaffected.
- Malformed `meta.json` → same — `status: invalid`, log, skip.
- Mount-path collision (two UIs at `/brain`) → both marked `status: collision`, neither mounted, both surfaced in `list`. Resolution is operator-driven (edit one's meta.json). No alphabetical-wins or first-wins; the operator made a mistake and apps surfaces it loudly.
- OAuth DCR registration failure (hub unreachable, scope rejected) → UI mounted but `status: oauth-unregistered`; the UI's own OAuth dance will fail at runtime; surfaced in `list`. Retry on next `reload`.

**Registration via HTTP API:** apps exposes `POST /apps/add` for programmatic registration (the CLI calls this internally; third-party tooling can call it too). Auth: `apps:admin` scope on a hub-issued bearer.

### 8. Routing + mount

**Decision:** hub's reverse proxy routes `/(<UI mount path>)/*` requests to apps's port (1946); apps serves the bundle for the matched UI with SPA fallback.

- Each UI mounts at `meta.path` (e.g., `/brain`).
- Static assets resolve under that mount: a request for `/brain/main.js` serves `uis/gitcoin-brain/dist/main.js`.
- Unmatched paths under the mount serve `index.html` (SPA-routing fallback). React Router / hash-routing / any client-side router works.
- Asset paths in the bundle should be **mount-relative** (no leading `/`) so the bundle can be re-deployed at a different mount without rebuilding. This is the same discipline as the mount-path-convention pattern's "Vite `base`" rule — for Vite UIs, set `base: meta.path + "/"` at build time; for vanilla UIs (Gitcoin Brain), reference assets as `./main.js` not `/main.js`.
- Mount-path collision is rejected at add-time and at reload-time (see section 7).

apps registers its served paths in services.json as `paths: ["/apps", "/<all mounted UI paths>", "/.parachute"]`. Hub's path-routing picks the longest-prefix match. When a UI is added at `/brain`, apps updates services.json (re-running self-register with the new path list).

**Why apps owns its UIs' mount paths in services.json:** the alternative is each UI getting its own services.json row. That re-introduces the per-UI ceremony we're trying to avoid (each row needs a name, a port — which it doesn't really have since apps is the port-holder, a health endpoint, …). Apps owns one row with a `paths` array that grows + shrinks as UIs come and go. Hub's longest-prefix-match routing handles this fine (this is what hub already does for vault's multi-tenant paths).

### 9. Trust + sandboxing — none in MVP, documented explicitly

**Decision:** MVP ships **no per-UI sandboxing**. All UIs share the hub origin and trust each other through the operator's trust.

This is correct for the v0.6 owner-operated audience per [`trust-gradient-isolation.md`](../../parachute-patterns/patterns/trust-gradient-isolation.md):

- The operator chose which UIs to install.
- The operator owns the vault those UIs talk to.
- The operator owns the host apps runs on.
- All UIs read + write the same vault under operator-granted scopes; the operator's MCP setup already gives anyone with the bearer full access.

Same-origin means UIs can in theory `fetch('/other-app/...')` and read each other's localStorage. That's acceptable because the operator chose the UIs. If a UI is untrusted, **don't install it** — don't reach for sandboxing in a flat gradient.

**What we explicitly do NOT do at MVP:**

- Per-UI subdomain (would require multi-cert / DNS work).
- iframe-per-UI with `sandbox` attributes (breaks SPA navigation, breaks hub-origin OAuth flow, breaks the discovery UX).
- Per-UI CSP headers tighter than apps's default.
- Cross-UI localStorage namespacing (UIs share `window.localStorage`).

For multi-tenant cloud (v0.8+), per-UI isolation becomes load-bearing — that's parachute-cloud's lane. Apps in cloud-mode would either run per-tenant (one apps instance per tenant, separate origins) or grow real per-UI sandboxing. The cloud design is the right home for that decision, not apps MVP. Same pattern as runner's "owner-operated only, no per-job sandbox; multi-tenant is parachute-cloud's lane."

### 10. Module-protocol compliance

apps ships the standard module surface.

**`.parachute/module.json`:**

```json
{
  "name": "apps",
  "manifestName": "parachute-apps",
  "displayName": "Apps",
  "tagline": "Host module for custom Parachute UIs — drop a built bundle in and serve it under one origin.",
  "kind": "frontend",
  "port": 1946,
  "paths": ["/apps", "/.parachute"],
  "stripPrefix": false,
  "health": "/apps/healthz",
  "uiUrl": "/apps",
  "managementUrl": "/apps/admin/",
  "startCmd": ["parachute-apps", "serve"],
  "scopes": {
    "defines": ["apps:read", "apps:admin"]
  }
}
```

A few notes on shape choices:

- `kind: "frontend"` — apps's served output is HTML for users; same default-exposure posture as Notes. The `apps:admin` scope still protects the admin endpoints (per-UI add/remove/reload), so the `kind: "frontend"` + `hasAuth: true`-shaped admin surface coexist. The `kind` field drives hub's discovery-page rendering; the per-endpoint auth gate is independent.
- `paths` is the **initial** list — apps re-stamps services.json as UIs are added/removed with the live UI mount paths appended.
- `uiUrl: "/apps"` — the apps admin SPA is itself a UI on the hub discovery page. The admin SPA shows "what UIs are installed, add/remove/reload them." Per [`module-ui-declaration.md`](../../parachute-patterns/patterns/module-ui-declaration.md).
- `managementUrl: "/apps/admin/"` — trailing slash, per the fragment-token gotcha documented in [`module-json-extensibility.md`](../../parachute-patterns/patterns/module-json-extensibility.md#managementurl-string).
- `port: 1946` claims a fresh slot in the canonical 1939–1949 range. Formal reservation lands in a PR to `parachute-hub/src/service-spec.ts` + `canonical-ports.md` alongside the apps ship, not in this design doc. (Current table: hub 1939, vault 1940, channel 1941, notes 1942, scribe 1943, agent 1944, runner 1945. 1946 is the next free slot.)

**`.parachute/config/schema` (Draft-07):**

| Field | Type | Default | Notes |
|---|---|---|---|
| `hub_url` | string (uri) | — required | Where the hub lives — apps uses this for OAuth DCR registration on `add`. |
| `auto_dcr_register` | boolean | `true` | Whether `add` triggers an automatic DCR registration. Operators who want manual OAuth setup can flip this to false. |
| `default_scopes` | array of string | `["vault:read"]` | Default `scopes_required` for UIs that don't declare their own. |
| `disabled` | boolean | `false` | Global kill switch — daemon stays running but unmounts all UIs and returns 404 under their paths. |

**Self-registration:** apps follows the [`module-self-registration.md`](../../parachute-patterns/patterns/module-self-registration.md) pattern. On `serve` startup, after HTTP listen, apps reads its own `.parachute/module.json`, computes `installDir`, and atomically upserts services.json. On subsequent UI add/remove/reload, apps re-runs the upsert with the updated `paths` array.

### 11. Admin endpoints

apps's HTTP surface:

| Endpoint | Auth | Returns |
|---|---|---|
| `GET /apps/list` | `apps:read` | Array of `{ name, displayName, path, status, version, oauthClientId, scopes }` |
| `GET /apps/<name>/info` | `apps:read` | The UI's parsed `meta.json` + hub-derived fields (oauthClientId, status, mount timestamp) |
| `GET /apps/<name>/oauth-client` | none (the UI reads this at boot) | `{ client_id, scopes, discovery_url }` — the UI's OAuth identity, public-client-shaped |
| `POST /apps/add` | `apps:admin` | Register a new UI. Body: `{ name, path, source: { kind: "filesystem", path: "..." } \| { kind: "upload", base64: "..." }, meta?: object }`. Returns `{ ok, oauthClientId, status }`. |
| `DELETE /apps/<name>` | `apps:admin` | Remove the UI; revoke its OAuth client at hub. |
| `POST /apps/<name>/reload` | `apps:admin` | Re-read `meta.json` + dist contents without daemon restart. |
| `GET /apps/healthz` | none | `{ ok: true, ui_count: N, daemon_active: bool }` |

Plus the standard `.parachute/info`, `.parachute/icon.svg`, `.parachute/config`, `.parachute/config/schema` endpoints.

**Why `oauth-client` is unauthenticated:** the UI's `client_id` is public information (OAuth public clients with PKCE don't have a secret). The UI's JS needs to read it at boot before the user is signed in. Same shape as any public OAuth client discovery endpoint.

**Scopes apps defines:** `apps:read` (read the UI catalog), `apps:admin` (add/remove/reload UIs, modify global config). The `apps:admin` scope is what gates the admin SPA's writes.

### 12. Gitcoin Brain migration walkthrough

End-to-end concrete steps. From "I have a UI at `~/Gitcoin/gitcoin-brain-ui/`" to "I see it at `https://parachute.tailnet.example.com/brain/`."

1. **Install apps.** `parachute install apps` (calls the standard install path; ships canonical module.json + port 1946 + self-registers services.json row).
2. **Configure apps.** Hub's admin SPA shows the apps module-config form (from its `/.parachute/config/schema`). Set `hub_url` to the local hub URL (typically `http://127.0.0.1:1939` for loopback, or the operator's tailnet URL). Defaults for `auto_dcr_register: true` and `default_scopes: ["vault:read"]` are fine.
3. **Start apps.** `parachute start apps` — hub-supervised. Verify `parachute status` shows it healthy on 1946.
4. **Author `meta.json` for Gitcoin Brain.** In `~/Gitcoin/gitcoin-brain-ui/`, create (or update) `meta.json`:
   ```json
   {
     "name": "gitcoin-brain",
     "displayName": "Gitcoin Brain",
     "tagline": "Reading room for the Gitcoin team's vault.",
     "path": "/brain",
     "scopes_required": ["vault:read"],
     "iconUrl": "icon.svg",
     "vault_default": "gitcoin"
   }
   ```
5. **Add the UI to apps.** `parachute-apps add ~/Gitcoin/gitcoin-brain-ui --name gitcoin-brain --path /brain` (the `--name` and `--path` flags override `meta.json`'s values if both are present; the meta.json is copied as the authoritative version going forward). This:
   - Validates `index.html` is present (it is — the three-file bundle).
   - Copies `~/Gitcoin/gitcoin-brain-ui/*` to `~/.parachute/apps/uis/gitcoin-brain/dist/`.
   - Copies `meta.json` to `~/.parachute/apps/uis/gitcoin-brain/meta.json`.
   - Runs OAuth DCR registration against hub with `scopes_required: ["vault:read"]`. Persists `client_id`.
   - Touches reload signal; running daemon picks up the new mount.
   - Updates services.json: apps's row now has `paths: ["/apps", "/.parachute", "/brain"]`.
6. **Update the UI's OAuth bootstrap to read its `client_id` from apps.** Replace the hardcoded vault-URL paste flow in `index.html` / `oauth.js`:
   ```js
   const res = await fetch("/apps/gitcoin-brain/oauth-client");
   const { client_id, scopes, discovery_url } = await res.json();
   // …use client_id + discovery_url to drive the OAuth dance against hub
   ```
   The same pattern Notes uses. Token-paste flow stays as a fallback for dev.
7. **Re-build (if there's a build) and re-`add`.** For Gitcoin Brain's vanilla three-file bundle there's no build step — edit and re-`add`. For Vite UIs, `bun run build && parachute-apps reload gitcoin-brain` (the reload path picks up changes to `dist/` without re-running OAuth registration).
8. **Verify.** Open `https://parachute.tailnet.example.com/brain/`. Sign in via hub OAuth (the consent screen shows "Gitcoin Brain wants: read your vault"). Grant. UI loads with vault data.
9. **Discovery.** The apps row appears in `/.well-known/parachute.json`; hub's discovery page renders a "Gitcoin Brain" tile linking to `/brain/` (via apps's per-UI uiUrl propagation — see open question #3 below).

Migration time estimate: ~15 min for a UI that already has working OAuth-against-hub JS; ~30 min for a UI that needs the token-paste-to-OAuth swap. Cheap enough that Aaron will do it for both UIs without it feeling like a chore.

### 13. Comparison table — notes vs apps-hosted-UI

| Aspect | Notes (own module) | Apps-hosted UI |
|---|---|---|
| Ship as | Published npm package (`@openparachute/notes`) | Built static bundle, dropped in `uis/<name>/dist/` |
| Versioning | RC chain, semver, npm publish gates | Whatever the operator wants — bundle version is opaque to apps |
| Install | `parachute install notes` | `parachute-apps add <path>` |
| Port | Own port (1942) | Shares apps's port (1946) |
| Services.json row | Own row (`parachute-notes`) | Shares apps's row, path appended |
| OAuth client | One client_id per Notes install, DCR-registered by hub on install | One client_id per UI, DCR-registered by apps on add |
| Module-protocol surface | Own `.parachute/info`, `/config`, `/config/schema`, `/healthz` | Inherits apps's surface for module-level; per-UI info at `/apps/<name>/info` |
| Hub admin SPA config form | Yes (Notes-specific) | Apps's config form covers global settings; per-UI config is meta.json + apps's add/remove flow |
| Cross-vault customization | Per-vault TagRoles + settings note | Per-UI; UI handles its own settings |
| Update cadence | Released by Parachute team | Released by UI's operator/author |
| Restart on update | `parachute restart notes` | `parachute-apps reload <name>` (no daemon restart) |
| Reviewer + release gate | Parachute governance (RC chain, reviewer dispatch, Aaron clicks merge) | Operator's own (apps doesn't gate adds) |

**When (A) wins over (B):**

- UI needs server-side compute beyond what vault provides (background workers, server-side OAuth callbacks for third-party APIs, native binary dependencies).
- UI is a publishable npm package wanted by many operators with first-party support (Notes is the canonical example).
- UI needs its own port / its own services.json row for reasons specific to its protocol (e.g., it's also an MCP server).
- UI is committed-core — i.e., the Parachute team commits to maintaining + releasing it.

For owner-curated SPAs against vault (Gitcoin Brain, Unforced Brain, future ones), **B is right**. Notes specifically stays as A because of its committed-core + first-party-canonical status, not because of any technical block.

### 14. Phasing

**MVP (v0.7 target):**

- `parachute-apps serve` daemon with HTTP server on 1946.
- `parachute-apps add`, `list`, `remove`, `reload` CLI verbs.
- meta.json Draft-07 schema + validation at add and reload.
- Mount registration: each UI served under its declared path, SPA fallback, mount-relative asset resolution.
- OAuth DCR registration on `add`, persisting per-UI client_id.
- Per-UI `oauth-client` endpoint (unauthenticated, public-client discovery).
- Admin HTTP surface: `GET /apps/list`, `GET /apps/<name>/info`, `POST /apps/add`, `DELETE /apps/<name>`, `POST /apps/<name>/reload`, `GET /apps/healthz`.
- Module protocol scaffolding: `.parachute/info`, `.parachute/config/schema`, `.parachute/config`, `.well-known/parachute.json`, services.json self-registration (with dynamic `paths` array).
- Hub-supervised on local + Render. Same install path as runner/vault/notes/scribe.
- Hub admin SPA config form support via the generic schema-driven form.
- Phase 1 of Gitcoin Brain migration: drop the token-paste flow, use `oauth-client` endpoint.

**Phase 2 (v0.8+):**

- File watcher in `uis/` so adding/removing a UI doesn't require an explicit `reload`.
- Git-clone-and-build flow: `parachute-apps add --from-git <url> [--branch <b>]` clones, runs declared build command, copies dist. (Build sandbox boundaries TBD.)
- Apps admin SPA: a richer UI for managing installed apps (rendered at `/apps/admin/`), beyond the generic config form. Shows per-UI status grid, recent OAuth grants, per-UI mount toggle.
- Helper library: `@openparachute/app-bootstrap` npm package with the canonical OAuth dance JS, so a new UI doesn't have to copy 150 lines of vanilla OAuth code.
- Per-UI `uiUrl` propagation into hub discovery (see open question #3).

**Phase 3 (deferred indefinitely):**

- Per-UI sandboxing (subdomain, iframe, or CSP-based). Becomes relevant only when multi-tenant cloud lands — that's parachute-cloud's lane.
- Third-party publishing model (an "app store" of installable UIs). Out of scope for v0.7's owner-operated audience.
- Hot-reload of in-flight sessions when a UI is reloaded. Today's reload requires the user to refresh the browser tab.

### 15. Open questions

Flagged for resolution during build or for Aaron, not blockers:

1. **Apps's services.json `paths` array growing dynamically — does hub's longest-prefix routing actually handle this cleanly when UIs come and go between hub restarts?** Vault's multi-tenant model is the precedent (vault adds a path per new vault), so the answer should be "yes, this works the same way." Worth a smoke during MVP build to confirm hub re-reads services.json on every routing decision rather than caching the path table at boot.

2. **Per-UI `uiUrl` propagation into hub's discovery page.** Apps itself declares `uiUrl: "/apps"` (the apps admin SPA), but the hosted UIs are individual tiles too — each one wants its own discovery tile. The cleanest seam is: apps publishes `/.well-known/parachute.json/apps-children` (or similar) with a list of hosted UIs + their displayName/tagline/path; hub reads it as a virtual sub-set of frontend entries. Or, apps writes one services.json row per hosted UI (which contradicts section 8's "apps owns one row" decision — there's a real tension here). Resolve during build by trying the well-known-extension shape first; revisit if it doesn't surface cleanly in hub's discovery.

3. **Should apps own the OAuth DCR registration, or should hub own it on apps's behalf?** Currently the design says apps registers each UI directly. The alternative: apps notifies hub "I have a new UI named X with scopes Y," and hub creates the client. The alternative is cleaner (hub remains the OAuth authority; apps doesn't need to know DCR protocol) but adds a hub-side endpoint specifically for this case. MVP-leaning: apps does the DCR call directly using its own bearer with `hub:dcr-register` scope (or equivalent). Hub-mediated is a Phase 2 refactor if the trust boundary is uncomfortable.

4. **Per-UI scope inheritance.** A UI declares `scopes_required: ["vault:read"]`. The operator who installs that UI may want to widen it (e.g., to `vault:gitcoin:read` for a specific vault). MVP: scopes are exactly what meta.json declares — no operator override. If operators routinely want per-install scope changes, add a CLI flag (`--scopes ...`) at Phase 2.

5. **Storage of OAuth client secrets.** Public OAuth clients with PKCE don't have a secret, so this is moot for the default flow. If a future UI registers as a confidential client (for some server-side OAuth callback flow), apps would need to store the secret encrypted. MVP defers — public clients only.

6. **Per-UI logging.** Each UI is a static bundle with no server-side; logging happens in the browser. apps could capture access logs (which UIs are being hit, by which user). MVP: apps logs to its own stdout the per-request mount + path; per-user attribution requires reading the hub-issued bearer's `sub` claim, which apps doesn't do today. Phase 2 addition if operators want it.

7. **Apps's own admin SPA — is it shipped with apps, or is it a Hosted-by-apps UI of itself?** Most elegant: apps ships a bare-minimum HTML admin page that uses `apps:admin` scope, mounted at `/apps/admin/`. Future apps admin SPA could itself be a hosted UI (apps eating its own dog food). MVP ships the bare HTML page; the dog-fooded SPA is a Phase 2 polish.

## What's new vs the Gitcoin Brain UI today

For readers familiar with the current Gitcoin Brain UI (deployed at `unforced-dev.github.io`):

| Aspect | Today | Apps-hosted |
|---|---|---|
| Hosting | GitHub Pages (external) | Parachute hub origin |
| Vault discovery | Operator pastes vault URL on first visit | Service catalog from hub-issued token |
| Auth | Operator pastes `pvt_*` token | OAuth-against-hub with PKCE, per-UI client_id |
| Bundle update | Push to GitHub, Pages rebuilds | `parachute-apps reload gitcoin-brain` after rebuild |
| Discovery | URL passed person-to-person | Hub discovery tile, alongside Notes / Vault / etc. |
| Multiple installs | Each user runs against own vault | Each operator has their own apps install with their own UIs |
| Token storage | localStorage in browser | OAuth refresh tokens managed by hub; UI holds short-lived access tokens |

The current UI works; apps makes it ecosystem-native. Same shape, same UX intent, ecosystem-shaped integration.

## Why the architecture is right

Three equivalences make this small primitive load-bearing:

**The runner equivalence.** parachute-runner is the supervisor for vault job-notes; parachute-apps is the supervisor for UI bundles. Same shape (one daemon, N discovered units, lightweight per-unit registration), same audience (owner-operated, flat trust gradient), same module-protocol surface. Two supervisors on the same pattern means future supervisors (parachute-feeds for RSS sources? parachute-bots for chat agents?) inherit the conceptual model for free.

**The notes equivalence.** Notes is the canonical first-party UI module. Apps is "the easy path for UIs that aren't first-party." A new operator-curated UI doesn't have to compete for committed-core status to land in a Parachute deployment — it just gets dropped in `uis/`. The boundary between "first-party module" and "operator-curated UI" stays clean: A for first-party, B for operator-curated, no fuzzy middle.

**The trust-gradient equivalence.** Apps is explicitly flat-gradient. The operator chose every UI in `uis/`; the operator owns the vault; there's nothing to sandbox from. Same architectural justification as runner. When multi-tenant cloud arrives, apps in cloud-mode is one of the things that needs to change shape (per-tenant origin, per-UI sandboxing) — and that's a parachute-cloud problem, not an apps problem.

Apps is small on purpose. The supervisor + meta.json + DCR-on-add machinery is maybe ~500 lines of TypeScript plus the standard module-protocol scaffolding. The complexity it absorbs (per-UI hosting ceremony) is real; the complexity it adds is small. Keeping it small is the design.
