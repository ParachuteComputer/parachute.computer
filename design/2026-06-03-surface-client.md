---
title: "surface-client — make custom surfaces a thin import (rendering layer + client polish)"
description: "Today an external developer who wants a custom Parachute surface either re-implements OAuth + vault REST + token storage from scratch (my-vault-ui hand-rolled ~1,300 lines) or vendors notes-ui's entire rendering stack. `@openparachute/surface-client` already ships the auth + data layer (OAuth/PKCE/DCR, VaultClient, token storage, runtime-tenancy helpers) and is dogfooded by notes-ui — but it owns no rendering, no core types, no quick-start, and its README still names a package that no longer exists. This doc plans the polish that makes `import` beat `copy`, and proposes a sibling `@openparachute/surface-render` for the markdown + wikilink + embed + multi-format rendering layer that is the single biggest gap."
---
# surface-client — make custom surfaces a thin import

**Date:** 2026-06-03
**Status:** Proposed. Design-review artifact — the architectural decisions (A–D) the owner blesses **before any code lands**. No code ships with this PR. The `parachute-patterns/migrations/2026-06-03-surface-client.md` propagation checklist lands with **Phase 1**, not with this design PR.

**Companions:**
- [`2026-05-21-parachute-apps-design.md`](./2026-05-21-parachute-apps-design.md) — the surface-host design; §16 is the notes-ui-as-app migration arc that produced surface-client (referenced from `surface-client/src/index.ts:11`)
- [`2026-04-20-module-architecture.md`](./2026-04-20-module-architecture.md) — module protocol (well-known, services.json, surfaces) the hosted path discovers from
- [`../../parachute-patterns/patterns/runtime-tenancy-contract.md`](../../parachute-patterns/patterns/runtime-tenancy-contract.md) — the `<meta>`-tag contract `mount.ts` reads (the host-injected runtime tenancy that hosted surfaces depend on; standalone surfaces *don't* get it — §3 D-tenancy)
- [`../../parachute-patterns/patterns/surface-bundle-shape.md`](../../parachute-patterns/patterns/surface-bundle-shape.md) — what a hosted frontend bundle ships
- [`../../parachute-patterns/patterns/oauth-scopes.md`](../../parachute-patterns/patterns/oauth-scopes.md) + [`hub-as-issuer.md`](../../parachute-patterns/patterns/hub-as-issuer.md) — the OAuth surface `ParachuteOAuth` drives
- [`../onboarding/surface-build.md`](../onboarding/surface-build.md) — the "build a custom UI for your vault" starter prompt this work upgrades from "hit the raw HTTP API" to "import surface-client"
- [`../../parachute-patterns/patterns/governance.md`](../../parachute-patterns/patterns/governance.md) — RC versioning + reviewer-gated PR discipline the phasing follows

> **Grounding note.** This doc was written against the real source at `main`: `parachute-app/packages/surface-client/`, `parachute-app/packages/notes-ui/`, and the external adopter at `~/Code/my-vault-ui`. Every export name, file path, and interface shape below was read, not assumed. Where the brief that seeded this doc differed from the code, this doc follows the code and flags the difference in §10.

---

## 1. Problem

A developer who wants a custom surface over their Parachute vault — a daily-capture inbox, a project dashboard, a graph explorer — has two paths today, and **both are bad**:

1. **Re-implement everything.** The real external adopter `~/Code/my-vault-ui` (Vite/React, GitHub Pages) uses **no Parachute packages**. It hand-rolled OAuth (`src/vault/oauth.ts`, 413 lines, its own header: *"Ported from Parachute Notes / surface-client … collapsed into one self-contained module — no npm oauth dependency"*), the vault client (`src/vault/api.ts`, 552 lines), `pkce.ts`, `config.ts`, redeclared every core type (`src/vault/types.ts`, 127 lines — `Note`, `NoteRef`, `NoteMetadata`, `TagRecord`, …), markdown + wikilink rendering (`src/components/Markdown.tsx`), and the auth'd blob → `<audio>` embed path (`src/components/AudioEmbed.tsx`). That is ~1,300 lines of generic Parachute plumbing the developer should never have written.

2. **Vendor notes-ui.** The starter prompt (`onboarding/surface-build.md:37`) points developers at notes-ui as a reference — full CRUD, OAuth, PWA, multi-vault. It is "probably more than I need" (the prompt says so itself) and there is no clean way to take *just the rendering* without copying files.

The thing is, **the auth + data layer already exists and is good.** `@openparachute/surface-client` (v0.1.0, published, at `parachute-app/packages/surface-client`) ships:

- **OAuth** — `ParachuteOAuth` (PKCE + DCR + same-hub auto-trust), `discoverAuthServer` / `registerClient` (`src/oauth.ts`, `pkce.ts`, `discovery.ts`).
- **`VaultClient`** — queries/CRUD/tags/attachments + a typed error hierarchy (`VaultError` → `VaultAuthError` → `VaultPermissionError`, `VaultNotFoundError`, `VaultUnreachableError` → `VaultServerError`, `VaultConflictError`, `VaultTargetExistsError`, `VaultUploadError`) (`src/vault-client.ts`).
- **Token storage** (`src/token-storage.ts`), **runtime-tenancy helpers** (`src/mount.ts`: `getMountBase` / `getTenantId` / `getHubOrigin` / `getVaultUrl`), **vault-id** + **sw-reload** helpers, and the core **vault types** (`src/vault-types.ts`).
- Subpath exports (`./oauth`, `./vault-client`, `./mount`, …) for tree-shaking.

And it is **dogfooded**: notes-ui depends on `@openparachute/surface-client` (`notes-ui/package.json`), wraps its OAuth (notes-ui keeps a thin `discovery.ts` shim that delegates to surface-client and pins `client_name: "Parachute Notes"`), and extends `VaultClient` for tag-rename/merge/delete + `fetchAttachmentBlob`.

So the auth + data half is real. **The gaps are four:**

1. **Rendering lives nowhere shareable.** notes-ui owns the *entire* rendering stack and surface-client owns *none of it*: `components/MarkdownView.tsx` (react-markdown + remark-gfm + a local `remark-wikilinks` + rehype-highlight), `lib/markdown/remark-wikilinks.ts` (parses `[[x]]`, takes a `resolve` callback → resolved/unresolved classes), `components/VaultImage.tsx` (auth'd blob fetch for `/api/storage/` URLs — the embed-render path), `components/render/{Csv,Json,Yaml,Code,Plain}Renderer.tsx`, and the format dispatcher `lib/render/format.ts` + `NoteRenderer.tsx`. my-vault-ui re-built all of this from scratch (`Markdown.tsx`, `AudioEmbed.tsx`). This is the **single biggest gap** — and the one with the most copy-paste blast radius.

2. **No quick-start.** Both adopters wrote ~20 lines of OAuth/VaultClient boilerplate (the four-step dance in the README's "OAuth quick-start"). There is no sane-defaults factory for the common case (single vault, hub = origin, default redirect).

3. **Core types aren't reached for.** my-vault-ui redeclared `Note`/`NoteRef`/metadata/`TagRecord` rather than importing `surface-client`'s `vault-types.ts`. The types are exported; nobody outside the dogfood knows.

4. **The package lies about its own name.** `surface-client/README.md` still says `# @openparachute/app-client` and imports `from "@openparachute/app-client"` throughout — a package name that **does not exist** (the package is `@openparachute/surface-client`, renamed when parachute-app → parachute-surface, 2026-05-27). A developer who copies the README's import string gets an install failure. There's a smaller drift too: `index.ts:130` hard-codes `APP_CLIENT_VERSION = "0.1.0-rc.4"` while `package.json` says `0.1.0`.

The decision: **polish surface-client so `import` beats `copy` for the auth/data/types/quick-start layer, and extract the rendering stack into a sibling package so a custom surface is a thin consumer instead of a fork.** The proof is migrating notes-ui onto the extracted rendering (it becomes a thin consumer + kills its `discovery.ts` duplicate) and adopting both packages in my-vault-ui (deleting its ~1,300 hand-rolled lines).

---

## 2. Current state (what ships, what's duplicated)

| Concern | Where it lives today | Shareable? |
|---|---|---|
| OAuth (PKCE/DCR/discovery/refresh) | `surface-client/src/oauth.ts`, `pkce.ts`, `discovery.ts` | **Yes** — exported, dogfooded by notes-ui |
| Vault REST + typed errors | `surface-client/src/vault-client.ts` | **Yes** — exported, extended by notes-ui |
| Token storage | `surface-client/src/token-storage.ts` | **Yes** — exported |
| Runtime tenancy (`<meta>` readers) | `surface-client/src/mount.ts` | **Yes** — exported; **hosted-only** (standalone surfaces have no host to inject the tags — §3) |
| Core vault types | `surface-client/src/vault-types.ts` | **Yes** — exported; **not reached for** (my-vault-ui redeclared) |
| Quick-start / sane-defaults factory | — | **No** — both adopters wrote boilerplate |
| Markdown render + wikilinks + embeds | `notes-ui/src/components/MarkdownView.tsx` + `lib/markdown/remark-wikilinks.ts` + `VaultImage.tsx`; my-vault-ui's `Markdown.tsx` + `AudioEmbed.tsx` | **No** — duplicated, drifted |
| Multi-format renderers (csv/json/yaml/code/plain) | `notes-ui/src/components/render/*` + `lib/render/format.ts` + `NoteRenderer.tsx` | **No** — notes-ui-only |
| MDX | — | **No** — not a first-class format anywhere |

**The `discovery.ts` duplication is real but already half-resolved.** notes-ui's `src/lib/vault/discovery.ts` is **not** a verbatim copy — it is a *thin shim* that imports `discoverAuthServer` / `registerClient` from `@openparachute/surface-client` and re-exports them, pinning `client_name: "Parachute Notes"` so call sites don't plumb the brand string. So the "dedup discovery" task is narrower than "two full implementations": it's "confirm the shim adds only the brand-pin (it does) and decide whether the brand-pin belongs in the quick-start factory (§4) instead of a per-surface shim." notes-ui also keeps `src/lib/vault/hub-discovery.ts` (a *different* concern — hub-origin/service-catalog discovery, not AS-metadata) which is **not** a surface-client duplicate and stays put.

**`fetchAttachmentBlob` is already on `VaultClient`.** The brief implied notes-ui adds it as an extension; in the current code it's a base-class method (`vault-client.ts`) plus a `storageUrl()` helper. The embed renderer (`VaultImage`) calls `client.fetchAttachmentBlob(src)`. So the auth'd-blob primitive the rendering layer needs is already in surface-client — the rendering package consumes it rather than re-implementing it.

---

## 3. The standalone-vs-hosted distinction (load-bearing)

This is the constraint that shapes the whole design, and the brief understated it. There are **two deployment shapes** for a surface, and they differ in exactly one place — **how OAuth bootstraps**:

**Hosted surface** (notes-ui under the surface host). The host serves the bundle under `/surface/<name>/`, injects the runtime-tenancy `<meta>` tags (`mount.ts` reads them), and exposes a per-surface OAuth-client endpoint. `ParachuteOAuth.getClientId()` (`oauth.ts:215`) fetches `${hubUrl}/surface/${appName}/oauth-client` to learn its `client_id`. **This endpoint only exists for surfaces the host knows about.**

**Standalone surface** (my-vault-ui on GitHub Pages). There is **no host**, no injected meta tags, and **no `/surface/<name>/oauth-client` endpoint**. So `getClientId()`'s hosted path is unavailable. my-vault-ui therefore does **RFC 7591 Dynamic Client Registration directly** against the hub's `registration_endpoint` — exactly what `discovery.ts`'s `registerClient` already does. It registers itself as a public client at runtime, with its GitHub Pages URL as the redirect URI.

The implication for the quick-start factory (§4): **it must support both bootstraps.** A hosted surface gets its client_id from the host endpoint; a standalone surface self-registers via DCR. `ParachuteOAuth` already has both primitives (`getClientId` for hosted, `registerClient` for DCR) — the factory just has to pick the right one (or let the caller pick) and stop assuming the host endpoint exists. **This is why the README's quick-start (which leads with `getClientId()`) is misleading for the standalone audience the onboarding prompt targets.**

A second implication for tenancy: `mount.ts`'s `<meta>`-tag readers return `null` off-host (no host injected them). That is *by design* (`mount.ts` is documented to never throw and to let callers choose fallbacks) — but it means the **runtime-tenancy contract is a hosted-surface feature**, and standalone surfaces configure their vault URL + hub origin explicitly (paste-in screen or build-time config, as my-vault-ui does in `src/vault/config.ts`). The docs must say this plainly so a standalone developer doesn't reach for `getVaultUrl()` and get `null`.

---

## 4. Goals

1. **Importing beats copying for auth/data/types.** A standalone developer writes a few lines, not ~1,300.
2. **A shareable rendering layer** with good defaults + per-surface override hooks (resolver, link component, custom per-type renderers), shipping *primitives, not opinionated app components*.
3. **notes-ui and my-vault-ui both become thin consumers** — the dogfood (notes-ui) and the real-world proof (my-vault-ui).
4. **The starter prompt upgrades** from "hit the raw HTTP API / token-paste" to "import `@openparachute/surface-client` (+ `surface-render`)."
5. **No regressions** to the hosted notes-ui path, which is live and dogfooded.

Non-goal: a turnkey app shell. See §9 (out of scope) and decision **C**.

---

## 5. Design decisions

### A — Rendering home: a **sibling `@openparachute/surface-render` package**, not a `surface-client/render` subpath

**Recommendation: ship rendering as a sibling package `@openparachute/surface-render` that depends on `@openparachute/surface-client` for types.**

The forces:

- **The core client is framework-agnostic.** `oauth.ts`, `vault-client.ts`, `token-storage.ts`, `pkce.ts`, `discovery.ts`, `mount.ts`, `vault-types.ts` import **no React**. A headless surface (a CLI, a Node sync job, a Svelte/Vue surface) can depend on surface-client today with zero React in its tree. The package's whole value for non-React consumers is that it's just fetch + types.
- **Rendering is React.** The proven stack is react-markdown + remark/rehype plugins + React components (`VaultImage`, the per-format renderers). Bolting it onto surface-client as a `./render` subpath would add `react`, `react-markdown`, `remark-gfm`, `rehype-highlight` (and, with decision B, an MDX runtime) as **peer dependencies of the client**. Even though a subpath is tree-shakeable, the *peer-dependency declaration* and the *type surface* leak React into every consumer's resolution. A Svelte surface that wants `VaultClient` should not have to satisfy a React peer range.
- **A sibling keeps the seam honest.** `@openparachute/surface-render` declares `react` + the markdown stack as peers, depends on `@openparachute/surface-client` for `Note` / `NoteAttachment` types and the `VaultClient` interface (for `fetchAttachmentBlob`), and is imported only by React surfaces. The client stays clean; React surfaces add rendering on top.

**Honest case for the subpath alternative:** one package, one version to track, one install. The render code is small. ESM subpath exports + a `react` peer marked optional would tree-shake out for non-React consumers in practice. If the owner judges that *every realistic surface is React* and a second package is overhead, the subpath is defensible — but it permanently couples the framework-agnostic core to a React peer range, and "every surface is React" is exactly the assumption a platform shouldn't bake in. **Recommendation stands: sibling package.**

**Package shape (`@openparachute/surface-render`):**

```
@openparachute/surface-render
  .                      → barrel
  ./markdown             → <MarkdownView>, remarkWikilinks plugin, the resolver/link hooks
  ./embed                → <VaultImage>, <VaultAudio> (auth'd /api/storage blob → <img>/<audio>)
  ./formats              → <CsvRenderer> <JsonRenderer> <YamlRenderer> <CodeRenderer> <PlainRenderer>
  ./note                 → <NoteRenderer> (the format dispatcher) + formatForPath
peerDependencies: react, react-dom, react-markdown, remark-gfm, rehype-highlight (+ MDX runtime per B)
dependencies: @openparachute/surface-client (types only)
```

### B — MDX safety: **render-as-markdown by default, opt-in sandboxed component evaluation**

MDX is requested as a new first-class format. **MDX executes JSX — rendering arbitrary vault MDX is a code-execution surface.** A vault is a trust boundary the operator controls, but a surface may render notes authored by a runner job, an import, a shared multi-user vault, or a synced repo — not all of which the *viewer* authored. Evaluating arbitrary MDX components in the viewer's browser is a self-XSS-class hazard.

**Recommendation (a security decision the owner must bless):**

- **Default: MDX renders as Markdown.** `.mdx` files go through the same `MarkdownView` path as `.md` (remark/rehype, wikilinks, GFM). JSX expressions are **not** evaluated; component tags render inert or are stripped. This is safe-by-default and matches the current `format.ts` behavior, which already maps `.mdx` → `markdown` (`format.ts:33`). Nothing regresses.
- **Opt-in: a `components` allowlist.** A surface that *wants* live MDX passes an explicit allowlist of components to a `<MdxView components={{...}} allowExpressions={false}>` — only allowlisted tags evaluate; arbitrary imports and bare expressions stay disabled unless the surface explicitly opts into `allowExpressions`. The surface author takes on the trust decision deliberately, in their own code, not by default.
- **Flag loudly in docs + types:** the opt-in path is documented as "you are evaluating note content as code; only do this for vaults whose authorship you trust."

**Owner call:** bless safe-default-as-markdown + opt-in allowlisted components? Or defer MDX-as-code entirely (markdown-only) until there's a concrete demand?

### C — Default experience vs flexibility: **primitives + good defaults + hooks; NOT a turnkey app shell**

**Recommendation: ship primitives with good defaults and per-surface override hooks. Do not ship an app shell.**

What this means concretely:

- **In:** the render primitives (A), the quick-start auth factory (below), core types, the tenancy readers. Each works out-of-the-box with defaults and accepts overrides.
- **Explicitly out (domain-owned, never in the shared packages):** routing, app chrome/navigation, the proposal-review forms and entity cards in my-vault-ui, my-vault-ui's entity-folder conventions / `proposalSpec` parser / capture model, notes-ui's PWA shell / quick-switch / sync panel. These are app-domain. The line: **surface-client + surface-render own "talk to a vault and render a note"; the surface owns "what this app is."**

This is why the wikilink resolver is a *hook*, not a baked behavior (decision D) — notes routes wikilinks to `/n/<id>`, my-vault-ui routes them to entity paths via its own `EntityIndex`. The shared layer must not pick one.

**The quick-start factory (the "good defaults" for auth), in surface-client:**

```ts
// @openparachute/surface-client — new
export interface CreateVaultSurfaceOpts {
  hubUrl?: string;              // default: window.location.origin
  clientName: string;          // shown on the hub consent screen (REQUIRED — no sane default)
  vaultName?: string;          // default: "default"
  redirectUri?: string;        // default: `${origin}${mount}/oauth/callback` (hosted) or `${origin}/oauth/callback` (standalone)
  bootstrap?: "hosted" | "dcr"; // default: auto — "hosted" if a parachute-mount meta tag is present, else "dcr"
}

export interface VaultSurface {
  oauth: ParachuteOAuth;
  login(): Promise<void>;           // beginFlow + navigate
  handleCallback(): Promise<void>;  // parse code/state from window.location, exchange
  getClient(): VaultClient | null;  // a VaultClient wired with auto-refresh-on-401, or null if not authed
  logout(): void;
}

export function createVaultSurface(opts: CreateVaultSurfaceOpts): VaultSurface;
```

`createVaultSurface` collapses the README's 4-step dance into one call, auto-detects hosted-vs-standalone (the §3 distinction) from the presence of the `parachute-mount` meta tag, runs DCR for standalone, and wires the `VaultClient`'s `onAuthError` refresh loop that both adopters wrote by hand. The brand-pin notes-ui's `discovery.ts` shim exists for becomes `clientName` here — folding the §2 shim concern into the factory.

### D — Wikilink resolution contract: a **per-surface resolver hook** returning `{ href, exists }`

**Recommendation: define the resolver as `(target: string) => { href: string; exists: boolean } | null`, decided per-surface, with a separate link-component hook for navigation.**

The two adopters resolve wikilinks to **different URL spaces**, which is exactly why the shared layer cannot bake one in:

- notes-ui: resolves to `/n/<id>` (its `remark-wikilinks.ts` builds the href itself from a `{ id } | null` resolver and a React Router `<Link>`).
- my-vault-ui: resolves to entity paths via its own `EntityIndex.resolve()` + `entityHref()`, and renders unresolved links as inert `<span class="wikilink-dead">`.

**Correction to the brief (and to today's notes-ui code):** the *current* notes-ui `WikilinkResolver` is `(target) => { id: string } | null` and the **plugin** builds the `/n/<id>` href — so the href space is hard-coded inside the shared-candidate plugin. That's the wrong seam: it forces every consumer into `/n/<id>`. The **proposed** contract moves href-construction to the surface:

```ts
// @openparachute/surface-render/markdown
export interface WikilinkTarget {
  href: string;     // surface-chosen: "/n/<id>" (notes), "/entity/<slug>" (my-vault-ui), …
  exists: boolean;  // drives resolved vs unresolved styling
}
export type WikilinkResolver = (target: string) => WikilinkTarget | null;
// null === "I can't resolve this; render the dashed-underline unresolved affordance"
```

The plugin parses `[[target]]` / `[[target|alias]]`, calls the resolver, and emits a link node carrying `className: "wikilink wikilink-resolved" | "wikilink wikilink-unresolved"` + `data-wikilink-target` + the surface-chosen href (matching the class contract notes-ui's `MarkdownView` already styles against). A separate **link-component hook** (`linkComponent?: React.ComponentType<{href; className; children}>`, default a plain `<a>`) lets a surface inject React Router's `<Link>` without the plugin importing a router.

**Embed (`![[…]]`) vs link (`[[…]]`) — tie to the Obsidian-import work.** The brief asked to handle both. The code reality:

- notes-ui's `remark-wikilinks` handles **only** `[[…]]` links. Embeds (`![[…]]`) are **not** handled by the wikilink plugin — they arrive as standard markdown images `![](/api/storage/…)` because the **Obsidian import already rewrote** `![[file]]` embeds to `/api/storage/` image syntax (the [Obsidian-parser-convergence work](../../parachute-patterns/) — imported embeds were rewritten to `![](/api/storage/…)`). notes-ui then renders those via the `img` component override → `VaultImage` (auth'd blob fetch).
- my-vault-ui takes the *other* approach: it **strips** `![[…]]` embeds in `Markdown.tsx` and renders audio separately via `AudioEmbed` keyed off the note's attachment list.

So the shared rendering layer must be **consistent with the import's rewrite**: the canonical embed path is `![](/api/storage/…)` → `<VaultImage>` / `<VaultAudio>` (auth'd blob), and the wikilink plugin owns only `[[…]]` links. A surface that still has raw `![[…]]` embeds (un-imported, hand-authored) can opt into an **embed-resolver** hook (symmetric to the link resolver) that maps an embed target to a storage URL — but the *default* assumes the import-rewritten `![](/api/storage/…)` shape, because that's what vault content actually contains post-import. This keeps the renderer's embed handling and the importer's rewrite as **two ends of one contract**, not two guesses.

---

## 6. Phased plan

Independently-shippable, reviewer-gated PRs (governance rule 1 + mandatory reviewer dispatch). Code-touching PRs bump `rc.N` per governance rule 2; the parachute.computer doc PRs skip rc per the doc-only exemption. The `parachute-patterns/migrations/2026-06-03-surface-client.md` propagation checklist lands with **Phase 1**.

| Phase | Scope | Repo(s) | Shippable? |
|---|---|---|---|
| **1. Client polish + docs truth** | Fix README package name (`app-client` → `surface-client`) + the `APP_CLIENT_VERSION` drift; document the hosted-vs-standalone bootstrap (§3) + the runtime-tenancy contract + fallbacks; add an error-handling guide (the typed `VaultError` hierarchy → UI affordances); ship `examples/` minimal standalone SPA; confirm/retire the notes-ui `discovery.ts` shim relative to the new factory. Ship the migration checklist. | surface-client | Yes (additive + docs) |
| **2. Quick-start factory** | `createVaultSurface` (§5C) with hosted/standalone auto-detect + DCR + auto-refresh `VaultClient`. Re-export core types prominently; add a "don't redeclare these" doc note. | surface-client | Yes (additive) |
| **3. Extract `@openparachute/surface-render`** | New sibling package: `<MarkdownView>` + the `remarkWikilinks` plugin with the **new `{href, exists}` resolver + link-component hook** (D); `<VaultImage>` + `<VaultAudio>` embed primitives; the csv/json/yaml/code/plain renderers + `<NoteRenderer>` dispatcher + `formatForPath`; MDX safe-default (B). Peers: react + markdown stack; deps: surface-client (types). | new repo path under parachute-surface `packages/surface-render` | Yes (new package; nothing consumes it yet) |
| **4. Migrate notes-ui onto surface-render** | Replace notes-ui's `MarkdownView` / `remark-wikilinks` / `VaultImage` / `components/render/*` / `NoteRenderer` / `format.ts` with imports from `@openparachute/surface-render`. notes-ui's resolver returns `{href: "/n/<id>", exists}` + passes React Router `<Link>` as `linkComponent`. Kills the local rendering stack; confirms the hooks fit the dogfood. | parachute-surface (notes-ui) | Yes (after 3) — the dogfood gate |
| **5. Adopt both packages in my-vault-ui** | Replace my-vault-ui's hand-rolled `oauth.ts` / `api.ts` / `pkce.ts` / `types.ts` with `createVaultSurface` + `VaultClient` + core types; replace `Markdown.tsx` / `AudioEmbed.tsx` with `surface-render`. Keep app-domain code (`EntityIndex`, `proposalSpec`, capture model, routes). The real-world proof. | external (`~/Code/my-vault-ui`) | Yes (after 3+4) |
| **6. Upgrade the starter prompt + onboarding** | Rewrite `onboarding/surface-build.md` from "hit the raw HTTP API / token-paste" to "import `@openparachute/surface-client` (+ `surface-render`)"; point at the `examples/` SPA; keep the token-paste fallback documented for the truly-minimal case. | parachute.computer | Yes (docs-only) |

**Why notes-ui (Phase 4) before my-vault-ui (Phase 5):** notes-ui is in-tree and dogfooded — if the extracted hooks don't fit the live PWA, that's caught before an external repo adopts them. The dogfood is the gate on the hook design.

---

## 7. Adoption + dogfood

The credibility of this plan is the two migrations, in order:

1. **notes-ui (in-tree dogfood, Phase 4).** Success = notes-ui renders identically after deleting its local rendering stack and importing `surface-render`, with its resolver returning `{href:"/n/<id>", exists}` and passing `<Link>` as `linkComponent`. Verifies: the `{href, exists}` resolver (D), the link-component hook (D), the `![](/api/storage/…)` → `VaultImage` embed path (D), the format dispatcher, MDX-as-markdown default (B). This is also where the `discovery.ts` shim is reconciled with `createVaultSurface`'s `clientName`.

2. **my-vault-ui (external proof, Phase 5).** Success = the ~1,300 hand-rolled lines (`oauth.ts` 413 + `api.ts` 552 + `pkce.ts` + `types.ts` 127 + `Markdown.tsx` 89 + `AudioEmbed.tsx` 79) collapse to imports, while its app-domain code (entity folders, proposal spec, capture model, routes) is untouched. This proves the standalone bootstrap (§3 DCR path) and the per-surface resolver (entity paths, not `/n/<id>`) actually generalize — the entire point of decision D.

3. **The starter prompt (Phase 6)** is the funnel: every future "build me a custom vault UI" session starts from the packages, not raw HTTP. The reference-implementation pointer to notes-ui stays, but the *default* path becomes the import.

---

## 8. Open questions

- **A (render home)** — sibling `@openparachute/surface-render` (recommended) vs `surface-client/render` subpath. *Lean: sibling.* Owner call.
- **B (MDX safety)** — bless safe-default-as-markdown + opt-in allowlisted components (recommended), or defer MDX-as-code entirely until concrete demand? Security decision; owner must bless.
- **C (scope)** — confirm primitives-not-shell, and confirm the out-of-scope list (§9) is the right line.
- **D (resolver contract)** — bless the `(target) => {href, exists} | null` resolver + separate link-component hook + embed-resolver opt-in. Note this **changes** notes-ui's current `{id}`-returning resolver, which is the migration's first task.
- **Repo home for `surface-render`** — `parachute-surface/packages/surface-render` (alongside surface-client + notes-ui) is the natural home (consolidates "host module + bundled reference surfaces + shared client/render libs"). Confirm vs a separate repo.
- **Versioning the pair** — surface-client and surface-render version independently (render depends on a client semver range) vs lockstep. *Lean: independent, render pins a client `^range`.* Owner call.
- **`getVaultPath` vs `getVaultUrl` pattern drift** — `runtime-tenancy-contract.md` documents `getVaultPath` and a `parachute-tenant-id` meta tag, but the code exports `getVaultUrl` (no `getVaultPath`) and derives the tenant id from the mount path (no `parachute-tenant-id` tag read). Reconcile the pattern doc with the code as part of Phase 1's "document the tenancy contract."

---

## 9. Out of scope

The shared packages own "talk to a vault, render a note." They explicitly do **not** own:

- **Routing / app chrome / navigation** — each surface picks its own router and shell.
- **Domain conventions** — my-vault-ui's entity-folder layout, `proposalSpec` parser, capture/entity model; notes-ui's PWA shell, quick-switch, sync panel, neighborhood graph.
- **Opinionated app components** — proposal-review forms, entity cards, dashboards. Primitives only.
- **A turnkey "Parachute Surface SDK app"** — there is no generated app shell; the developer composes primitives.
- **Non-React rendering** — surface-render is React; a Svelte/Vue surface uses surface-client (framework-agnostic) for auth/data and renders markdown with its own ecosystem's tools. (This is *why* render is a sibling, not a client subpath — §5A.)
- **Server-side / headless rendering** — the render primitives are browser React components (auth'd blob fetch, object URLs). A headless consumer uses `VaultClient` + its own renderer.

---

## Appendix — the polish, concretely

The auth/data/types layer **already ships and is dogfooded**; the work is mostly *additive + extraction + truth-in-docs*, not new architecture:

- **(a)** Fix the README package name + version drift; document hosted-vs-standalone (§3) and the tenancy contract (Phase 1).
- **(b)** Add `createVaultSurface` (§5C) so the common case is one call, not 20 lines, with hosted/standalone auto-detect (Phase 2).
- **(c)** Extract the proven rendering stack (markdown + wikilinks + auth'd embeds + multi-format + MDX-safe-default) into `@openparachute/surface-render` with the per-surface resolver/link/embed hooks (D), then migrate notes-ui onto it (the dogfood gate) and my-vault-ui (the external proof) (Phases 3–5).
- **(d)** Repoint the starter prompt at the import (Phase 6).

The single biggest payoff — a custom surface being a thin consumer instead of a ~1,300-line fork — falls out of (b)+(c): once auth is one factory call and rendering is one package, "build me a custom vault UI" is composition, not re-implementation.
