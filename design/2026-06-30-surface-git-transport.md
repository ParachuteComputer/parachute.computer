# Surface Git Transport — vault-declared, git-transported, hub-authenticated surfaces

*Design doc — 2026-06-30. Status: DRAFT for review. Author: uni/session (with Aaron).*

## TL;DR

A surface should be **developed, lives, and serves entirely inside the parachute**, with GitHub as an *optional* backup — and an agent (or a human, or a standalone Claude Code session) should be able to ship to it by doing a plain **`git push`** that the **hub authenticates**. The transport is git; the auth authority is the hub; the surface is declared in the vault and served by surface-host.

Four layers, each doing what it's best at:

> **Vault *declares*** (a `#surface` note — mount, mode, source, scopes; low-churn metadata) · **Git *transports*** (versioned, content-addressed, delta-efficient movement) · **Hub *authenticates*** (issues + validates a `surface:<name>:push` scope; runs the authenticated git endpoint) · **surface-host *serves*** (receives the push event, builds/serves in its own trust boundary).

This resolves every constraint that the alternatives traded off (see §2), and it positions **git-as-transport as a reusable hub substrate primitive** — surfaces are the first consumer, but "hub-authenticated git" generalizes to any module that wants versioned, authenticated, file-shaped content movement.

---

## Decisions locked (Aaron, 2026-06-30)

These supersede the conflicting items in §11; the body below is aligned to them.

1. **No `source.kind` axis — git is simply how surfaces work.** A surface *is* a hub-transported git repo. Period. Mirroring to an external remote (GitHub) is a **separate, optional connection**, configured independently — exactly the parallel to vault history + the optional GitHub mirror. (Removes the §9 dial.)
2. **Scope vocabulary = read / write** (not "push"). `surface:<name>:read` (fetch/clone/pull) + `surface:<name>:write` (push) — matching GitHub's model, the vault `read/write/admin` ladder, and parachute's existing vocabulary. Better practice: name the *authority*, not the git verb. **Both read and write are supported** (clone + push). surface-host already declares `surface:read` — we add `surface:write`.
3. **The hub owns the git-transport substrate; the *surface* specifies it.** The hub provides the authenticated git primitive (endpoint, http-backend, bare repos, auth); surface-host + the `#surface` note **declare/configure** their use of it (which repo, which mount) — the substrate-provides / module-specifies seam. (Confirms §4's recommended split.)
4. **What goes over the wire is the SOURCE; surface-host compiles it.** The agent/human pushes source via git; the **surface module is responsible for building** it into the served bundle. *Security implication:* surface-host builds pushed source → it must build **in a sandbox** (the CI trust model — pushed source from an *authorized* writer, built without privileged host access), not as a privileged process. This is the cost of source-over-dist; mitigated by the sandbox + the operator-governed write grant. (Reverses the earlier "push dist" lean.)
   - **Sandbox phasing (decided 2026-06-30):** Phase 0b ships **Option A** — a constrained subprocess behind a swappable `BuildRunner` seam (`bun install --ignore-scripts`, scrubbed env [no hub secrets/operator token/PARACHUTE_*], HOME/TMPDIR redirected to a throwaway dir, process-group timeout, bounded output, non-root, fail-closed). Its residual (a malicious build can read absolute-path files the surface-host user can read, incl. the vault read cred — a `write`→`read-vault-cred` escalation) is **moot in Phase 0b** because the only writer is the operator, who already holds that cred. **Phase 0c** swaps in **Option B** — kernel confinement via `@anthropic-ai/sandbox-runtime` (the same Seatbelt/bubblewrap engine the agent uses; reuse the agent's Linux fixes) — and is a **HARD gate that MUST merge before Phase 2** (when non-operator agents/external clients can push, which is when the residual would matter). The `BuildRunner` seam makes 0c a pure swap.
5. **Confirmed:** (B) git-push-source · push **and** pull.

---

## 1. Motivation

The open question: **how does a surface's content get from where it's authored/built to where it's served** — such that it's:

- **self-contained** — no *required* external hop (no "bump up to GitHub and back down" just to move bytes between two places on one machine);
- **modular** — no shared-disk coupling (surfaces must survive the cloud/multi-container future, where the agent, surface-host, and vault may be separate containers);
- **low-churn** — iterating doesn't bloat a store that wasn't built for it;
- **versioned** — history + rollback;
- **authenticated** — scoped, governable access.

Every candidate is a different answer to "what's the *transport* and what's the *store*." Git wins on all five at once (§2), and the missing piece — auth — is something the hub already is.

---

## 2. The directions we considered (and why git)

| Direction | Transport / store | Verdict |
|---|---|---|
| **Vault-as-store** (zip attachment / source-as-notes) | vault blobs | Clean-feeling, *wrong material*. A dist is binary → every build is a fresh blob → the vault accretes artifact history it was never meant to hold. The vault is a knowledge graph, not a CDN. |
| **GitHub round-trip** (release artifact) | GitHub + CI | Fine as backup/mirror; *wrong as the primary loop*. Not self-contained; depends on an external service + CI to move bytes between two places on the same box. |
| **Content-addressed registry** (OCI / `oras`) | local registry | Same properties as git, more ceremony + another system to run. Git is content-addressed, versioned, authed, and *already everywhere*. |
| **Git-as-transport** ⭐ | git (local remote, hub-authed) | **Content-addressed → kills churn** (deltas, not zips). **Versioned for free** (history = version history; rollback = checkout). **Modular** (a push is a protocol boundary even on one machine). **Dev-native** (agents + humans already speak git). The only missing piece is auth — which is the hub's whole job. |

The bigger thing: *"if we start using git as how we move information around, with proper auth"* — that's a general primitive, not a surface feature. So we build it as **hub substrate** and prove it on surfaces.

---

## 3. The decisive fork: what does "push to a surface" mean?

Two genuinely different capabilities hide under "push to a surface." **State both; this doc is about (B).**

- **(A) Publish content the surface *renders*** (surface = a vault-consuming UI). This is ≈ `vault:<name>:write` and **already works end-to-end today** — a vault grant → minted JWT → MCP-server injection into the agent turn, no git involved. "Surface name" is sugar for "the backing vault + tag-scope." Near-zero new runtime. *If the need is "an agent writes notes a surface displays," it's already done.*
- **(B) `git push` to the surface's *source/deploy*** (ship code / a built static SPA — the parachute-brain-on-Pages, uni-evolve style: "an agent ships changes to a surface's repo"). **This is the real new work** and the subject of this doc: a `surface` grant kind, a hub git-transport substrate, and the runtime that wires a hub token into `git push`.

---

## 4. Architecture

```
   author (agent / human / standalone Claude Code)
        │  git push  (Authorization: Bearer <hub JWT, scope surface:<name>:push>)
        ▼
   ┌─────────────────────────────────────────────────────────┐
   │ HUB  (substrate: identity + transport)                   │
   │  • /git/<name>/* smart-HTTP endpoint  (git http-backend) │
   │  • validate bearer + surface:<name>:push  (scope-guard)  │
   │  • bare repos (transport store)                          │
   │  • surface→remote registry (name → repo)                 │
   │  • issues surface:<name>:push tokens                     │
   └─────────────────────────────────────────────────────────┘
        │  post-receive → notify over HTTP + hub JWT (NOT shell-out)
        ▼
   ┌─────────────────────────────────────────────────────────┐
   │ surface-host  (module: domain = surface content)         │
   │  • subscribes to push events for its registered repos    │
   │  • pulls the new ref → serves dist under /surface/<name> │
   │  • (build only in its own sandbox, if we push source)    │
   └─────────────────────────────────────────────────────────┘

   VAULT  (declares):  #surface note — mount, mode, source, scopes
```

**Why the hub owns the git transport (recommended) rather than surface-host:** the hub-module-boundary charter lists *transport* as hub-substrate; making git-transport general (not surface-specific) lets it serve **any** future module; and it keeps the RCE surface (§7) out of the substrate (the hub only receives + stores; it never builds). *Alternative:* surface-host owns the endpoint and self-validates via the scope-guard it already imports (matches the vault/notes module pattern). Recommended: **hub owns transport + auth; surface-host owns build + serve.** This is a key decision to confirm (§11).

---

## 5. The `git push`-over-hub-OAuth mechanism (concrete)

Git's HTTP auth is "whatever the front enforces"; nothing exotic. (Grounded in the smart-HTTP protocol + how GitHub/GitLab/`gh`/GCM do it.)

1. **Two requests, service name = read/write.** Discovery `GET /git/<name>.git/info/refs?service=git-receive-pack` (push) or `…upload-pack` (fetch); transfer `POST /git/<name>.git/git-receive-pack`. **read = `upload-pack`, write = `receive-pack`** — scope enforcement keys *purely off the path/service*, no pack parsing.
2. **The 401 dance (load-bearing).** Git first tries anonymously; the hub returns **`401` + `WWW-Authenticate: Bearer`**; git invokes the credential helper and **retries with `Authorization`**. *Push is gated at the info/refs GET, before any pack is sent.* Without the `WWW-Authenticate` header some git versions won't retry — must include it.
3. **Bearer or Basic.** git ≥2.46 sends native `Authorization: Bearer <jwt>` (helper emits `authtype=Bearer`+`credential=<jwt>`); older git uses Basic with **`x-access-token`:`<jwt>`** (GitHub's compat trick). Support both.
4. **The gate.** The hub validates the JWT (signature → JWKS; `iss` ∈ `buildHubBoundOrigins` multi-origin set; `aud`; revocation — the existing scope-guard path) and checks `surface:<name>:push`. On success, proxy (streaming/chunked-safe) to a **`git http-backend`** subprocess with CGI env (`GIT_PROJECT_ROOT`, `PATH_INFO`, `REMOTE_USER=<subject>`, `GIT_HTTP_EXPORT_ALL=1`, `GIT_PROTOCOL`). Enforce at **both** info/refs GET and the POST.
5. **Deploy hand-off — no shell-out.** `post-receive` does **not** run a build as the git user (that's RCE — §7). It **notifies surface-host over HTTP + a hub JWT** (the settled "service-to-service via HTTP, not shell-out" + hub-module-boundary patterns). surface-host pulls the new ref and serves.

---

## 6. Authentication — the three actors (all via the one hub authority)

The whole point: **`git push` becomes just another hub-scoped capability**, identical in spirit for everyone.

### 6a. Internal agents (in the parachute framework) — the grant flow
The agent-connectors subsystem already implements request→approve→mint→inject for `vault`/`service`/`mcp` grant kinds; **`surface` is a 4th kind that extends the machinery almost mechanically.** Invariant preserved: **a vault note can only REQUEST, never GRANT.**

1. **Declare:** a `#agent/role` note carries `wants: surface:<name>:push` (parsed by `parseOneWant`, `grants.ts`; honored only on a `#agent/role`, never a plain content note — the role security gate).
2. **Request (auto, on def load):** the module `PUT <hub>/admin/grants {agent, connection}` → hub writes a `status:"pending"` row to `agent-grants.json` (0600). A note can only ever sit pending.
3. **Approve (human governs):** operator-cookie-gated `POST /admin/grants/<id>/approve` (the module *never* approves). Mints/stores the push credential (lowest-effort precedent: the operator-pasted `service`-token path; cleanest: a hub-minted `surface:<name>:push` JWT).
4. **Inject at spawn (the one genuinely new runtime piece):** material is fetched fresh per turn (revocation = next turn). Today injection is MCP-entry or env-var — **neither authenticates `git push`** (no credential helper exists anywhere in the repo). Add a **third injection channel: a per-spawn 0600 `GIT_ASKPASS` script** in the private workspace that echoes the token, with `GIT_TERMINAL_PROMPT=0` (token never lands in `.git/config`). *Recommended over URL-embedding.*
   - Adjacent: **egress** — under `network:"restricted"`, auto-allow the granted surface's git host (least-privilege link, derived from the grant). **Filesystem** — the repo must be in the turn's cwd (clone-per-turn vs a mounted checkout — §11).

### 6b. External / standalone Claude Code session (on or off machine)
Same hub OAuth, no framework needed:
1. **DCR** (`POST /oauth/register`) — loopback redirect URIs (`http://127.0.0.1:<port>/cb`) are accepted, so a native CLI works. *First registration is `pending` until operator approval* — the headless flow must account for this.
2. **OAuth** auth-code + PKCE (S256) → a `surface:<name>:push` token.
3. **`git-credential-parachute`** — a near-verbatim copy of `git-credential-oauth`: loopback-PKCE for desktops, **device-flow for headless**, emits `authtype=Bearer`/`x-access-token`, caches + refreshes. `git config credential.helper parachute` and any `git push` to a hub surface remote authenticates transparently.
   - **GAP to resolve:** the hub today has **no device-flow (RFC 8628) / client_credentials**. A browserless box completes the flow only via the loopback-browser native pattern. *Decision (§11): ship the helper with loopback + token-cache now, or build a device-authorization grant.*

#### 6b — Phase 3a SHIPPED (2026-07-01): the static **deploy token** — "a GitHub PAT, but for a surface"

Phase 3a takes the **simplest** cut of 6b: skip the browser/OAuth/device-flow (those are the *human* paths, deferred to 3b/3c) and give a remote client the git-equivalent of a **GitHub PAT** — mint a scoped secret, hand it over, `git push` just works. It reuses the Phase-0a mint + Phase-2 credential mechanism verbatim; no new auth primitive.

**Operator (on the box) — mint / list / revoke a deploy token:**

```bash
# push access (default; --read for clone-only). 90d TTL by default (--ttl 30d / --expires-in <s>, cap 365d).
parachute surface token mint <name> --write          # → the token on stdout, setup guidance on stderr
parachute surface token list  [<name>]               # jti · surface · access · status (active/revoked/expired)
parachute surface token revoke <jti>                  # kill a leaked one (git endpoint rejects it within ~60s)
```

The token is a **registered, revocable** `surface:<name>:<read|write>` JWT (`created_via: surface_token`, so it lists as a distinct class from agent grants). It's scoped to ONE surface + one verb — a deploy-key, not a master key (design §7). `mint`/`list`/`revoke` require the operator token to carry `parachute:host:auth` (same gate as `auth mint-token`).

**Remote client (any machine with `git` — NO parachute install, NO `gh`):**

```bash
export PARACHUTE_SURFACE_TOKEN=<the-token>
# the one-line, git-native mechanism — the credential helper supplies the token as
# Basic `x-access-token:<token>`, which the hub /git endpoint accepts on any git version:
git config --global credential.helper \
  '!f() { test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$PARACHUTE_SURFACE_TOKEN"; }; f'

git clone https://<hub-origin>/git/<name> && cd <name>
# …edit / build the surface…
git push                                             # authenticated, no prompt
```

`parachute surface token mint` prints exactly this with the hub origin filled in (`--json` emits `{ token, jti, scope, remoteUrl, credentialHelper }` for scripted / agent config). A reusable **`git-credential-parachute`** helper script ships in `parachute-hub/scripts/` for boxes that prefer a named helper on PATH (`git config credential.helper parachute` + the env var). It works on or off the box — the only requirement is that the hub is reachable at a non-loopback origin (`parachute expose …`), which the mint output flags.

**Zero-tooling fallbacks** (documented, not preferred): a 2-line `GIT_ASKPASS` echoing `$PARACHUTE_SURFACE_TOKEN`; or the token embedded in the remote URL — **flagged**, since it leaks the secret into `.git/config`. Env-var / credential-helper is the recommended path; never commit the token.

**Still to come:** 3b/3c add the interactive loopback-PKCE (desktop) + device-flow (headless) helper modes for *humans* who'd rather log in than paste a secret. The `git-credential-parachute` static path is the seam those extend.

### 6c. Local human (on the box)
Operator token (carries `parachute:host:auth`) → `parachute auth mint-token --scope surface:<name>:push` → use as the git credential (or a `parachute surface push` sugar that wraps it). Validated via the iss-set-tolerant operator path (survives loopback↔public origin skew after `expose`).

---

## 7. Security & trust

- **Write-scope on the git endpoint = RCE *iff* something builds the pushed tree as a privileged user.** Mitigations, in order: **(1) push pre-built dist → the server only static-serves (no build, no exec)** — the recommended default; (2) if building, do it in a *sandboxed* worker that is **not** the git/hub user, the same trust posture as untrusted CI; (3) post-receive *notifies a module* over HTTP+JWT — exec authority stays inside the module's boundary, never the substrate.
- **Human governs grants, always.** Approve/revoke are operator-cookie + first-admin only; the module can only register-pending / fetch-approved-material / reconcile-prune. Worst case from a malicious note: a pending row that sits forever. Consider **step-up PIN** for `surface:push` approval (it's an external *write* capability — strictly more dangerous than a read vault grant), and prefer **least-privilege per-surface tokens** over broad ones.
- **Secret discipline:** credentials live only in the hub's 0600 `agent-grants.json` and, at spawn, an ephemeral 0600 `GIT_ASKPASS`/child-env — **never** in a vault note. The child-env scrub already prevents a grant from setting the Claude-auth trio.
- **Mechanism gotchas:** the `401` must carry `WWW-Authenticate`; auth is checked twice (info/refs + POST); stream/chunked-safe proxy with raised body limits (`http.postBuffer` default 1 MiB → chunked); **never persist the loopback origin** into a token/config (the known origin-pinned-staleness class); force-push/ff is enforced below HTTP (hooks/`receive.denyNonFastForwards`, not the proxy); **Git LFS is a separate auth surface** — declare it out of scope for v1.

---

## 8. The scope model

- **Declare `surface:push`** in surface-host's `.parachute/module.json` `scopes.defines` (joining the existing `surface:read` / `surface:admin`). The hub's 3-segment→2-segment collapse means declaring `surface:push` makes *every* `surface:<name>:push` validate — exactly the mechanism per-vault scopes use. No enumeration.
- **Add a `surface:push` entry to `SCOPE_EXPLANATIONS`** for an honest consent-screen label (else it renders raw).
- **Leave it requestable** (out of `NON_REQUESTABLE_SCOPES`) so it's OAuth-requestable *and* mintable by `parachute auth mint-token` (via `canGrant` from a `parachute:host:auth` bearer).
- **Gaps to decide (§11):** `capScopesToUserAuthority` caps only *vault* named scopes today — `surface:<name>:push` passes **uncapped** (no per-surface ownership cap). `inferAudience` resolves `surface:<name>:*` to `surface` (no per-surface `aud` pin) unless we add a branch. And `push` is outside the read/write/admin ladder → **exact-match** (`surface:admin` does *not* imply push unless we add it).

---

## 9. The `#surface` note (vault declares)

A surface is a vault-native entity, parallel to `#agent/thread`:

```yaml
#surface  "Surfaces/gitcoin-brain"
metadata:
  mount: /surface/gitcoin-brain
  mode: dev | prod
  source:
    kind: git | github | vault | local     # the coupling dial
    ref:  <hub-repo-name | github-url | vault-ref | path>
  scopes: [vault:default:read]             # what the surface's backend may read
content: |
  (the surface's identity/description)
```

surface-host **discovers surfaces from `#surface` notes** (mirroring the agent's `#agent/thread` discovery). `source.kind` is the coupling dial — `git` (hub-transported, the default for this design), `github` (remote backup/mirror), `vault` (content in the vault), `local` (box filesystem, opt-in escape hatch). The vault holds the **declaration + a pointer**, never the artifact — low-churn.

---

## 10. Lifecycle

1. **Create** — write a `#surface` note (an agent via MCP, or a human). surface-host sees it; the hub provisions a **bare repo** + registers `name → repo` in the surface registry.
2. **Grant** — `wants: surface:<name>:push` on an agent role (→ operator approves), or a human/external client gets a `surface:<name>:push` token.
3. **Push** — `git push <hub>/git/<name>` (authenticated). Pre-built dist on a branch (recommended) or source (if we choose build-on-receive).
4. **Serve** — post-receive notifies surface-host → it pulls the ref → serves under `/surface/<name>`.
5. **Iterate** — just push again. Deltas only (no churn).
6. **Roll back** — it's git: revert/checkout an earlier commit and the surface follows. History is free.
7. **Backup** — optionally `git remote add github …` and push there too (git's multi-remote model). GitHub becomes a mirror, not plumbing.

---

## 11. Open decisions (for Aaron)

1. **What is "push"?** → **(B) git-push-source** is this doc; (A) publish-vault-content is already free. *Confirm B is the target.*
2. **Where does the git transport live?** → **Recommended: hub substrate** (general primitive; transport=substrate; RCE out of the substrate). Alternative: surface-host owns it (module self-auth). *The load-bearing architectural call.*
3. **Dist or source over the wire?** → **Recommended: push pre-built dist** (server stays dumb, no exec). Source + build-on-receive needs a sandboxed builder. *Shapes the whole serve path.*
4. **Headless auth** — ship `git-credential-parachute` with loopback-PKCE + cache now, **or** build a device-flow grant (RFC 8628)? *The standalone-Claude-Code path depends on this.*
5. **Push vs pull** — push (immediate, agent-driven) vs pull (surface-host polls; survives agent offline). *Could do both; push is the better dev loop.*
6. **Agent cwd** — clone-per-turn (needs read creds too) vs a mounted checkout (`spec.mounts`).
7. **Scope semantics** — does `surface:<name>:admin` imply push? Add a per-surface *ownership* cap to `capScopesToUserAuthority`? Per-surface `aud` pin in `inferAudience`?
8. **Trust gating** — step-up PIN for `surface:push` approval? Least-privilege per-surface tokens?

---

## 12. Phased build plan

- **Phase 0 — feel it (thinnest slice):** hub runs one authenticated `git http-backend` endpoint; `git push` a dist with a hand-minted `surface:<name>:push` token; post-receive notifies surface-host; it serves. *Proves the spine end-to-end on one machine.*
- **Phase 1 — scope + declaration:** `surface:push` in module.json + consent label; the `#surface` note schema + surface-host discovery; the hub surface→remote registry; `parachute surface push` (local-human sugar).
- **Phase 2 — internal-agent grants:** the `surface` grant kind (both repos' `ConnectionSpec` + `parseOneWant` + both `connectionKey` impls, spec-not-key reconcile); the `surface` approve path; the **`GIT_ASKPASS` injection channel** + egress auto-allow.
- **Phase 3 — external clients:**
  - **3a (SHIPPED 2026-07-01):** the static **deploy token** — `parachute surface token mint|list|revoke` (a scoped, registered, revocable `surface:<name>:<verb>` PAT-equivalent) + the static `git-credential-parachute` helper (env-var token → Basic `x-access-token`). The simplest "add a secret, git just works" for a remote `claude -p` agent / any box. See §6b Phase-3a. No new auth primitive — reuses the Phase-0a mint + Phase-2 credential mechanism.
  - **3b/3c (deferred):** the *human* login paths — `git-credential-parachute` interactive loopback-PKCE + the headless-auth decision (device-flow, RFC 8628, if chosen). The static path is the seam these extend.
- **Phase 4 — surface-dev loop + polish:** the surface-dev agent role; rollback UX; optional GitHub mirror; (stretch) generalize the git-transport primitive beyond surfaces.

Ship a `parachute-patterns/migrations/` file when this redraws the grant-kind contract / the surface install path.

---

## Appendix — grounding (where this is real, not hand-wavy)

- **git mechanics:** smart-HTTP services (`upload-pack`/`receive-pack`), the 401+`WWW-Authenticate` retry, `git http-backend` (auth-by-front), `git-credential` protocol (`authtype`/`credential`/`wwwauth`, git ≥2.46), `git-credential-oauth`/`gh`/GCM precedents, bare-repo + post-receive.
- **hub:** `signAccessToken` (jwt-sign.ts); scope taxonomy + the 3→2-seg collapse (`scope-explanations.ts`, `scope-registry.ts`); DCR + auth-code/PKCE (`oauth-handlers.ts` register/authorize/token); the proxy dispatch + the audience-gate precedent for proxy-layer bearer+scope checks (`hub-server.ts`, `audience-gate.ts`); scope-guard `validateHubJwt` (multi-origin `allowedIssuers`); operator token (`operator-token.ts`).
- **agent grants:** `wants:`/`parseOneWant` + the role security gate (`grants.ts`); request→approve→material→mint (`admin-agent-grants.ts`, `grants-store.ts`); runtime injection (`backends/programmatic.ts`, `agent-mcp-config.ts`, `spawn-agent.ts`); spec-not-key reconcile (the agent#96/hub#674 lesson); egress/spec knobs (`sandbox/`).
- **surface-host:** `uis/<name>/{dist,meta.json}` serve + startup scan (`bootstrap.ts`); the `surface:read`/`surface:admin` scope namespace + credential custody (module.json); the backend-supervisor + dev-watcher.
