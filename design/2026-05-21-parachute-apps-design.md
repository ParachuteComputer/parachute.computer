---
title: "parachute-app — UI host module for custom UIs, MVP shape"
description: "A new module that supervises a directory of small custom SPAs (Gitcoin Brain, Unforced Brain, …) without each becoming a full npm-published module. The mount-many-UIs-under-one-supervisor primitive."
---
# parachute-app — UI host module for custom UIs, MVP shape

**Date:** 2026-05-21
**Status:** Proposed. Targets v0.7. The Gitcoin Brain UI (shipped May 2026), Aaron's about-to-start Unforced Brain UI, and **Notes itself** (which migrates from own-module to app-hosted over 4 phases — see section 16) collectively name the audience this module serves. App is positioned as committed-core; Notes is the canonical first app installed under it.

**Naming note:** the module is **parachute-app** (singular), mirroring the vault precedent — `parachute-vault` (singular module) hosts many vault instances; `parachute-app` (singular module) hosts many app instances. The filename of this design doc keeps "apps" for historical continuity with PR #54; the artifact name is `parachute-app` throughout.

**Companions:**
- [`2026-05-21-parachute-runner-design.md`](./2026-05-21-parachute-runner-design.md) — closest precedent (one supervisor, many discovered units); app mirrors its shape on the UI axis
- [`2026-04-20-module-architecture.md`](./2026-04-20-module-architecture.md) — module protocol app must comply with
- [`2026-04-20-hub-as-portal-oauth-and-service-catalog.md`](./2026-04-20-hub-as-portal-oauth-and-service-catalog.md) — OAuth architecture each hosted UI integrates against
- [`../../parachute-patterns/patterns/trust-gradient-isolation.md`](../../parachute-patterns/patterns/trust-gradient-isolation.md) — the owner-operated principle that justifies the shape
- [`../../parachute-patterns/patterns/canonical-ports.md`](../../parachute-patterns/patterns/canonical-ports.md) — port table app slots into
- [`../../parachute-patterns/patterns/module-self-registration.md`](../../parachute-patterns/patterns/module-self-registration.md) — registration pattern app follows
- [`../../parachute-patterns/patterns/mount-path-convention.md`](../../parachute-patterns/patterns/mount-path-convention.md) — Vite-base / BrowserRouter discipline each hosted UI must respect
- [parachute-patterns#74](https://github.com/ParachuteComputer/parachute-patterns/issues/74) — the issue this design resolves
- [parachute-hub#301](https://github.com/ParachuteComputer/parachute-hub/issues/301) — drop `kind` from module.json; app ships without it
- [parachute-hub#292](https://github.com/ParachuteComputer/parachute-hub/pull/292) (merged 2026-05-21) — install path now stamps `installDir` on services.json rows; verified hub already reads services.json per-request (no caching)
- [parachute-notes/DEPRECATED.md](../../parachute-notes/DEPRECATED.md) (planned, Phase 3) — Notes module retirement, mirrors `parachute-agent/DEPRECATED.md`
- [parachute-notes#151](https://github.com/ParachuteComputer/parachute-notes/issues/151) — dev-rebuild ergonomics (SW caches stale code); solved at the platform level by section 18

## The decision

parachute-app is a new module: a small Bun HTTP service that supervises a directory of pre-built static UI bundles. Each bundle is a self-contained SPA living under `~/.parachute/app/uis/<name>/`, with a `dist/` (the bundle) and a `meta.json` (mount path, OAuth scopes, display props). app mounts each declared UI at its declared subpath, serves the bundle with SPA-routing fallback, and auto-registers each as an OAuth client of the hub on add.

The module name is **parachute-app**; the binary is **`parachute-app`**; the npm package is **`@openparachute/app`**. CLI verbs:

- `parachute-app serve` — long-running Bun process, hub-supervised, watches the `uis/` directory
- `parachute-app add <path-to-dist> --name <name> --path <mount-path>` — copy a built bundle into `uis/<name>/`, register it
- `parachute-app list` — what's installed, status, mount path, auto-registered OAuth client_id
- `parachute-app remove <name>` — uninstall
- `parachute-app reload <name>` — re-read meta.json + bundle without restarting the daemon

The unit is the UI bundle (a directory of static files + meta.json). The module is the host. They are explicitly separate, and they stay separate.

## Why we got here

Three observations pinned the shape:

**1. The Gitcoin Brain UI established the use case.** Aaron's May 2026 UI for the Gitcoin team's vault is a vanilla SPA — three files (`index.html`, `main.js`, `style.css`), hash-based routing, talks to vault REST via a `pvt_*` bearer the operator pastes on first visit. No build step; no framework. It runs today at `https://unforced-dev.github.io/gitcoin-brain-ui/` and the connection model is "paste vault URL + token." The UX wants to evolve to OAuth-against-hub, and Aaron is about to build a second UI of the same shape (Unforced Brain). The pattern is real: small, operator-curated SPAs that read + write one vault and live as part of a Parachute deployment.

**2. Each-UI-as-its-own-module is too much ceremony for this audience.** A first-class module today means: own git repo, `.parachute/module.json`, port reservation, npm package + RC versioning chain, services.json self-registration, hub install path. That ~all-of-it for *every* small SPA puts a tax on the next custom UI Aaron writes. He'll do this twice in a month then resist building a third. The trust-gradient pattern is explicit about not paying complexity tax that doesn't earn its keep.

**3. The runner-design pattern absorbs this cleanly.** parachute-runner is the supervisor for "many job notes in vault" — the unit (job) is lightweight, the supervisor is the module. parachute-app mirrors that exactly on the UI axis: many UI bundles in a directory, one supervisor module. Same audience (owner-operated, flat trust gradient), same shape (supervisor + discovered units), same module-protocol surface. The cost of a second supervisor is small; the reuse of the mental model is high.

## What "app" means precisely

A UI is a directory under `~/.parachute/app/uis/<name>/` containing:

- `dist/` — the built static bundle (HTML, JS, CSS, assets)
- `meta.json` — declarative metadata: mount path, display name, OAuth scopes required, optional icon URL, version

The app daemon polls `uis/` on startup and on `reload`. For each declared UI:

1. Parse `meta.json`, validate against schema. Malformed → log, skip, surface as `status: invalid` in `parachute-app list`.
2. Mount the bundle at `meta.path` under the hub origin (via hub's reverse proxy, same as notes today).
3. Serve `index.html` for any unmatched path under the mount (SPA fallback).
4. On first add, register the UI as an OAuth client of the hub via DCR (RFC 7591) using `meta.scopes_required` and `meta.path` as the redirect-URI base. Persist the resulting `client_id` (no secret — public client, PKCE) in app's own state.
5. Expose the OAuth `client_id` and discovery doc per-UI at `/app/<name>/oauth-client` so the UI's JS can read it at boot.

There is no per-UI sandbox, no per-UI origin, no iframe. All UIs share the hub origin. The trust gradient is flat: the operator put the bundles in `uis/`, the operator owns the vault those UIs read, the operator runs the host. Isolation is a parachute-cloud (TBD) concern.

**Framework freedom for hosted UIs.** parachute-app requires only a `dist/` directory with an `index.html`. Your UI can be Vite + React (recommended for the JS bootstrap convenience), Vue, Svelte, vanilla JS, anything — app doesn't care. The Vite + React stack is what app's *own* admin SPA uses (see section 7), not what app *requires* of hosted UIs.

## The 19 design landings

### 1. Naming — `parachute-app` (singular)

**Decision:** the module is `parachute-app` (singular), npm `@openparachute/app`, binary `parachute-app`. Each unit hosted by the module is "an app."

This mirrors **vault precedent**: `parachute-vault` (singular module) hosts many vault instances; `parachute-app` (singular module) hosts many app instances. The relationship between module-name and hosted-units is the same shape across the ecosystem.

The patterns#74 issue preferred `parachute-pages`. Pushing back: the things hosted are **apps**, not pages. The Gitcoin Brain UI has hash-based routing, an OAuth dance, state in localStorage, a search input wired to vault full-text — it's not a page. "Pages" undersells what these are. The other rejected candidates (`parachute-display`, `parachute-host`, `parachute-mount`, `parachute-surfaces`, `parachute-canvas`, `parachute-deck`) were either too generic, overlapping with existing vocabulary, or undersold compared to "app."

The "app implies app-store/marketplace" concern is real but doesn't bite the owner-operated audience. App is the operator's directory of operator-curated UIs; there's no publishing model, no third-party submission, no marketplace UI. The connotation is harmless because the surface contradicts it.

### 2. Shape — B (UI host module supervises many UIs in a directory)

**Decision:** Option B. With Option A as a documented escape hatch when a hosted UI grows its own backend services.

Stress-testing against Aaron's actual two use cases (Gitcoin Brain + Unforced Brain):

**Option A (each UI is its own module).** Each becomes a `.parachute/module.json`-bearing npm package with its own port reservation, services.json row, install command, RC chain, hub install path. For two ~500-line vanilla-JS SPAs that talk to vault REST, this is the ceremony of three committed-core modules to ship two reading rooms. Aaron would do this twice and then resist building the third UI — the friction discourages the use case.

**Option B (host module supervises many UIs).** One module ships once. Adding a UI is `parachute-app add <path-to-dist> --name <name> --path <mount-path>`. Each UI is a directory + meta.json — no npm, no port, no module.json, no RC chain. The ceremony is paid once (app itself); marginal cost per UI is the directory copy.

**Option C (vault stores UIs as content as `tag:ui` notes).** Clever but breaks: how does vault serve an SPA bundle? Either vault grows a static-server mode (a new vault responsibility that crosses the data-vs-presentation boundary) or each UI lives as a single HTML note (no multi-file bundle, no real SPA shell, no build tooling). The Gitcoin Brain UI is three files served from a directory — that doesn't fit as a single note. C is right for "tiny widgets stored as content" but wrong for "real SPA bundles."

B wins decisively. The escape-hatch matters: if a future UI grows server-side dependencies (not just vault reads), it graduates to its own module (A). App doesn't try to be a backend host. The continuum is clean: B for client-only-against-vault UIs (most things); A for UIs with real backend services.

This also resolves a question the issue left open: **does Notes move into app?** Yes — **app replaces notes**. Notes-as-module retires; Notes lives forward as the canonical first app installed under parachute-app, distributed as the `@openparachute/notes-ui` bundle. The migration arc is captured in detail in section 13 (Notes migration to app). The short of it: app's existence collapses the per-module-ceremony tax that justified Notes-as-module today, and Notes' PWA-specific needs (offline-first, service worker) are absorbed by app's opt-in PWA mode (section 18). Notes' release cadence + team commitment carry forward — they're commitments to the bundle's quality, not to the module shape. The committed-core line ends up as **vault + app + scribe + hub** post-migration; Notes-as-app lives within app as the first canonical app installed.

### 3. Repository shape for UIs themselves — each UI is its own project

**Decision:** each UI is its own project / git repo. Operators clone, build, and either run `parachute-app add <dist>` or symlink/copy the `dist/` into `uis/<name>/`.

Alternatives: a single monorepo of UIs (one repo with `app/gitcoin-brain/`, `app/unforced-brain/`, etc.). Rejected because:

- Different UIs are owned by different teams (Gitcoin Brain is for Aaron's Gitcoin work; Unforced Brain is for Aaron's `unforced.org` work; a future UI might be third-party). Monorepo coupling forces shared tooling on parties who don't share infrastructure.
- Different UIs have different build tooling (Gitcoin Brain is vanilla three-file; the next UI might be Vite + React; a third might be Svelte). Monorepo wants a unified build; that fight isn't worth it.
- Independent versioning matters. Each UI ships when its operator wants it to ship, not on a shared cadence.

Trade-off accepted: discoverability — there's no canonical place to find "all UIs hostable by app." An optional convention "publish your UI as a git repo named `<scope>/parachute-app-<name>`" is fine as a docs note; not enforced.

### 4. Distribution mechanism — CLI `add` for primary path; manual `cp` supported

**Decision:** the primary surface is `parachute-app add <path-to-dist> --name <name> --path <mount-path>`. Manual `cp -r dist/ ~/.parachute/app/uis/<name>/` works equivalently as a fallback for the operator who wants to script around it. Git-clone-and-build is deferred to Phase 2; npm-publish is explicitly out of scope.

The `add` flow:

1. Validate `<path-to-dist>` has at least an `index.html` (otherwise reject + warn).
2. Copy the directory contents to `~/.parachute/app/uis/<name>/dist/`. Reject if `<name>` collides with an existing UI unless `--force` is passed.
3. If a `<path-to-dist>/../parachute-app.json` (or `<path-to-dist>/meta.json`) is present, copy it as `~/.parachute/app/uis/<name>/meta.json`. Otherwise scaffold a minimal `meta.json` with the `--name` and `--path` flags + sensible defaults, and warn the operator to fill in the rest.
4. Run the OAuth DCR registration against hub for this UI. Persist the resulting `client_id`.
5. Touch the app daemon's reload signal (or POST `/app/<name>/reload`) so the running daemon picks up the new mount without a restart.

The manual `cp` path skips step 1 + 2 + 3 (operator does it themselves) and triggers steps 4 + 5 on the next `parachute-app reload <name>` call.

**Why not git-clone-and-build at MVP:** app would need a build sandbox per UI, language detection, node/bun version handling, build-tool detection, network access for `npm install`. That's a whole second product. Operators who want git-clone-and-build can shell-script it (`git clone && cd <repo> && bun run build && parachute-app add ./dist --name <n> --path <p>`). Phase 2 can fold the convenience in.

**Why not npm-publish:** the whole point of app is to avoid per-UI npm ceremony. If a UI is npm-published with a `module.json`, it's option A, not option B — install it as its own module instead.

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
      "pattern": "^/app/[a-z0-9-]+$",
      "description": "Mount path under the hub origin, always under /app/ (e.g. '/app/gitcoin-brain'). No trailing slash."
    },
    "version": {
      "type": "string",
      "description": "Bundle version. Free-form; rendered for diagnostics."
    },
    "iconUrl": {
      "type": "string",
      "description": "Path to icon (relative to the UI bundle, e.g. 'icon.svg'). Hub discovery + app admin SPA render it."
    },
    "scopes_required": {
      "type": "array",
      "items": { "type": "string" },
      "default": ["vault:*:read"],
      "description": "OAuth scopes the UI declares as required. Wildcards (vault:*:read) signal vault-agnostic; concrete names (vault:gitcoin:read) signal vault-specific."
    },
    "public": {
      "type": "boolean",
      "default": false,
      "description": "If true, hub does not enforce a session gate at /app/<name>/* — the UI is reachable unauthenticated. Default false (gated)."
    }
  }
}
```

The required-vs-optional split:

- **Required:** `name`, `displayName`, `path`. The minimum app needs to host the UI.
- **Optional with defaults:** `scopes_required` (defaults to `["vault:*:read"]` — least-privilege starting point, vault-agnostic), `version`, `iconUrl`, `tagline`, `public`.

Validation runs at `add` time and on every daemon poll. Invalid `meta.json` → UI marked `status: invalid`, mount skipped, error surfaced in `parachute-app list`. Validation failures don't bring down the daemon or affect other UIs.

**Scope shape — wildcard vs concrete.** The `scopes_required` array declares the **shape** of scopes a UI needs, not a binding to a specific vault. Two idioms:

- **Vault-agnostic (multi-vault) UIs** declare wildcards: `["vault:*:read", "vault:*:write"]`. The UI handles vault selection in-app (Notes-style — see notes' `VaultPopover` component). Each vault-pick triggers an OAuth flow narrowed to the selected vault; tokens are stored per-vault client-side.
- **Vault-specific (single-vault) UIs** declare concrete names: `["vault:gitcoin:read", "vault:gitcoin:write"]`. The UI is bound to one vault at install time; the OAuth flow grants the concrete scopes.

This generalizes the Notes pattern. Today Notes' VaultPopover lets users pick which vault to work against, doing an OAuth flow per vault and caching the token per vault. Same shape applies to any multi-vault app hosted under parachute-app.

**Why `name` is constrained to `^[a-z][a-z0-9-]*$`:** it becomes the directory name, the OAuth client identifier, and the URL-safe lookup key in `parachute-app list`. Same constraint as `module.json`'s `name` field for symmetry.

**Why `path` is constrained to `^/app/[a-z0-9-]+$`:** all hosted UIs live under the `/app/` mount that parachute-app owns. Single-segment after `/app/` keeps routing simple at MVP; multi-segment can be a Phase 2 relaxation if real UIs need it. Mount-path conflicts (two UIs at `/app/brain`) need a deterministic rejection rule (see section 7).

### 6. Auth model — same-hub auto-trust + multi-vault install-once

**Decision:** each UI is its own OAuth client of the hub, registered via DCR (RFC 7591) at `parachute-app add` time. The UI does its own OAuth dance against hub using the registered `client_id`. app does NOT pre-issue tokens or proxy them. But **the consent ceremony is silent for same-hub apps**.

#### Same-hub auto-trust (the major simplification)

Quoting Aaron: *"we shouldn't need to say that it's okay for an app that's on here to refer to a Vault that's also on here. The user is still authenticating with the vault."*

When a user visits a hosted UI and the UI initiates an OAuth flow against hub:

- For scopes shaped `vault:<name>:read` or `vault:<name>:write` (or narrower, e.g. `vault:*:read`): **hub auto-approves silently. No consent screen.** Same-hub apps installed by the operator are trusted by virtue of having been installed; the install IS the consent.
- For scopes shaped `vault:<name>:admin` (high-power — destructive ops, schema changes, token mints): **consent screen still required** as a last sanity gate. Admin power gets the extra friction.

This generalizes [hub#270](https://github.com/ParachuteComputer/parachute-hub/issues/270)'s "auto-approve the first OAuth client after wizard" to "auto-approve same-hub apps for non-admin scopes." The trust gradient is: install-time gating (operator chose this app) replaces grant-time gating (user clicks "Allow"). Admin-scope is the one exception that keeps consent in the loop.

Per-UI client_id and DCR auto-registration are still load-bearing — they're how revocation, per-UI audit, and scope-grant tracking continue to work. The user-visible change is the consent screen disappears for the common case.

#### Install-once + multi-vault pattern

A UI's meta.json declares scope **shape**, not vault binding:

```json
// Single-vault (bound at meta.json time)
{
  "name": "gitcoin-brain",
  "displayName": "Gitcoin Brain",
  "path": "/app/gitcoin-brain",
  "scopes_required": ["vault:gitcoin:read", "vault:gitcoin:write"]
}

// Multi-vault (vault chosen at use time)
{
  "name": "notes",
  "displayName": "Notes",
  "path": "/app/notes",
  "scopes_required": ["vault:*:read", "vault:*:write"]
}
```

The pattern:

- **Install-once, single mount path.** A multi-vault UI is installed once at one path. The UI doesn't get installed per-vault.
- **UI handles vault selection.** An in-app picker (e.g. Notes' VaultPopover) lets the user pick which vault to work against. The picker reads available vaults from the hub's service catalog.
- **OAuth flow per vault-pick.** When the user selects a vault, the UI initiates an OAuth flow narrowed to that vault — concrete scopes like `vault:gitcoin:read` derived from the wildcard `vault:*:read`. The hub mints a token scoped to that one vault.
- **Token-per-vault stored client-side.** The UI maintains a token cache keyed by vault name (Notes' current pattern). Switching vaults swaps tokens; no extra round-trip if a fresh-enough token is cached.

This is what Notes does today. parachute-app generalizes it — any multi-vault app inherits the same flow.

#### Why each UI is its own OAuth client (not one shared client)

- It matches the Notes pattern. Notes is a public OAuth client of the hub with PKCE; the hub's DCR machinery already handles this shape. Reusing it costs app nothing.
- It keeps app **out of the credential path**. App never holds a UI's tokens; never sees a user's grant. Compromising app doesn't compromise any UI's data access.
- Per-UI client makes scope-grant per-UI explicit and revocable in the standard hub admin UI. The user revokes UI-X's token; that's the existing flow.
- It matches the scope-guard pattern used elsewhere — UI is the resource consumer, hub is the issuer, vault is the resource server.

The per-UI OAuth client lookup endpoint app exposes — `GET /app/<name>/oauth-client` returning `{ client_id, scopes, discovery_url }` — lets the UI read its own client_id at boot without baking it into the build (so the same dist bundle can be deployed against different hubs / different `client_id`s).

### 7. App's own admin SPA — Vite + React, bundled with the package

**Decision:** parachute-app ships with its own admin SPA, built with **Vite + React** (matching the notes stack), bundled inside the `@openparachute/app` npm package. Mounted at `/app/admin/` — a path the app module reserves for itself, separate from user-added apps under `/app/<name>/`.

The admin SPA is **not** dogfooded as a hosted-UI of itself. Aaron's explicit call: *"too messy."* Mounting it as a regular UI through app's own discovery surface would mean the admin needs an OAuth client_id, would be subject to the same gating as user UIs, would appear in `parachute-app list` as a UI you can `remove`, etc. — a recursive special case for marginal elegance. The cleaner shape: app's admin SPA is a known fixed path served directly by the app daemon, distinct from the directory-driven UIs.

Capability surface of the admin SPA:

- List installed UIs + their status (active, invalid, oauth-unregistered, collision).
- Per-UI: open the UI, view meta.json, view OAuth client_id, view recent access stats, remove the UI.
- Add a UI from a local-path source (upload not in MVP — operator drops `dist/` on the box and uses the path picker; or runs `parachute-app add` from CLI).
- Toggle the app daemon's global config (the `.parachute/config` form values).

The `parachute-app/admin/` path is reserved at the app daemon level: meta.json files attempting to claim `path: "/app/admin"` are rejected at add time.

**The admin SPA inherits the caching defaults from section 18:** no service worker, smart cache headers on `index.html` (no-cache) vs. hashed Vite output (immutable). Hot-reload during admin development uses the same `parachute-app dev admin` plumbing as user-added UIs, with one wrinkle — the admin path is reserved, so the dev-mode CLI accepts `admin` as a special case that targets the bundled admin SPA's source directory inside the npm package's source tree (only meaningful in dev installs).

### 8. Discovery + supervision

**Decision:** app scans `uis/` at daemon startup and on explicit `reload`. No file watcher in MVP — operators run `parachute-app reload <name>` or restart the daemon to pick up changes. Phase 2 can add a watcher if friction is real.

**Why no watcher at MVP:** file watching is fiddly across OSes (FSEvents vs. inotify vs. ReadDirectoryChangesW), and the operator action ("I just added a UI") is exactly when they're already at the CLI. The cost-of-cron isn't worth it for MVP.

**What happens to broken UIs:**

- Missing `index.html` in `dist/` → UI marked `status: invalid`, log, skip mount, surface error to `parachute-app list`. Other UIs unaffected.
- Malformed `meta.json` → same — `status: invalid`, log, skip.
- Mount-path collision (two UIs at `/app/brain`) → both marked `status: collision`, neither mounted, both surfaced in `list`. Resolution is operator-driven (edit one's meta.json). No alphabetical-wins or first-wins; the operator made a mistake and app surfaces it loudly.
- OAuth DCR registration failure (hub unreachable, scope rejected) → UI mounted but `status: oauth-unregistered`; the UI's own OAuth dance will fail at runtime; surfaced in `list`. Retry on next `reload`.
- Reserved-path collision (meta.json claims `/app/admin`) → rejected at add, `status: reserved-path`.

**Registration via HTTP API:** app exposes `POST /app/add` for programmatic registration (the CLI calls this internally; third-party tooling can call it too). Auth: `app:admin` scope on a hub-issued bearer.

### 9. Routing + mount + hub-level auth gate

**Decision:** hub's reverse proxy routes `/app/*` requests to the app daemon's port (1946). The app daemon owns the entire `/app/` namespace. Within that namespace, the daemon serves each hosted UI under `/app/<name>/` and the admin SPA under `/app/admin/`.

- Each UI mounts at `meta.path` (e.g., `/app/gitcoin-brain`).
- Static assets resolve under that mount: a request for `/app/gitcoin-brain/main.js` serves `uis/gitcoin-brain/dist/main.js`.
- Unmatched paths under the mount serve `index.html` (SPA-routing fallback). React Router / hash-routing / any client-side router works.
- Asset paths in the bundle should be **mount-relative** (no leading `/`) so the bundle can be re-deployed at a different mount without rebuilding. This is the same discipline as the mount-path-convention pattern's "Vite `base`" rule — for Vite UIs, set `base: meta.path + "/"` at build time; for vanilla UIs (Gitcoin Brain), reference assets as `./main.js` not `/main.js`.

**Hub-level auth gate at `/app/<name>/*` (default = gated).** Before forwarding any request under a hosted UI's mount to the app daemon, hub enforces session auth: unauthenticated requests are redirected to `/login` with `next=/app/<name>/...`. The gate is on by default. Per-UI opt-out via `meta.json`: `"public": true` makes the UI reachable unauthenticated (use case: a public landing page hosted under app). The admin SPA at `/app/admin/` is always gated regardless of meta.json — it's app's own surface, not a hosted UI.

The gate is implemented hub-side (in the reverse-proxy layer), not app-side. App doesn't need to know who the user is to serve static assets; the gate just protects the bundle from anonymous reads when the operator wants gating.

### 10. Trust + sandboxing — none in MVP, documented explicitly

**Decision:** MVP ships **no per-UI sandboxing**. All UIs share the hub origin and trust each other through the operator's trust.

This is correct for the v0.6 owner-operated audience per [`trust-gradient-isolation.md`](../../parachute-patterns/patterns/trust-gradient-isolation.md):

- The operator chose which UIs to install.
- The operator owns the vault those UIs talk to.
- The operator owns the host app runs on.
- All UIs read + write the same vault under operator-granted scopes; the operator's MCP setup already gives anyone with the bearer full access.

Same-origin means UIs can in theory `fetch('/app/other-ui/...')` and read each other's localStorage. That's acceptable because the operator chose the UIs. If a UI is untrusted, **don't install it** — don't reach for sandboxing in a flat gradient.

**What we explicitly do NOT do at MVP:**

- Per-UI subdomain (would require multi-cert / DNS work).
- iframe-per-UI with `sandbox` attributes (breaks SPA navigation, breaks hub-origin OAuth flow, breaks the discovery UX).
- Per-UI CSP headers tighter than app's default.
- Cross-UI localStorage namespacing (UIs share `window.localStorage`).

For multi-tenant cloud (v0.8+), per-UI isolation becomes load-bearing — that's parachute-cloud's lane. App in cloud-mode would either run per-tenant (one app instance per tenant, separate origins) or grow real per-UI sandboxing. The cloud design is the right home for that decision, not app MVP. Same pattern as runner's "owner-operated only, no per-job sandbox; multi-tenant is parachute-cloud's lane."

### 11. Module-protocol compliance — no `kind`, hub infers from `paths` + `health`

App ships the standard module surface.

**`.parachute/module.json`:**

```json
{
  "name": "app",
  "manifestName": "parachute-app",
  "displayName": "App",
  "tagline": "Host module for custom Parachute UIs — drop a built bundle in and serve it under one origin.",
  "port": 1946,
  "paths": ["/app", "/.parachute"],
  "stripPrefix": false,
  "health": "/app/healthz",
  "uiUrl": "/app/admin/",
  "managementUrl": "/app/admin/",
  "startCmd": ["parachute-app", "serve"],
  "scopes": {
    "defines": ["app:read", "app:admin"]
  }
}
```

**No `kind` field.** Per [hub#301](https://github.com/ParachuteComputer/parachute-hub/issues/301), the `kind ∈ {"api" | "frontend" | "tool"}` trichotomy is the wrong frame for app: app is *both* frontend (serves UI bundles) *and* backend (admin endpoints + supervision). Dropping `kind` entirely — letting hub infer routing behavior from `paths` + `health` + the `static: boolean` field hub#301 phase B introduces — is cleaner than picking the wrong-fit value. App ships without `kind` from day one and is one of the first modules to test the post-kind world hub#301 is migrating toward.

`static: boolean` is also the wrong shape for app and is **not** included. App serves static bundles AND dynamic admin endpoints; a single boolean doesn't capture that. Hub's per-path routing (which it already does via the `paths` array) is sufficient — paths matching mounted-UI prefixes route to static-asset behavior; paths matching `/app/api/*` or `/app/admin/api/*` route as backend. The shape is per-request, derived from the path, not per-module.

A few notes on other shape choices:

- `paths: ["/app", "/.parachute"]` — app owns the entire `/app` namespace. Per section 12, hosted-UI sub-paths surface in services.json as a separate `uis` map (not appended to `paths`), pending hub-side schema work.
- `uiUrl: "/app/admin/"` — app's admin SPA is the module-level "UI." Per-UI uiUrls (the discovery surface for each hosted UI) flow via the hierarchical `uis` field in services.json (section 12).
- `managementUrl: "/app/admin/"` — trailing slash, per the fragment-token gotcha documented in [`module-json-extensibility.md`](../../parachute-patterns/patterns/module-json-extensibility.md#managementurl-string).
- `port: 1946` claims a fresh slot in the canonical 1939–1949 range. Formal reservation lands in a PR to `parachute-hub/src/service-spec.ts` + `canonical-ports.md` alongside the app ship, not in this design doc. (Current table: hub 1939, vault 1940, channel 1941, notes 1942, scribe 1943, agent 1944, runner 1945. 1946 is the next free slot.)

**`.parachute/config/schema` (Draft-07):**

| Field | Type | Default | Notes |
|---|---|---|---|
| `hub_url` | string (uri) | — required | Where the hub lives — app uses this for OAuth DCR registration on `add`. |
| `auto_dcr_register` | boolean | `true` | Whether `add` triggers an automatic DCR registration. Operators who want manual OAuth setup can flip this to false. |
| `default_scopes` | array of string | `["vault:*:read"]` | Default `scopes_required` for UIs that don't declare their own. Wildcard default mirrors the multi-vault-by-default expectation. |
| `disabled` | boolean | `false` | Global kill switch — daemon stays running but unmounts all UIs and returns 404 under their paths. |

**Self-registration:** app follows the [`module-self-registration.md`](../../parachute-patterns/patterns/module-self-registration.md) pattern. On `serve` startup, after HTTP listen, app reads its own `.parachute/module.json`, computes `installDir`, and atomically upserts services.json. On subsequent UI add/remove/reload, app re-runs the upsert with the updated `uis` map (see section 12).

### 12. services.json shape — hierarchical, mirror vault

**Decision:** app registers in services.json as a hierarchical entry with a nested `uis` map, one entry per hosted UI. Hub discovery surfaces "App" as the module-level row; clicking through reveals each hosted UI (Gitcoin Brain, Unforced Brain) as a sub-unit — exactly the surface vault gives for multiple vault instances.

**Proposed shape:**

```json
{
  "parachute-app": {
    "name": "app",
    "manifestName": "parachute-app",
    "displayName": "App",
    "port": 1946,
    "paths": ["/app"],
    "health": "/app/healthz",
    "version": "0.1.0",
    "installDir": "/Users/parachute/ParachuteComputer/parachute-app",
    "uis": {
      "gitcoin-brain": {
        "displayName": "Gitcoin Brain",
        "tagline": "Reading room for the Gitcoin team's vault.",
        "path": "/app/gitcoin-brain",
        "iconUrl": "/app/gitcoin-brain/icon.svg",
        "scopes_required": ["vault:gitcoin:read", "vault:gitcoin:write"],
        "oauthClientId": "client_abc123",
        "status": "active"
      },
      "unforced-brain": {
        "displayName": "Unforced Brain",
        "tagline": "Reading room for the unforced.org vault.",
        "path": "/app/unforced-brain",
        "iconUrl": "/app/unforced-brain/icon.svg",
        "scopes_required": ["vault:unforced:read", "vault:unforced:write"],
        "oauthClientId": "client_def456",
        "status": "active"
      }
    }
  }
}
```

**Why hierarchical, not flat.** Hub today reads vault's flat `paths: ["/vault/default", "/vault/gitcoin", ...]` array and renders each path as a discoverable sub-unit. That works but loses per-unit display metadata (displayName, tagline, icon) — each sub-vault renders as a path, not a named thing. The hierarchical shape carries display metadata per sub-unit, which is exactly what app's discovery UX needs (and what vault should grow to as well).

**This requires hub-side schema work.** The `ServiceEntry` type in `parachute-hub/src/services-manifest.ts` today has flat fields only (`name`, `port`, `paths`, `health`, `version`, `displayName`, `tagline`, `installDir`, `stripPrefix`). Adding a nested `uis: Record<string, UiEntry>` field requires:

1. Schema extension in `services-manifest.ts` (`UiEntry` interface + validation).
2. Discovery rendering: hub's `/` HTML + `/.well-known/parachute.json` surface the `uis` sub-units as their own tiles, linking to `entry.uis[k].path`.
3. Per-UI access logging hooks (the entry carries `oauthClientId`; hub-side request logging can attribute by it).

**Dynamic-reload is already a property of hub.** Hub reads services.json per-request (verified by reading `parachute-hub/src/services-manifest.ts` post-#292); there is no in-memory cache to bust. App's runtime writes to services.json — on every UI add/remove/reload — will be visible to hub on the next request without a restart. The "hub must learn to reload services.json" framing (formerly tracked at hub#311) is moot; hub#311 was closed as resolved-by-#292 on 2026-05-21. PR #292 (merged 2026-05-21) is the last piece of the puzzle — it stamps `installDir` on services.json rows in the API install path, which is what fixed the install-doesn't-show-in-discovery symptom.

**The schema extension is the remaining hub-side work.** The hierarchical `uis` field is a real schema-extension question separate from the dynamic-reload concern. Hub's current `ServiceEntry` interface accepts the flat shape; the `uis` map needs an interface addition + validation. Track this as its own hub issue; it's not blocked by anything else.

**Migration plan for vault.** Once app's hierarchical shape lands, vault can adopt the same shape in a follow-up (`paths: ["/vault"]` + `uis: { default: ..., gitcoin: ..., ... }`). This isn't blocking for app; vault's flat shape continues to work via hub's existing path-prefix routing. The point of the hierarchical shape is **forward-consistent ecosystem discovery**.

### 13. Admin endpoints

App's HTTP surface:

| Endpoint | Auth | Returns |
|---|---|---|
| `GET /app/list` | `app:read` | Array of `{ name, displayName, path, status, version, oauthClientId, scopes }` |
| `GET /app/<name>/info` | `app:read` | The UI's parsed `meta.json` + hub-derived fields (oauthClientId, status, mount timestamp) |
| `GET /app/<name>/oauth-client` | none (the UI reads this at boot) | `{ client_id, scopes, discovery_url }` — the UI's OAuth identity, public-client-shaped |
| `POST /app/add` | `app:admin` | Register a new UI. Body: `{ name, path, source: { kind: "filesystem", path: "..." } \| { kind: "upload", base64: "..." }, meta?: object }`. Returns `{ ok, oauthClientId, status }`. |
| `DELETE /app/<name>` | `app:admin` | Remove the UI; revoke its OAuth client at hub. |
| `POST /app/<name>/reload` | `app:admin` | Re-read `meta.json` + dist contents without daemon restart. |
| `GET /app/healthz` | none | `{ ok: true, ui_count: N, daemon_active: bool }` |
| `GET /app/admin/*` | session (hub-gated) | The admin SPA (Vite + React bundle). |

Plus the standard `.parachute/info`, `.parachute/icon.svg`, `.parachute/config`, `.parachute/config/schema` endpoints.

**Why `oauth-client` is unauthenticated:** the UI's `client_id` is public information (OAuth public clients with PKCE don't have a secret). The UI's JS needs to read it at boot before the user is signed in. Same shape as any public OAuth client discovery endpoint.

**Scopes app defines:** `app:read` (read the UI catalog), `app:admin` (add/remove/reload UIs, modify global config). The `app:admin` scope is what gates the admin SPA's writes.

### 14. Gitcoin Brain migration walkthrough

End-to-end concrete steps. From "I have a UI at `~/Gitcoin/gitcoin-brain-ui/`" to "I see it at `https://parachute.tailnet.example.com/app/gitcoin-brain/`."

**Gitcoin Brain is the second app installed.** Notes (via `@openparachute/notes-ui`, see section 16) is the first — either bundled with parachute-app's installer as the canonical first app or one `parachute-app add @openparachute/notes-ui` away. This walkthrough assumes Notes is already installed; the steps below are general and apply to any custom UI Aaron adds after Notes.

1. **Install app.** `parachute install app` (calls the standard install path; ships canonical module.json + port 1946 + self-registers services.json row). At first install, Notes is the canonical first app to bootstrap.
2. **Configure app.** Hub's admin SPA shows the app module-config form (from its `/.parachute/config/schema`). Set `hub_url` to the local hub URL (typically `http://127.0.0.1:1939` for loopback, or the operator's tailnet URL). Defaults for `auto_dcr_register: true` and `default_scopes: ["vault:*:read"]` are fine.
3. **Start app.** `parachute start app` — hub-supervised. Verify `parachute status` shows it healthy on 1946.
4. **Author `meta.json` for Gitcoin Brain.** In `~/Gitcoin/gitcoin-brain-ui/`, create (or update) `meta.json`:
   ```json
   {
     "name": "gitcoin-brain",
     "displayName": "Gitcoin Brain",
     "tagline": "Reading room for the Gitcoin team's vault.",
     "path": "/app/gitcoin-brain",
     "scopes_required": ["vault:gitcoin:read", "vault:gitcoin:write"],
     "iconUrl": "icon.svg"
   }
   ```
5. **Add the UI to app.** `parachute-app add ~/Gitcoin/gitcoin-brain-ui --name gitcoin-brain --path /app/gitcoin-brain`. This:
   - Validates `index.html` is present (it is — the three-file bundle).
   - Copies `~/Gitcoin/gitcoin-brain-ui/*` to `~/.parachute/app/uis/gitcoin-brain/dist/`.
   - Copies `meta.json` to `~/.parachute/app/uis/gitcoin-brain/meta.json`.
   - Runs OAuth DCR registration against hub with `scopes_required: ["vault:gitcoin:read", "vault:gitcoin:write"]`. Persists `client_id`.
   - Touches reload signal; running daemon picks up the new mount.
   - Updates services.json: app's `uis` map now includes the new entry.
6. **Update the UI's OAuth bootstrap to read its `client_id` from app.** Replace the hardcoded vault-URL paste flow in `index.html` / `oauth.js`:
   ```js
   const res = await fetch("/app/gitcoin-brain/oauth-client");
   const { client_id, scopes, discovery_url } = await res.json();
   // …use client_id + discovery_url to drive the OAuth dance against hub
   ```
   The same pattern Notes uses. Token-paste flow stays as a fallback for dev.
7. **Re-build (if there's a build) and re-`add`.** For Gitcoin Brain's vanilla three-file bundle there's no build step — edit and re-`add`. For Vite UIs, `bun run build && parachute-app reload gitcoin-brain` (the reload path picks up changes to `dist/` without re-running OAuth registration).
8. **Verify.** Open `https://parachute.tailnet.example.com/app/gitcoin-brain/`. Sign in via hub (if you weren't already). The OAuth flow runs silently — same-hub auto-trust skips the consent screen for `vault:gitcoin:read` + `vault:gitcoin:write`. UI loads with vault data.
9. **Discovery.** Hub's discovery page shows "App" as a module; clicking through reveals "Gitcoin Brain" as a sub-tile linking to `/app/gitcoin-brain/`.

Migration time estimate: ~15 min for a UI that already has working OAuth-against-hub JS; ~30 min for a UI that needs the token-paste-to-OAuth swap. Cheap enough that Aaron will do it for both UIs without it feeling like a chore.

**Dev iteration.** For iterative work on Gitcoin Brain after it's installed:

```
1. parachute-app dev gitcoin-brain    # disables caching, opens SSE live-reload
2. Edit ~/Gitcoin/gitcoin-brain-ui/ source
3. bun run build                       # (skip if no build step — for the vanilla three-file bundle, edit dist/ directly)
4. The browser tab auto-reloads via SSE; new code is visible
5. parachute-app dev --off gitcoin-brain   # restore production caching when done
```

Per section 18, dev mode disables all caching for the named UI and pushes a reload signal to connected browser tabs every time the bundle directory changes. Phase 2 will fold step 3 into the dev mode itself via `dev_build_cmd` in meta.json — for MVP, the operator runs the build manually after editing source.

### 15. Comparison table — Module-A vs App-hosted-B

| Aspect | Own module (A) | App-hosted UI (B) |
|---|---|---|
| Ship as | Published npm package (`@openparachute/<name>`) | Built static bundle, dropped in `uis/<name>/dist/` |
| Versioning | RC chain, semver, npm publish gates | Whatever the operator wants — bundle version is opaque to app |
| Install | `parachute install <name>` | `parachute-app add <path>` |
| Port | Own port | Shares app's port (1946) |
| Services.json entry | Own row | Sub-entry under app's `uis` map |
| OAuth client | One client_id per install, DCR-registered by hub | One client_id per UI, DCR-registered by app on add |
| Module-protocol surface | Own `.parachute/info`, `/config`, `/config/schema`, `/healthz` | Inherits app's surface for module-level; per-UI info at `/app/<name>/info` |
| Hub admin SPA config form | Yes (module-specific) | App's config form covers global settings; per-UI config is meta.json + app's add/remove flow |
| Update cadence | Released by Parachute team or third-party | Released by UI's operator/author |
| Restart on update | `parachute restart <name>` | `parachute-app reload <name>` (no daemon restart) |
| Reviewer + release gate | Parachute governance (RC chain, reviewer dispatch, Aaron clicks merge) | Operator's own (app doesn't gate adds) |

**When (A) wins over (B):**

- UI needs server-side compute beyond what vault provides (background workers, server-side OAuth callbacks for third-party APIs, native binary dependencies).
- UI needs its own port / its own services.json row for reasons specific to its protocol (e.g., it's also an MCP server).
- UI is structurally a backend (scribe-shaped: transcription worker with HTTP control plane).

**Notes-specifically.** At the time of this design's first revision, Notes was placed in the A column as the canonical first-party UI. That framing reversed during this revision: Notes' shape (vanilla SPA + service worker + OAuth-against-hub + per-vault picker) is exactly the shape app was built for, and app's existence removes the per-module-ceremony tax that justified Notes-as-module. **Notes migrates to B** — see section 16 for the full migration arc. Post-migration, the A column's exemplars are scribe and vault (backend-shaped modules); the B column's exemplars are Notes (multi-vault), Gitcoin Brain (single-vault), Unforced Brain, and the long tail of future custom UIs.

### 16. Notes migration to app

Notes is the first app. Its migration from own-module to app-hosted is the proof-of-pattern for the whole architecture — if Notes can be an app, the bar for graduating any other UI to its own module gets higher.

**Phase 1 — parachute-app v0.7 MVP ships (this design).**

- parachute-app ships per section 17 (phasing). Hub admin SPA shows the new "Add app" surface.
- parachute-notes repo continues to build + publish `@openparachute/notes` as a module (port 1942, services.json row, etc.) on its current cadence.
- A parallel build target lands: `@openparachute/notes-ui` — same source code, output is the `dist/` bundle + meta.json, no module surface. Published to npm as a regular package.
- Operators who want notes-as-app can run `parachute-app add @openparachute/notes-ui --name notes --path /notes`. The CLI grows an npm-fetch shorthand (Phase 2 of app's distribution mechanism — see section 4) so this is one command, not a manual clone + build.
- Notes-as-app and Notes-as-module are both available; operators choose. Cloud (parachute-cloud, TBD) defaults Notes-as-app.

**Phase 2 — parachute-notes v0.4: Notes-as-module deprecated.**

- parachute-notes repo's `module.json` is removed; the build target shifts entirely from "module with daemon" to "UI bundle published as `@openparachute/notes-ui`."
- `@openparachute/notes` (module package) ships its final RC chain. `parachute install notes` is removed from hub's install path.
- A `parachute-notes/DEPRECATED.md` lands, mirroring `parachute-agent/DEPRECATED.md` shape: "module retired, migrate to `parachute-app add @openparachute/notes-ui`."
- Hub admin SPA's "Notes module" tile becomes a "Notes app" tile. Settings that were the module's `.parachute/config/schema` move into Notes's meta.json + app's per-UI config.
- The hub's per-route reverse-proxy entry for `/notes/*` continues to work, but now routes to `/app/notes/*` internally via a redirect for backwards-compat URLs.

**Phase 3 — parachute-notes v0.5: full retirement.**

- parachute-notes module is fully retired. Port 1942 is reclaimed and reassigned to whichever next module needs a slot (likely `parachute-jobs` or a successor — see workspace CLAUDE.md note on parachute-agent's retirement and parachute-jobs's plausible reclaim).
- Hub's `/notes/*` → `/app/notes/*` redirect runs for one release window as backwards-compat, then retires.
- Documentation, blog posts, and design docs update: the four committed-core modules are vault, app, scribe, hub. Notes is the canonical first app.

**Phase 4 — cleanup (post-1.0).**

- parachute-notes redirect retired.
- Operators on legacy installs (still running `parachute-notes` as a module) get a one-time migration notice on hub upgrade.
- The parachute-notes repo is either archived (if it has no remaining role) or refactored to be the UI-bundle-only repo (`@openparachute/notes-ui` becomes its sole npm publish).

**Cross-references:**

- `parachute-agent/DEPRECATED.md` is the precedent for module-retirement docs (committed-core 2026-05-05 → retired 2026-05-20). parachute-notes's eventual DEPRECATED.md follows the same shape.
- The committed-core list, currently **vault + notes + scribe + hub**, becomes **vault + app + scribe + hub** after Phase 3. Notes-as-app lives within app as the canonical first app installed.

**What carries forward unchanged:**

- Notes' source code (the actual React + offline-first PWA logic).
- Notes' UX, brand, identity. Users don't see "Notes is an app now"; they see Notes.
- Per-vault TagRoles + settings flow (now a Notes-UI concern, not a module concern).
- VaultPopover + multi-vault token caching (already the pattern app generalizes).
- PWA install + service worker — preserved via app's opt-in `"pwa": true` meta.json field (section 18).

**What changes:**

- No port 1942. No `parachute restart notes` (becomes `parachute-app reload notes`).
- No own services.json row. Notes is a sub-entry under app's `uis` map.
- No per-Notes RC chain — Notes ships when notes-ui's npm publish ships.
- Module-config form folds into Notes's per-UI meta.json + Notes-side UI for the rest.

### 17. Phasing

**MVP (v0.7 target):**

- `parachute-app serve` daemon with HTTP server on 1946.
- `parachute-app add`, `list`, `remove`, `reload` CLI verbs.
- meta.json Draft-07 schema + validation at add and reload.
- Mount registration: each UI served under its declared path, SPA fallback, mount-relative asset resolution.
- OAuth DCR registration on `add`, persisting per-UI client_id.
- Same-hub auto-trust: hub auto-approves DCR clients for non-admin scopes (extends hub#270 logic).
- Per-UI `oauth-client` endpoint (unauthenticated, public-client discovery).
- Hub-level session gate at `/app/<name>/*` (default on, opt-out via meta.json `public: true`).
- Admin HTTP surface: `GET /app/list`, `GET /app/<name>/info`, `POST /app/add`, `DELETE /app/<name>`, `POST /app/<name>/reload`, `GET /app/healthz`.
- Vite + React admin SPA at `/app/admin/` — list/add/remove/configure UIs.
- Module protocol scaffolding: `.parachute/info`, `.parachute/config/schema`, `.parachute/config`, `.well-known/parachute.json`, services.json self-registration with hierarchical `uis` map.
- Hub-supervised on local + Render. Same install path as runner/vault/notes/scribe.
- Hub admin SPA config form support via the generic schema-driven form.
- Phase 1 of Gitcoin Brain migration: drop the token-paste flow, use `oauth-client` endpoint + auto-trust.
- Phase 1 of Notes migration (section 16): `@openparachute/notes-ui` published as a parallel build target; `parachute-app add @openparachute/notes-ui` works alongside the existing `parachute install notes`.
- Caching strategy (section 18): no-SW default, opt-in PWA via meta.json `"pwa": true`, smart cache headers on index.html vs hashed assets.
- Dev mode (section 18): `parachute-app dev <name>` disables caching for the named UI + SSE live-reload to connected browser tabs.

**Phase 2 (v0.8+):**

- File watcher in `uis/` so adding/removing a UI doesn't require an explicit `reload`.
- Git-clone-and-build flow: `parachute-app add --from-git <url> [--branch <b>]` clones, runs declared build command, copies dist. (Build sandbox boundaries TBD.)
- npm-fetch shorthand: `parachute-app add @openparachute/notes-ui` fetches the published package and installs the bundle.
- Richer admin SPA: per-UI status grid, recent OAuth grants, per-UI mount toggle, per-UI access logs.
- Helper library: `@openparachute/app-bootstrap` npm package with the canonical OAuth dance JS, so a new UI doesn't have to copy 150 lines of vanilla OAuth code.
- Phase 2 of Notes migration: parachute-notes v0.4 deprecates the module form; `parachute-notes/DEPRECATED.md` lands; hub's `/notes/*` → `/app/notes/*` redirect runs for backwards-compat.
- Dev mode auto-rebuild: `dev` mode runs the UI's declared `dev_build_cmd` on `dev_watch_dir` changes, eliminating the manual `bun run build` step.

**Phase 3 (deferred indefinitely):**

- Per-UI sandboxing (subdomain, iframe, or CSP-based). Becomes relevant only when multi-tenant cloud lands — that's parachute-cloud's lane.
- Third-party publishing model (an "app store" of installable UIs). Out of scope for v0.7's owner-operated audience.
- Hot-reload of in-flight sessions when a UI is reloaded. Today's reload requires the user to refresh the browser tab.
- Phase 3 of Notes migration (parachute-notes v0.5): parachute-notes module fully retires; port 1942 reclaimed.
- Phase 4 of Notes migration (post-1.0): legacy redirect retired; parachute-notes repo archived or refactored to UI-only.

### 18. Caching + reload strategy

A recurring frustration tracked at [parachute-notes#151](https://github.com/ParachuteComputer/parachute-notes/issues/151): edit notes source, run `bun run build`, the browser shows old code. The culprit is the service worker caching the previous bundle. Solving this at the platform level — so future apps inherit a clean default — is the design intent here. App's HTTP serving makes the right choice the default, and PWA is opt-in for the apps that genuinely need offline-first behavior.

**Default (MVP): no service worker.**

App serves UI bundles with smart cache headers that match the bundle's content-hashed asset convention:

- `index.html` (the SPA entrypoint): `Cache-Control: no-cache, no-store, must-revalidate`. The browser always fetches a fresh index.html on every page load.
- Bundled assets with content-hash filenames (`app.a3b9f2.js`, `style.7e1c.css`, etc.): `Cache-Control: public, max-age=31536000, immutable`. Cache forever — the filename changes on rebuild, so a new index.html will reference new filenames.
- Non-hashed assets (e.g. `icon.svg`, static images that aren't part of the build output): `Cache-Control: public, max-age=3600`. Cache for an hour as a sensible default; operators can override per-UI in meta.json if needed (Phase 2 — `meta.cache_headers` extension).

This pattern (Vite, Webpack, Parcel, esbuild, Rollup, Rspack — all major build tools default to content-hashed asset filenames) means: rebuild produces new hashed assets; next page load fetches the fresh index.html; index.html references the new hashed assets; the old hashes evict from cache eventually but never get served fresh. **No service worker = no service worker caching problem.** Operators don't have to think about it.

**Opt-in per UI: PWA mode via meta.json.**

For UIs that genuinely need offline-first behavior (Notes is the canonical example — the whole point of Notes is "edit your vault offline on your phone"), meta.json grows an opt-in PWA mode:

```json
{
  "name": "notes",
  "displayName": "Notes",
  "path": "/notes",
  "pwa": true,
  "pwa_service_worker": "sw.js"
}
```

When `pwa: true`:

- App mounts the service worker at the UI's mount path (e.g. `/notes/sw.js`).
- App serves the SW file with `Cache-Control: no-cache` so SW updates propagate immediately on rebuild.
- The UI is responsible for its own SW logic — registration, `skipWaiting`, `controllerchange`, the user-facing "new version available, refresh" prompt. Notes' existing pattern (the [notes#148](https://github.com/ParachuteComputer/parachute-notes/issues/148) work) is the reference implementation; future PWA-mode apps copy it.
- Operators see "PWA: yes" in `parachute-app list` for PWA-mode UIs, so they know a SW is in play if they hit cache weirdness.

Default-off is the load-bearing choice: every other app — Gitcoin Brain, Unforced Brain, any future custom UI that doesn't need offline — inherits the no-SW path. The caching-frustration default-on disappears.

**Dev mode: `parachute-app dev <name>`.**

For iterative development, a built-in dev mode that explicitly disables caching for the named UI and broadcasts a refresh signal when the bundle changes.

- `parachute-app dev <name>` puts the named UI into dev mode. The daemon overrides production cache headers for that UI with `Cache-Control: no-cache, no-store, must-revalidate` on **every** response (including hashed assets — dev mode trumps the immutable default).
- App opens a Server-Sent Events stream at `/app/<name>/_dev/reload`. The UI's index.html, when dev mode is active, gets a small injected `<script>` that listens to this stream and reloads the tab on a `reload` event.
- App watches the UI's source directory (configurable via meta.json `dev_watch_dir`, defaults to the dist's parent). On any file change, app waits 200ms (debounce), then emits a `reload` event on the SSE stream. (Phase 2: auto-rerun the UI's `dev_build_cmd` before the reload event.)
- `parachute-app dev --off <name>` exits dev mode and restores production cache headers.

The MVP operator flow:

```
1. parachute-app dev notes        # puts /app/notes into dev mode
2. Open browser; hard-reload once to clear the prior bundle
3. Edit notes source
4. cd ~/parachute-notes && bun run build
5. The browser tab auto-reloads via SSE; new code is visible
```

In Phase 2, step 4 disappears — `dev_build_cmd` in meta.json runs the build automatically on file change.

**Why SSE + manual build at MVP, not a full HMR setup.** Hot module replacement is per-build-tool (Vite's HMR ≠ Webpack's ≠ Parcel's), needs deep integration with each, and most usefully runs inside the UI's own dev server (Vite's `bun run dev`). App's job is to host the production bundle; matching that with a full HMR shim is out of scope. The SSE + manual build pattern is the lowest-common-denominator solution that works for every build tool, vanilla JS included.

**meta.json extensions for dev mode:**

```json
{
  "dev_watch_dir": "../src",          // path relative to dist/, watched for changes in dev mode
  "dev_build_cmd": ["bun", "run", "build"]  // Phase 2: ran in the UI's source dir on file change
}
```

Both optional. If not declared, dev mode falls back to watching the dist directory itself (still useful — operator builds manually, browser still reloads).

**Cross-reference:** [parachute-notes#151](https://github.com/ParachuteComputer/parachute-notes/issues/151) is the dev-rebuild ergonomics issue this section closes at the platform level. Once Notes migrates to app (section 16), notes-ui inherits this dev mode and the original frustration is gone.

### 19. Open questions (resolution status)

Captured from the original design pass; updated with what's been resolved during the review.

1. **App's services.json `paths` array growing dynamically — does hub's longest-prefix routing handle this cleanly?** **✓ Resolved — hub already reads services.json per-request.** Verified by reading `parachute-hub/src/services-manifest.ts` (post-PR #292, merged 2026-05-21): there is no in-memory cache, no mtime watcher needed; every hub request that touches the manifest re-reads it from disk. App's runtime writes to services.json on UI add/remove/reload will be visible on the next hub request without a restart. (Hub#311, formerly tracked as a prerequisite, was closed as resolved-by-#292 — #292 stamped `installDir` on services.json rows in the API install path, which fixed the install-doesn't-show-in-discovery symptom that motivated #311.) The hierarchical `uis` schema extension (section 12) is the remaining hub-side work, tracked separately.

2. **Per-UI `uiUrl` propagation into hub's discovery page.** **✓ Resolved via hierarchical services.json (section 12).** Each hosted UI surfaces as a sub-unit under app's row, carrying its own `displayName`, `tagline`, `iconUrl`, and `path`. Hub renders sub-units as their own discovery tiles. This mirrors what vault should grow into; for now, vault keeps its flat shape and app pioneers the hierarchical surface.

3. **Should app own the OAuth DCR registration, or should hub own it on app's behalf?** **✓ Resolved: app-direct.** App calls hub's standard `/oauth/register` endpoint (RFC 7591 DCR) on `add`. Hub already has DCR machinery for Notes' install path; app reuses it. The trust boundary is fine — DCR is a public endpoint by design, and same-hub auto-trust (section 6) makes the registration step low-friction. Hub-mediated DCR would be a Phase 2 refactor if the trust boundary later feels uncomfortable; not needed at MVP.

4. **Per-UI scope inheritance / operator override.** **✓ Partially resolved.** meta.json declares scope **shape** (wildcard `vault:*:read` vs concrete `vault:gitcoin:read`). For multi-vault UIs, the UI handles vault selection in-app via a picker — the OAuth flow per vault-pick narrows the wildcard to a concrete name. Operators don't need to override `meta.scopes_required` for the vault-binding case (UI handles it). What remains open: operators wanting to **widen or narrow** the declared shape at install (e.g., "this Notes install only gets `vault:gitcoin:*`, never the rest"). MVP: no operator override of declared shape; if real need surfaces, add `--scopes` CLI flag at Phase 2.

5. **Storage of OAuth client secrets.** **Open.** Public OAuth clients with PKCE don't have a secret, so MVP is moot — all app-hosted UIs are public clients. If a future UI registers as a confidential client (for some server-side OAuth callback flow), app would need to store the secret encrypted. **MVP: public clients only.**

6. **Per-UI access logging.** **Open.** Each UI is a static bundle with no server-side; logging happens in the browser. App logs request-level (which UI was hit, which path, response code) to its own stdout at MVP. Per-user attribution requires reading the hub-issued bearer's `sub` claim, which app doesn't do today. **Phase 2 addition** if operators want it — naturally fits with the richer admin SPA work in Phase 2.

7. **App's own admin SPA — is it shipped with app, or is it a hosted-UI of itself?** **✓ Resolved: NOT dogfood.** Per section 7, app's admin SPA is a Vite + React bundle shipped inside `@openparachute/app`, mounted at `/app/admin/` as a known fixed path. Aaron explicitly rejected the dogfood approach as "too messy" — recursive special-casing for marginal elegance. The admin SPA is distinct from user-added apps under `/app/<name>/`.

8. **Notes-as-app vs notes-module — does Notes stay as its own module or migrate to app?** **✓ Resolved: Notes migrates to app over 4 phases.** Section 16 captures the full arc. Phase 1 ships `@openparachute/notes-ui` alongside the existing `@openparachute/notes` module; Phase 2 deprecates the module form; Phase 3 retires it; Phase 4 cleans up. The committed-core line becomes vault + app + scribe + hub; Notes is the canonical first app installed under parachute-app. Aaron's framing: "app is replacing notes."

9. **Dev-rebuild ergonomics — how does the platform absorb the SW-caches-stale-code frustration that's recurred during Notes dev?** **✓ Resolved at the platform level (section 18).** Three pieces: (a) no-SW default — apps ship without a service worker, smart cache headers on `index.html` (no-cache) vs hashed assets (immutable); (b) opt-in PWA via meta.json `"pwa": true` — only apps that genuinely need offline-first carry the SW caching burden, and they own their SW lifecycle (skipWaiting, controllerchange); (c) `parachute-app dev <name>` dev mode — disables caching for the named UI, SSE live-reload signals connected browser tabs on file change. Phase 2 folds auto-rebuild via `dev_build_cmd`. Closes [parachute-notes#151](https://github.com/ParachuteComputer/parachute-notes/issues/151) at the platform level.

## What's new vs the Gitcoin Brain UI today

For readers familiar with the current Gitcoin Brain UI (deployed at `unforced-dev.github.io`):

| Aspect | Today | App-hosted |
|---|---|---|
| Hosting | GitHub Pages (external) | Parachute hub origin |
| Vault discovery | Operator pastes vault URL on first visit | Service catalog from hub-issued token |
| Auth | Operator pastes `pvt_*` token | OAuth-against-hub with PKCE + same-hub auto-trust (no consent screen for non-admin scopes) |
| Bundle update | Push to GitHub, Pages rebuilds | `parachute-app reload gitcoin-brain` after rebuild |
| Discovery | URL passed person-to-person | Hub discovery tile, alongside Notes / Vault / etc. |
| Multiple installs | Each user runs against own vault | Each operator has their own app install with their own UIs |
| Token storage | localStorage in browser | OAuth refresh tokens managed by hub; UI holds short-lived access tokens |

The current UI works; app makes it ecosystem-native. Same shape, same UX intent, ecosystem-shaped integration.

## Why the architecture is right

Three equivalences make this small primitive load-bearing:

**The runner equivalence.** parachute-runner is the supervisor for vault job-notes; parachute-app is the supervisor for UI bundles. Same shape (one daemon, N discovered units, lightweight per-unit registration), same audience (owner-operated, flat trust gradient), same module-protocol surface. Two supervisors on the same pattern means future supervisors (parachute-feeds for RSS sources? parachute-bots for chat agents?) inherit the conceptual model for free.

**The vault equivalence.** parachute-vault (singular module) hosts many vault instances; parachute-app (singular module) hosts many app instances. Same hierarchical discovery shape — module-level row in services.json, per-instance sub-units. App pioneers the hierarchical `uis` shape in services.json; vault adopts it in a follow-up. The ecosystem ends up with a consistent module-hosts-many-instances story.

**The trust-gradient equivalence.** App is explicitly flat-gradient. The operator chose every UI in `uis/`; the operator owns the vault; there's nothing to sandbox from. Same-hub auto-trust generalizes this — installed apps are trusted apps. The consent screen disappears for the common case because the install IS the consent. When multi-tenant cloud arrives, app in cloud-mode is one of the things that needs to change shape (per-tenant origin, per-UI sandboxing, consent screens back) — and that's a parachute-cloud problem, not an app problem.

**The Notes-as-first-app proof.** Notes migrating to app (section 16) is the proof-of-pattern for the whole architecture. If the canonical first-party UI — the one with the deepest cross-cutting integration, the longest history as own-module, the highest bar to clear — can be an app, the bar for graduating any other UI to its own module gets meaningfully higher. The committed-core line shifts from vault + notes + scribe + hub to vault + app + scribe + hub. App absorbs Notes; everything downstream inherits the absorption.

App is small on purpose. The supervisor + meta.json + DCR-on-add machinery is maybe ~500 lines of TypeScript plus the standard module-protocol scaffolding. The complexity it absorbs (per-UI hosting ceremony, OAuth boilerplate, discovery integration, dev-rebuild ergonomics, PWA-mode opt-in) is real; the complexity it adds is small. Keeping it small is the design.
