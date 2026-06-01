---
title: "Hub-as-supervisor unification — serve-under-process-manager everywhere"
description: "Retire the manager-less detached-daemon model (parachute start/expose/init → detached+unref'd hub + independent module daemons) and run `parachute serve` (hub foreground + in-process Supervisor, modules = attached children) under a per-platform process manager — systemd on a Linux VM, launchd on a Mac, the container runtime on Render/Fly. Reuses the cloudflare connector-service launchd/systemd machinery for the hub unit. Resolves the CLI→supervisor auth bootstrap, the `upgrade hub` self-modification, the expose/lifecycle coupling, and the process-group reaping regression."
---
# Hub-as-supervisor unification — serve under a process manager everywhere

**Date:** 2026-06-01
**Status:** Proposed. Design-review artifact — the architectural decision the owner blesses **before any code lands**. No code ships with this PR. The `parachute-patterns/migrations/2026-06-01-hub-as-supervisor.md` propagation checklist lands with **Phase 1**, not with this design PR.

**Companions:**
- [`2026-05-18-v06-deploy-architecture.md`](./2026-05-18-v06-deploy-architecture.md) — single-container, hub-as-supervisor deploy shape this generalizes off-container
- [`2026-05-26-fly-migration-path.md`](./2026-05-26-fly-migration-path.md) — Fly as a peer self-host target alongside Render; both are "container runtime = the process manager"
- [`2026-05-28-operator-mintable-vault-admin.md`](./2026-05-28-operator-mintable-vault-admin.md) — operator-token mint path the CLI→supervisor auth reuses
- [`2026-04-20-module-architecture.md`](./2026-04-20-module-architecture.md) — module protocol (services.json, startCmd) the supervisor boots from
- [`../../parachute-patterns/patterns/canonical-ports.md`](../../parachute-patterns/patterns/canonical-ports.md) — 1939 hub-pin (no fallback) that the port-race ordering in §7 must respect
- [`../../parachute-patterns/patterns/governance.md`](../../parachute-patterns/patterns/governance.md) — RC versioning + reviewer-gated PR discipline the phasing follows
- parachute-hub#494 — headless systemd user-unit linger (carried into the hub unit, §4)
- parachute-hub#481 — operator-token `iss` self-heal on `start hub` (the auth bootstrap in §3 must not race)
- parachute-hub#487 — alive-but-never-bound start failure (the port-readiness parity gap in §6)

> **Grounding note.** This doc was written against the real `parachute-hub` source at `main`. Every `file:line` citation was read, not assumed. The earlier thin draft made factual errors (it claimed the CLI mints a host-admin Bearer "the same way the SPA does," which is wrong — see §3); those are corrected here. Where the code does not yet offer a clean mechanism, this doc says so and proposes one rather than hand-waving.

---

## 1. Problem

Parachute runs **two incompatible process models** today, and which one you get depends entirely on *how you deployed*, not on any deliberate choice.

**Model A — manager-less detached daemon** (`parachute start` / `expose` / `init`). The hub is spawned detached and `unref()`'d, tracked only by a pidfile; each module is an independent detached+`unref()`'d daemon with its own pidfile. There is no supervisor. `supervisor.ts:6-30` states the design intent in its own header: the on-box flow *"spawns module daemons detached + unref'd, writes a pidfile, and walks away — process lifecycle becomes the operator's problem (launchd, systemd, or a follow-up `parachute restart`). … If vault crashes, nothing brings it back."* Used on Mac laptops and every Linux VM (EC2 / Hetzner / any VPS).

- Hub spawn: `ensureHubRunning` → `defaultHubSpawner` (`hub-control.ts:74-86, 200`) — spawns `hub-server.ts` **directly, not `serve`**, so the detached hub has **no Supervisor at all**.
- Module spawn: `defaultSpawner` (`lifecycle.ts:74-95`) — `detached: true` + `proc.unref()`, stdio → a per-service logfile.
- Source of truth: pidfiles under `~/.parachute/<svc>/run/<svc>.pid` + `processState()` (`process-state.ts:87`), whose own docstring anchors `unknown` = "may be externally managed (launchd-era)."

**Model B — hub-as-supervisor** (`parachute serve`). The hub runs in the foreground with an in-process `Supervisor` (`supervisor.ts`) that spawns modules as **attached** children, multiplexes their logs into hub stdout, and crash-restarts them on a budget. Used only inside containers today — the `Dockerfile` `CMD ["bun","src/cli.ts","serve"]` on Render and Fly.

The split produces four concrete, recurring failure classes:

1. **EC2 ≠ Render.** The exact same hub package behaves differently depending on deploy substrate. A Render box gets a supervisor, reboot survival (persistent disk + container restart), and working UI module-management. An EC2 box gets none of it. "Self-hosted with good defaults" is undermined when the defaults depend on the substrate.

2. **No reboot survival off-container.** On a VM or Mac, nothing keeps the hub or modules alive across a reboot. The README itself admits an at-login auto-start (`parachute start --boot`) is only "on the post-launch roadmap" (`README.md:211`). After a reboot, the box is simply down until the operator SSHes in and re-runs commands.

3. **UI module-management is broken off-Render.** The admin SPA drives module install/restart/upgrade/uninstall through `POST /api/modules/:short/*`, which **require a supervisor**. Without one, those endpoints return `503 supervisor_unavailable` (`hub-server.ts:1797-1808` and `:1844-1855`): *"module operations require `parachute serve` (supervisor mode); on-box CLI uses `parachute install/upgrade/restart`."* The detached `ensureHubRunning` hub has no supervisor, so the SPA's module manager is dead on every VM/Mac install. `proxy-state.ts:86-130` even carries a whole second classification branch ("on-box CLI mode: no supervisor — fall back to pidfile") to cope.

4. **Stale-daemon-drift bugs.** Independent detached daemons drift from the hub's current state. The origin-pinned-credential class (the recurring "not signed in to the hub" / Cloudflare 401, hub#481/#480) is one face of it: a daemon that captured the hub origin at init keeps a stale `iss` after `expose` until something restarts it. The detached model multiplies the number of independently-restartable things that can hold stale state. (This design does not *fix* the origin-pinning class — that is the self-heal-on-`start` work — but it collapses the number of drift surfaces and makes the self-heal reliably reachable, because there is one restart authority instead of N independent daemons.)

The decision: **retire Model A. Run `parachute serve` (Model B) under a per-platform process manager everywhere.** The target runtime already exists and ships in containers; the work is mostly *deletion + repointing*, plus making `serve` reboot-persistent off-container and closing a small set of capability gaps the supervisor has versus the detached path.

---

## 2. Target model

One runtime: **`parachute serve`** — the hub in the foreground with an in-process `Supervisor`, modules as attached children. One outer keeper per platform:

| Platform | Process manager | Hub unit | Notes |
|---|---|---|---|
| Linux VM (EC2 / Hetzner / VPS) | **systemd** | system unit (`/etc/systemd/system/parachute-hub.service`) when root; user unit (`~/.config/systemd/user/parachute-hub.service`) + `loginctl enable-linger` when non-root | linger is the hub#494 gotcha, carried over |
| Mac laptop | **launchd** | LaunchAgent `~/Library/LaunchAgents/computer.parachute.hub.plist`, `RunAtLoad` + `KeepAlive` | installed by default at `init` (decision D2) |
| Render / Fly | **container runtime** | the image `CMD` already runs `serve`; the runtime is the manager | unchanged — this is the existing shape |
| Init-less host (minimal cloud image, Docker-without-tini, nspawn) | none | graceful `fallback` → print the foreground `parachute serve` invocation + exit non-zero | **no background operation** — see §9 risk and D1 |

**The hub unit is load-bearing.** Under the unified model, modules are attached children: they **die with the hub** (`serve`'s `stop()` SIGTERMs all children before `server.stop()`, `serve.ts:342-351`; the supervisor map is transient in-memory, re-derived from `services.json` on every boot, `supervisor.ts:28-29, 151`). This is a deliberate trade. The detached model survived hub death because children were `unref()`'d; we give that up because the process manager restarts the hub, and `serve` re-boots every module from `services.json` via `bootSupervisedModules` (`serve-boot.ts:55`). The whole reason the migration needs the connector-service machinery is to make "the process manager restarts the hub" *reliably true* off-container.

**Reuse `src/cloudflare/connector-service.ts`.** That file already implements the exact per-platform install/remove seam the hub unit needs — it just hard-codes the cloudflared command and naming. It has:
- An injectable `ConnectorServiceDeps` seam (platform / getuid / homeDir / userName / which / run / file ops, `connector-service.ts:51-101`) so tests inject fakes.
- `installLaunchd` (`:269`) — writes a LaunchAgent plist (`RunAtLoad` + `KeepAlive`, `:163-166`), `launchctl bootout` → `bootstrap gui/<uid>` → `kickstart -k` (`:304-321`), with a legacy `load -w` fallback for old macOS.
- `installSystemd` (`:331`) — system vs user unit by uid (`:341`), `Restart=always RestartSec=5` (`:204-205`), best-effort `loginctl enable-linger` for non-root user units guarded by a `which("loginctl")` probe + try/catch (`:372-387`, the hub#494 fix).
- A graceful `{ outcome: "installed" | "fallback" }` contract (`:212-225`) that **never throws** — a missing tool degrades to fallback with a warning, rather than hard-failing the calling command.
- Idempotent `removeConnectorService` teardown (`:438`).

Generalizing it (factor the cloudflared-specifics into a `ManagedUnit` descriptor) is Phase 2.

---

## 3. CLI surface (post-unification)

The principle: **the running hub's in-process Supervisor is the single lifecycle authority. The CLI is a client that drives it over the module-ops HTTP API** (`api-modules-ops.ts`), the same API the admin SPA already uses. Per-module pidfile spawning (`lifecycle.ts` `defaultSpawner`) is retired.

### 3.1 The auth mechanism (BLOCKER 1 — resolved)

**The thin draft was wrong.** It claimed the CLI "mints a loopback admin Bearer the same way the SPA does … via `/admin/host-admin-token`." It cannot. `handleHostAdminToken` (`admin-host-admin-token.ts:66-91`) requires (a) a valid `parachute_hub_session` **browser cookie** set by a password login, and (b) first-admin identity. A CLI process has no session cookie. That path is the SPA's, full stop.

**The real on-box credential is the operator token** (`operator-token.ts`): `~/.parachute/operator.token`, mode 0600, a hub-issued JWT. The `admin` scope-set (`OPERATOR_TOKEN_SCOPE_SETS.admin`, `operator-token.ts:92-103`) carries **`parachute:host:admin`** — exactly the scope the module-ops API gates on (`api-modules-ops.ts:67`). So the mechanism is:

> **The CLI reads `~/.parachute/operator.token` and presents it as the `Authorization: Bearer` to `POST /api/modules/:short/<op>` on the loopback hub.** It does NOT mint its own token in parallel — it reads the existing on-disk operator token via `useOperatorTokenWithAutoRotate` (`operator-token.ts:391`), which validates against the hub DB + issuer and opportunistically re-mints a within-7d-of-expiry token in place.

This is correct because:
- The operator token already carries `parachute:host:admin` under the default (`admin`) scope-set.
- It is read, not minted-in-parallel — so there is no second SQLite writer racing the running hub, and no re-introduction of the origin-pinned-staleness class the auth-unification arc just closed (hub#481). The hub remains the sole minter.
- Its `iss` is self-healed to the hub's current origin on `start hub` (`selfHealOperatorTokenIssuer`, hooked into start-hub, `operator-token.ts:534`), so a token minted pre-expose validates after expose.

**The auth precondition this introduces (honest gap).** Today `parachute start vault` needs *no token at all* — it touches pidfiles directly. Under the unified model, every per-module verb is an authenticated module-ops call, so it needs an operator token. A fresh box that never ran `parachute auth set-password` / `rotate-operator` has **no operator.token** and would 401. We must close the bootstrap:

- `parachute init` already establishes first-admin and (per the operator-mintable arc) should mint the operator token as part of setup. Phase 3 makes init **guarantee** an operator token exists after a successful init (mint-on-init if absent), so the steady-state operator never sees a 401.
- If a per-module verb runs with no operator token on disk, the CLI fails with an **actionable** message: `no operator token — run \`parachute auth rotate-operator\` to mint one` (the existing `OperatorTokenExpiredError` message shape, `operator-token.ts:413`). Not a raw 401.
- The token is presented over **loopback only**. We do not add a "loopback is trusted" bypass — `operator-token.ts:9-13` is explicit that loopback is not trusted (browser extensions and compromised postinstalls hit 127.0.0.1 too). The operator token *is* the loopback caller's proof of operator authority.

### 3.2 The chicken-and-egg: a module-op when the hub is down (BLOCKER 1, part 2 — resolved)

A module-ops call requires a running hub to answer it. If the operator runs `parachute restart vault` while the hub is down, there is nothing to call. Resolution — **the CLI ensures the hub unit is up first, then drives the supervisor:**

1. **Probe loopback hub** (`GET /health` on the configured hub port). If it answers, go to step 4.
2. **Ensure the hub unit is started.** Drive the platform manager: `systemctl [--user] start parachute-hub.service` / `launchctl kickstart -k gui/<uid>/computer.parachute.hub`. (If no unit is installed — e.g. a never-migrated box — fail with "run `parachute migrate` to install the hub unit," or in `init` install it.) This replaces the old `ensureHubRunning` detached spawn (`hub-control.ts:200`); the new "ensure hub" means "ensure the unit is started," never a detached `bun hub-server.ts`.
3. **Wait for hub readiness** by polling the hub port (reuse the `defaultPortListening` connect-probe, `lifecycle.ts:121`, applied to the hub port). Bounded; on timeout, surface the hub unit's recent log (journald/`launchctl print` or the unit's log file) so a wedged hub is diagnosable, not a silent hang.
4. **Read the operator token** (post-readiness, so we don't race the start-hub self-heal of the token's `iss`, `operator-token.ts:534`) and call the module-op.

This is the explicit resolution of the verdict's bootstrap finding: read the token **after** the hub is ready, never mint in parallel.

### 3.3 Per-verb behavior

`POST /api/modules/:short/*` handlers live in `api-modules-ops.ts`; they require a non-optional `supervisor` (`api-modules-ops.ts:184`) — which is always present under `serve`, so the `503 supervisor_unavailable` gate (`hub-server.ts:1844-1855`) becomes unreachable. That is the off-Render UI fix, for free.

| Command | Post-unification behavior |
|---|---|
| `serve` | The universal runtime, invoked by the platform unit's `ExecStart`. Foreground hub + Supervisor. Unchanged. |
| `start <svc>` | **Needs a new `POST /api/modules/:short/start`** (see below). Ensure-hub (3.2) → call `start` → `supervisor.start(req)` with the boot-derived SpawnRequest. |
| `start` (no svc) | Ensure-hub. The hub's boot already started every installed module (`bootSupervisedModules`); `start` with no svc becomes "ensure the hub unit is up" (which transitively boots all modules). |
| `stop <svc>` | **Needs a new `POST /api/modules/:short/stop`** → `supervisor.stop(short)`. (Today only install/upgrade/restart/uninstall exist; uninstall stops-then-removes, which is the wrong verb for "just stop.") |
| `stop` (no svc) | Stop the **hub unit** via the platform manager: `systemctl stop` / `launchctl bootout`. Children die with it. **Must go through the manager, never a PID signal** — see the launchd KeepAlive note below. |
| `restart <svc>` | `POST /api/modules/:short/restart` → `supervisor.restart(short)`. **404-fallthrough**: if the module is `not_supervised` (404, `api-modules-ops.ts:733-740`), fall through to `start <svc>`. See §6. |
| `restart` (no svc) | Restart the **hub unit**: `systemctl restart` / `launchctl kickstart -k`. NOT "restart every module" — restarting the hub re-boots all modules anyway. Single-module discipline: restarting the hub ≠ a fan-out of per-module restarts. |
| `upgrade <svc>` | Module: `bun add -g` / git-pull then `supervisor.restart`. **Hub: special — see §5.** |
| `logs <svc>` | New `GET /api/modules/:short/logs` tap (see §6 — this is a logging-architecture change, not one endpoint). |
| `status` | Module rows: read `supervisor.list()`. Hub row: query the **platform manager** (`systemctl is-active` / `launchctl print`), since the supervisor does not supervise the hub. See §6. |
| `init` | Install + start the hub **unit** (launchd by default on Mac, D2), wait for hub readiness, guarantee an operator token exists, then run the install wizard / vault install against the loopback hub. Replaces the `ensureHubRunning` detached spawn (`init.ts:374`). |
| `expose` / `expose off` | See §4 — folds into the managed-unit story; `expose off` no longer stops the hub. |
| `migrate` | Idempotent detached→supervised cutover + unit install. See §7. |

**Two new endpoints to add** (Phase 1): `POST /api/modules/:short/start` (a pure `supervisor.start(req)` with the serve-boot-derived SpawnRequest — PORT/.env/HUB_ORIGIN injection per `serve-boot.ts:95-119`) and `POST /api/modules/:short/stop` (`supervisor.stop`). The verdict correctly flagged that **`start` cannot be aliased to `install`**: `handleInstall`→`runInstall` always runs the full install sequence (`bun add -g` or the isLinked probe, services.json seed, installDir stamp, well-known refresh, `api-modules-ops.ts:579-714`) — a heavy, network-touching path for what should be a pure spawn of an already-installed module.

---

## 4. Process-manager units (and how `expose` folds in)

### 4.1 The hub unit shapes

Generalize `connector-service.ts` into a `ManagedUnit` descriptor `{ label, execStart: string[], env: Record<string,string>, logPath }` and emit two units from the same machinery: the existing cloudflared connector and the new hub unit.

**systemd (Linux VM).** `parachute-hub.service`. System unit when root, user unit + linger when not — exactly the connector's branch (`connector-service.ts:341`, `installSystemd`). The new requirement versus the connector: an `Environment=` block (the connector's renderer emits none).

```ini
# /etc/systemd/system/parachute-hub.service   (system; or ~/.config/systemd/user/… for user)
# Generated by parachute — do not edit by hand.
[Unit]
Description=Parachute hub (serve + supervisor)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# User=<operator>  (system unit only — drop hub privileges)
Environment=PARACHUTE_HOME=/home/<operator>/.parachute
Environment=PORT=1939
# PARACHUTE_HUB_ORIGIN intentionally omitted — resolveStartupIssuer derives it
# (RENDER_EXTERNAL_URL / FLY_APP_NAME / expose-state), and start-hub self-heals
# the operator token + vault .env to the current origin. Baking a stale origin
# here would re-create the iss-mismatch class. See §9.
# PATH + BUN_INSTALL are load-bearing for supervised children that resolve a
# bun-linked binary — see §9 "linger env" risk.
Environment=PATH=/home/<operator>/.bun/bin:/usr/local/bin:/usr/bin:/bin
Environment=BUN_INSTALL=/home/<operator>/.bun
ExecStart=/abs/path/to/bun /abs/path/to/parachute-hub/src/cli.ts serve
Restart=always
RestartSec=5
# Crash-loop ceiling — without this a wedged hub (corrupt DB, held port)
# respawns forever, and each respawn re-boots every module (§6 / §9).
StartLimitIntervalSec=300
StartLimitBurst=5

[Install]
WantedBy=multi-user.target   # default.target for a user unit
```

**launchd (Mac).** `computer.parachute.hub.plist`, `RunAtLoad` + `KeepAlive` (mirroring `renderLaunchdPlist`, `connector-service.ts:143-173`), with a `ThrottleInterval` to bound the KeepAlive respawn rate (launchd's default throttle is 10s; we set it explicitly so the hub-crash-loop story is the same as systemd's StartLimit). An `EnvironmentVariables` dict carries `PARACHUTE_HOME` / `PORT` / `PATH` / `BUN_INSTALL`. `ProgramArguments` is `[<abs bun>, <abs cli.ts>, "serve"]` — launchd does not search `$PATH`, so absolute paths are resolved via `which` at install time (the connector already does this, `:181`).

**Both renderers gain an `Environment` / `EnvironmentVariables` block** (the connector emits none today). This is load-bearing: supervised children inherit `process.env` (`supervisor.ts:409`), which under a linger-started systemd user unit is the systemd user-manager's *minimal* env, not the operator's login shell. If `BUN_INSTALL` + a PATH that includes bun's global bin aren't in the unit env, a bun-linked vault/scribe spawn can fail to resolve its linked binary on cold boot while working fine on an SSH login (the `lifecycle.ts:695` resolution failure resurfacing through the unit env — "works when I'm logged in, broken on reboot," the hardest class to debug). See §9.

### 4.2 `PARACHUTE_HOME` capture at install time

`CONFIG_DIR` / `SERVICES_MANIFEST_PATH` are resolved at **import time** from `process.env.PARACHUTE_HOME` (`serve.ts:30-33`). The unit installer must capture the operator's *current* `PARACHUTE_HOME` at install time and bake it into the unit env — not hard-code the default — so an operator running a non-default home gets a unit pinned to *their* home. The launchd `EnvironmentVariables` and systemd `Environment=` both carry it.

### 4.3 How `expose` and the connector fold in (BLOCKER 3 — resolved)

The thin draft only discussed the cloudflared connector. The real coupling is broader and inverts under a managed hub.

**(a) `expose off` no longer stops the hub.** Today `exposeOff` stops the hub when the last layer is torn down (`expose.ts:458-464`: *"Hub lives only as long as some layer is exposed … stop the hub"*). Under a load-bearing platform unit with `Restart=always` / `KeepAlive`, calling `stopHub` would be *immediately undone* by the manager. So the "hub exists only while exposed" invariant **inverts**: the hub is now a persistent unit that runs whether or not any layer is exposed. `expose off` tears down the *exposure* (tailscale serve/funnel config or the cloudflared connector unit) and leaves the hub running. The CLI output changes accordingly (no more "hub stopped" line on `expose off`). This is a deliberate, owner-visible behavior change (D3).

**(b) `expose` (the default path) is Tailscale, not cloudflared.** `expose tailnet` / `expose public` (the supported path, `expose.ts:367`) is Tailscale `serve` / `funnel` — Tailscale's *own* daemon persists the serve config; there is **no Parachute-installed unit** for it. The cloudflared path (`--cloudflare`) is the one with a connector unit. So "expose" is **two unrelated persistence stories**:
- **Tailscale**: persistence is Tailscale's daemon's job. Parachute installs nothing. `expose` only needs the hub reachable on loopback (which the hub unit now guarantees). The old `ensureHubRunning` call in `expose.ts:323` becomes "ensure the hub unit is up" (§3.2).
- **Cloudflare**: the connector gets its own managed unit via the generalized `ManagedUnit` machinery (it already installs one via `installConnectorService`, `expose-cloudflare.ts:457`). `expose off --cloudflare` removes the connector unit (`removeConnectorService`, `:471`) and leaves the hub unit running.

**(c) The post-expose vault restart** (`expose.ts:395-407`, restarting hub-dependent services so they pick up the new origin) goes through the supervisor (`restart <svc>` → module-ops), not `lifecycle.restart`. The origin self-heal (`selfHealVaultHubOrigin` / `selfHealOperatorTokenIssuer`) still fires on the supervised restart.

---

## 5. `upgrade hub` self-modification (BLOCKER 2 — resolved)

`upgrade.ts` special-cases the hub: `hubTarget()` fabricates a synthetic services.json row (`upgrade.ts:369-378`) because the hub isn't in services.json, dispatched at `:387` (single-target) and `:425` (sweep, hub-first). Both branches finish by calling `restartFn` (default `lifecycleRestart`, `:255`), which today goes `stopHub`/`ensureHubRunning`. Under the target model the hub IS the running unit, so "restart the hub" must become a **manager restart of the very process driving the command**.

`upgrade hub` works as:

1. **Rewrite the binary.** Same as today — `upgradeNpm` does `bun add -g @openparachute/hub@<channel>` (`upgrade.ts:632`); `upgradeLinked` does `git pull --ff-only` + `bun install --frozen-lockfile` in the bun-linked checkout (`:543-573`). The unit's `ExecStart` points at `<abs bun> <abs cli.ts> serve` (linked) or the installed bin path (npm), so rewriting the package on disk changes what the unit runs **on its next start**. Idempotent skip-restart heuristics (HEAD unchanged / version unchanged) are preserved (`:556-559`, `:639-642`).

2. **Restart the unit, not the process.** Replace the hub branch's `restartFn` with **`systemctl restart parachute-hub.service` / `launchctl kickstart -k`**. The manager tears down the old hub (children die with it), then starts the new binary, which re-boots every module from services.json. This is a clean swap: the old hub process exits, the manager brings up the new one. The CLI command (`parachute upgrade hub`) returns once the restart is dispatched; it does not need to outlive the old hub.

3. **The SPA-initiated case.** If `upgrade hub` is driven from the admin SPA, the request is handled by a **child of the unit being restarted** (the hub process serving the SPA). The hub is not a supervised module — there is **no `/api/modules/hub/*` path** (`CURATED_MODULES` rejects `hub` in `parseModulesPath`). So the SPA cannot drive a hub upgrade through the module-ops API. Resolution: **`upgrade hub` is a CLI-only / unit-level operation in Phase 1.** Either the SPA's hub-upgrade affordance is omitted (the SPA surfaces "run `parachute upgrade hub` from a shell"), or it dispatches a **detached one-shot** — a short-lived helper that issues `systemctl restart` and survives the hub's exit. Phase 1 ships the CLI path; the SPA affordance is a follow-up issue if wanted. **OPEN for owner**: do we want an SPA hub-upgrade button at all, given the self-restart hazard? (D4 leans: CLI-only for now.)

4. **Ordering in the sweep.** The existing hub-first sweep order (`upgrade.ts:425`, *"a dispatcher upgrade can't be undermined mid-sweep by a service upgrade that restarts hub"*) is preserved — but note that restarting the hub unit now re-boots **all** modules, so a hub upgrade mid-sweep already restarts every module. The sweep should upgrade the hub binary, restart the unit (which re-boots all modules onto current code), then upgrade each module package and `supervisor.restart` it individually. The hub-first invariant still holds.

5. **bun-linked dev path.** Aaron's `parachute` is bun-linked to the checkout. `upgrade hub` on the linked path is `git pull` + `bun install` + unit restart. The unit's `ExecStart` already points at `src/cli.ts` in the checkout, so the new code is live on the unit's next start with **no re-link**. This also resolves the `services.json` stale-version-cache footgun (hub#243): the unit restart re-reads the package.

---

## 6. Lifecycle edge cases

### 6.1 Process-group reaping (BLOCKER/MAJOR 4 — Phase 2, BEFORE the Phase 3 cutover)

This is a **correctness regression**, not optional hardening, and it must land **before** the cutover.

The detached spawner sets `detached: true` (`lifecycle.ts:83`) specifically to put each module in its own process group, so `kill(-pid)` reaps wrapped grandchildren; the header comment is explicit: *"wrapped startCmds like `pnpm exec tsx server.ts` leave the tsx grandchild bound to the port after stop → restart hits EADDRINUSE."* `defaultAlive`/`defaultKill` are group-aware (`:150-180`). The supervisor's `defaultSpawnFn` (`supervisor.ts:403-415`) spawns **attached with no process group**, and `stop()` calls `proc.kill("SIGTERM")` on the **leader only** (`supervisor.ts:219`). For any module whose `startCmd` is a wrapper, cutting over to the supervisor **re-opens the exact EADDRINUSE-on-restart bug** the detached path was built to fix (hub#88) — and because Phase 3 makes `serve`+supervisor the *only* runtime, the regression ships to every box, not just containers.

**Resolution — Phase 2, gated before Phase 3:** add process-group spawn to the supervisor (`detached: true` in `defaultSpawnFn`) and group-signal in `stop()` (`kill(-pgid, ...)` with the same ESRCH/bare-pid fallback as `defaultAlive`/`defaultKill`). The supervisor stays attached for **stdio** (it must keep piping child stdout into the hub log — `pipeOutput`, `supervisor.ts:357`): `detached: true` does not detach the stdio pipes when `stdio` is explicitly `["ignore","pipe","pipe"]`, so this is "own process group for signalling, pipes still wired." Add a regression test that a wrapped startCmd's grandchild is reaped on `stop`/`restart` (the round-trip: spawn wrapper → grandchild binds port → `restart` → fresh spawn binds the *same* port without EADDRINUSE).

### 6.2 restart/upgrade of a not-currently-supervised module → 404 (MAJOR — resolved)

The supervisor map is populated **only** by `bootSupervisedModules` at serve startup and by install. So a module that crashed-and-exhausted-its-budget-then-the-hub-restarted, or whose services.json row failed `resolveSpec` at boot (skipped, `serve-boot.ts:69-93`), or was installed out-of-band, is **absent from the map**. `supervisor.restart(short)` returns `undefined` → `handleRestart` returns `404 not_supervised` (`api-modules-ops.ts:733-740`); `runUpgrade` fails with "upgraded but supervisor had no live entry — try install first" (`:813-820`). Under Model A, `restart <svc>` = stop+start and always works regardless of prior state.

**Resolution:** the CLI client treats `404 not_supervised` from `restart` as **"fall through to `start`"** (the new `POST /api/modules/:short/start` from §3.3, which calls `supervisor.start` with the boot-derived SpawnRequest). For `upgrade`, the "no live entry" failure similarly falls through to `start` after the package rewrite. This makes `restart <svc>` / `upgrade <svc>` total over module state, matching Model A's stop+start semantics.

### 6.3 Crashed-hub-takes-all-modules-down vs the restart budget (MAJOR — resolved)

The hub unit's `Restart=always` / `KeepAlive` is the *outer* keeper. The supervisor's per-module budget (`maxRestarts=3` in a 60s window, then `crashed`-and-stays-crashed, `supervisor.ts:318-331`) is the *inner* keeper. They compose badly in two ways:

1. **A wedged hub respawns forever with no cap.** Without a ceiling, a hub that crash-loops on boot (corrupt `hub.db`, held port) respawns every `RestartSec=5` indefinitely, and **each respawn re-runs `bootSupervisedModules`** → re-spawns all modules → nested crash storms. Under Model A a single wedged module never took down its siblings. **Resolution:** the hub unit carries `StartLimitIntervalSec=300` + `StartLimitBurst=5` (systemd) and a `ThrottleInterval` (launchd) — §4.1. After the burst, systemd holds the unit in `failed` and `parachute status` / `systemctl status` shows *why*. A wedged hub becomes a visible failed unit, not an infinite tight loop.

2. **A hub bounce masks a persistently-broken module.** The supervisor's crash budget is **transient** (`supervisor.ts:28-29`) — it resets on every hub boot. So a module that *should* stay `crashed` gets re-booted fresh on every hub restart, masking a persistently-broken module as a flapping one. **Resolution (accepted limitation + mitigation):** the budget is intentionally per-hub-lifetime; the mitigation is the hub's own StartLimit (above) — a *healthy* hub doesn't bounce, so a healthy-hub + broken-module scenario *does* hit the module budget and lands `crashed`. Only a *flapping hub* resets module budgets, and the StartLimit caps that. We accept the blast-radius increase ("children die with hub") as the explicit trade for one runtime; the StartLimit is what makes it bounded rather than catastrophic. **OPEN (minor):** whether to persist module crash-counts across hub boots is a future refinement, not Phase-1 scope.

### 6.4 status / proxy-state / logs for the hub itself (MAJOR — resolved)

**`status` hub row.** `hubRow` reads `processState(HUB_SVC)` (pidfile) + `readHubPort` (`status.ts:173-205`) — both retired. The supervisor does **not** supervise the hub (`supervisor.ts:25-29`), so there is no supervisor entry to read for the hub. **Resolution:** the hub row queries the **platform manager**: `systemctl [--user] is-active parachute-hub.service` (active/failed/inactive) / `launchctl print gui/<uid>/computer.parachute.hub` (state + last exit). On Render/Fly the hub row reports "container runtime (managed)" — there's no on-box manager to query, and the hub answering `/health` is the liveness signal. The hub-row branch is platform-dispatched, the same shape as the unit installer.

**`proxy-state` classification.** `classifyUpstream`'s Mode-2 pidfile fallback (`proxy-state.ts:114-130`) becomes dead for modules once everything is supervised (Mode-1 supervisor classification is authoritative). That is correct and intended. The **retained** signal for "is this module actually serving?" is the 30s boot-window in Mode-1 (`proxy-state.ts:97-104`) — which only papers over the alive-but-unbound case for 30s. See §6.5.

### 6.5 Per-service logs + port-readiness + structured preflight (MAJOR + MINOR — partly resolved, partly Phase-2 scope)

This is broader than "no per-service file." Three detached-model capabilities have **multiple consumers** that the supervisor doesn't yet replace:

- **Per-service logfile.** Detached writes `~/.parachute/<short>/logs/<short>.log` (`lifecycle.ts` `openSync`→stdio). Consumers: `parachute logs <svc>` tails it (`lifecycle.ts:998-1051`); `readLogTail` surfaces the boot error inline on **start failure** (`:191-200, 706-725`); the "running but no log file" diagnostic (`:1000-1013`). The supervisor multiplexes child stdout into hub stdout with a `[short]` prefix and writes **no per-service file** (`supervisor.ts:357-401`); it **streams and discards** (no ring buffer). A naive `/api/modules/:short/logs` SSE tap can only show output *from connect time forward* — losing the boot-time crash lines, which `pumpLines` itself notes are "likely the most important one — the exit cause" (`supervisor.ts:394-397`). And off-box, journald/launchd capture only the merged hub stream, so `parachute logs vault` off-box would return the *whole* hub log, not vault's.
  - **Resolution (Phase 2):** the supervisor keeps a **bounded per-module ring buffer** (last N KB) fed by `pumpLines`, so `logs <svc>` and start-failure tails can replay recent output including the boot/crash lines. The new `GET /api/modules/:short/logs` serves the ring buffer + an optional follow stream. This is a logging-architecture change touching the supervisor (buffer), the API (endpoint), and the CLI (`logs` client) — scoped explicitly into Phase 2, not hand-waved as "one endpoint."

- **Port-readiness verification.** `lifecycle.start` polls the actual port post-spawn to catch alive-but-never-bound (hub#487, `lifecycle.ts:738-781`). The supervisor marks a module `running` the instant `Bun.spawn` returns a pid (`supervisor.ts:290-295`) — no port check. So a module that spawns-but-never-binds (the classic bun-linked `notes-serve` resolution failure, `lifecycle.ts:695`) shows `running` while unreachable; `classifyUpstream` papers over it for only 30s then flips to persistent-error with no structured cause. Since the *whole point* of Phase 3 is "UI module-management works everywhere," shipping a supervisor that can't distinguish alive-but-unbound from healthy degrades the surface being unified.
  - **Resolution (Phase 2):** add a post-spawn port-readiness gate to the supervisor (reuse `defaultPortListening`), promoting the module to `running` only after the port binds (or marking a `started-but-unbound` substate). Intersects the still-open #188 (systematic missing-dependency UX).

- **Structured preflight / start-error.** `lifecycle.start` runs `ensureExecutable` preflight and `recordStartError`/`clearStartError` onto the services.json row, feeding the missing-dependency UX (`lifecycle.ts:638-687`, the `MissingDependencyError` wire shape). The supervisor does neither.
  - **Resolution (Phase 2):** the supervisor's `start` records a structured start-error onto the module state (and optionally the services.json row) on spawn-preflight failure, so the SPA + `status` keep the friendly missing-dependency surface. Intersects #188.

---

## 7. Migration

`parachute migrate` is extended into the **idempotent detached→supervised cutover** + unit installer. Today it sweeps the legacy `~/.parachute` layout and reads pidfiles (`migrate.ts`).

### 7.1 Cutover ordering (avoids the double-spawn / port-1939 race — MAJOR resolved)

The verdict caught a concrete race: the connector installer **starts the unit as part of install** (`enable --now`, `connector-service.ts:399`; launchd `bootstrap` + `kickstart -k`, `:305/:320`). If the hub-unit installer reuses that machinery verbatim, "install the unit" would start a **second** hub on 1939 while the detached hub is still bound → EADDRINUSE → crash-loop under `Restart=always`. The hub pins 1939 with **no fallback** (canonical-ports pattern), so this is a hard collision.

**Resolution — generalize the installer with an explicit `start: boolean`, and order the cutover stop-before-start:**

1. **Detect** the current model: detached hub alive (pidfile + `kill(0)`), and each module's pidfile/liveness.
2. **Write the unit file** (render + write, **without** enabling/starting it — the generalized installer gets a `{ start: false }` mode that does `daemon-reload` but **not** `enable --now` / `bootstrap`).
3. **Stop the detached processes.** `stopHub` (SIGTERM→SIGKILL + lsof orphan-adoption on 1939, `hub-control.ts:329-338`) for the hub; `lifecycle.stop` per module. **Plus a per-module lsof sweep** (see 7.2).
4. **Verify port 1939 is free** (and each module's port) — poll until released, bounded, to avoid the race.
5. **Now start the unit** (`systemctl enable --now` / `launchctl bootstrap`). The hub comes up on a free 1939 and re-boots every module from services.json.
6. **Verify** the hub answers `/health` and `supervisor.list()` shows the expected modules `running`.
7. **Fold the connector**: if a cloudflared connector unit exists, leave it (it already has its own unit) or re-home it under the unified `ManagedUnit` naming; tailscale needs nothing.

This is the explicit stop-detached-FIRST-then-start-unit ordering. It costs a brief downtime window (between step 3 and step 5) — accepted as correct over the racy "install-while-running" the reused installer would otherwise do.

### 7.2 Orphan-module sweep (MINOR resolved)

`stopHub`'s lsof orphan-adoption probes **only** the canonical port 1939 (`hub-control.ts:309`). A module whose pidfile is stale-but-process-alive (the `unknown`/externally-managed case) won't be found by `readPid` and won't be stopped → it stays bound to its port → the supervised re-spawn hits EADDRINUSE and burns its 3-restart budget → lands `crashed`. **Resolution:** the cutover does an **lsof sweep per services.json port** (mirroring the hub orphan-adoption), adopting and killing any process bound to a module's declared port before starting the unit. Step 6's verify catches anything missed.

### 7.3 The migrate-archive safety footgun (MAJOR resolved)

`migrate` refuses to sweep while services run, via `listRunningServices` (`migrate.ts:347-368`), which checks `processState(HUB_SVC)` **pidfile** (`:353`). Once the hub runs under a unit with **no pidfile**, `processState(HUB_SVC)` reports the hub as NOT running → the refuse-while-running guard (`migrate.ts:406-419`) **silently fails open** → `migrate` could archive `~/.parachute` state out from under a live unit-managed hub. **Resolution:** `listRunningServices` (and any guard reading `processState(HUB_SVC)`) gains a **platform-manager check** for the hub — `systemctl is-active` / `launchctl print` — so a unit-managed hub is correctly detected as running and the archive guard holds.

### 7.4 Unit uninstall / teardown (MAJOR resolved)

- **Explicit teardown.** `parachute migrate --teardown` (or a dedicated verb) removes the hub unit via the generalized `removeConnectorService`-shaped teardown (`connector-service.ts:438` — `bootout` + rm plist / `disable --now` + rm unit + daemon-reload), idempotent + best-effort. This is also the rollback path if the cutover misbehaves: tear down the unit, and the operator can fall back to a foreground `serve`.
- **Package-uninstall teardown.** If the **hub package itself** is removed (`bun remove -g @openparachute/hub`), the unit would persist pointing at a deleted `ExecStart` and crash-loop under `Restart=always`. **Resolution:** ship + document a teardown hook (the uninstall path / a `postuninstall`, or an explicit "run `parachute migrate --teardown` before removing the hub package" instruction), so removing the package removes the unit. Phase 5 owns this.

### 7.5 Backward-compat + the upgrade-lands-the-model footgun (MINOR resolved)

An operator on the detached model who simply `bun add -g @openparachute/hub@<new>` (or auto-upgrades) lands the cutover code **without running `migrate`**: new code expects a unit, no unit is installed, and the detached spawners are gone (Phase 5). After the next reboot they have a dead hub with no prompt. **Resolution — migrate-on-first-start / auto-detect-and-offer:** the first time post-cutover code runs a lifecycle verb and finds (a) no hub unit installed and (b) evidence of a prior detached install (pidfiles / services.json), it **offers** to run the cutover (`parachute migrate`), or in a non-interactive context prints the exact command. We keep pidfile **readers** for one release so the detector can see the old state; the detached **spawners** are removed in Phase 5. We do not silently auto-migrate (archiving is destructive-adjacent) — we detect and offer.

### 7.6 bun-link dev path

The unit's `ExecStart` points at the bun-linked checkout's `src/cli.ts serve`. A `git pull` in the checkout + unit restart picks up new code with no re-link. This is the same path `upgrade hub` (linked) uses (§5).

---

## 8. Phasing

Six independently-shippable, reviewer-gated PRs (governance rule 1 + the mandatory reviewer dispatch). Each code-touching PR bumps `rc.N` per governance rule 2. **The `parachute-patterns/migrations/2026-06-01-hub-as-supervisor.md` propagation checklist lands with Phase 1** and is updated by every subsequent phase (it tracks which PR landed each propagation item — README rewrite, hub CLAUDE.md Architecture block, help text, the FIRST_PARTY_FALLBACKS note, etc.).

| Phase | Scope | Independently shippable? | Gates |
|---|---|---|---|
| **1. Module-ops client + new endpoints + migration file** | Add `POST /api/modules/:short/{start,stop}`; add a CLI module-ops client that reads `operator.token` and drives the running hub (§3.1); ship the migration checklist file. No behavior cutover — additive. | Yes (additive; behind the existing serve path) | 3 |
| **2. Generalize connector-service + supervisor hardening** | Factor `connector-service.ts` into a `ManagedUnit` (env block, install-without-start mode, hub naming). **Supervisor: process-group spawn + `kill(-pgid)` (§6.1), per-module log ring buffer (§6.5), post-spawn port-readiness + structured start-error (§6.5).** | Yes (supervisor changes are container-safe improvements; the generalized installer is unused until 3) | **Blocks 3** |
| **3. `init` + `start`/`stop`/`restart <svc>` cutover** | `init` installs + starts the hub unit (launchd default on Mac, D2), guarantees an operator token, runs the wizard against the loopback hub. `start/stop/restart <svc>` drive the supervisor with 404-fallthrough (§6.2). Status hub row reads the platform manager (§6.4). | Yes (after 2) | 4, 5 |
| **4. `expose` + `upgrade hub` cutover** | `expose`/`expose off` decoupled from hub lifecycle (§4.3); connector folds into `ManagedUnit`. `upgrade hub` restarts the unit (§5). | Yes (after 3) | 5 |
| **5. `migrate` cutover + retire detached spawners** | Extend `migrate` (ordering §7.1, orphan sweep §7.2, archive-guard fix §7.3, teardown §7.4, auto-offer §7.5). Remove `defaultSpawner`/`ensureHubRunning`/`defaultHubSpawner` detached paths; thin `process-state.ts` to readers-only. | Yes (after 4) | 6 |
| **6. Docs + test sweep** | Rewrite README "Service lifecycle" (§9 D2/R14), hub CLAUDE.md Architecture block, help text; run `audit-canonical-refs.sh`; finalize the migration checklist. | Yes (docs-only; skips rc per the doc-only exemption) | — |

**Why process-group reaping is Phase 2, before the Phase 3 cutover:** §6.1. Retiring the detached spawner (Phase 5) without group-spawn in the supervisor re-opens the EADDRINUSE-on-restart bug on every box. Phase 2 lands it as a hard dependency, verified by a regression test, before any cutover.

---

## 9. Risks & resolutions

Every verdict finding (blocker / major / minor), folded in with its resolution or an explicit **OPEN — owner decision**.

| # | Severity | Finding | Resolution |
|---|---|---|---|
| R1 | blocker | CLI→module-ops auth claim was factually wrong (not `/admin/host-admin-token`) | **Resolved (§3.1):** CLI reads `~/.parachute/operator.token` (carries `parachute:host:admin`), presents it as Bearer to loopback module-ops; never mints in parallel. |
| R2 | blocker | Bootstrap chicken-and-egg: minting a token needs a running hub; module-op when hub is down | **Resolved (§3.2):** ensure-hub-unit-first (probe → `systemctl/launchctl start` → wait readiness → read token). Read token *after* hub ready to avoid racing the start-hub `iss` self-heal (hub#481). |
| R3 | blocker | New auth precondition: fresh box has no operator.token → 401 on every per-module verb | **Resolved (§3.1):** `init` guarantees an operator token (mint-on-init if absent); missing-token failure is an actionable "run `parachute auth rotate-operator`," not a raw 401. |
| R4 | blocker | `upgrade hub` self-modification absent; hub isn't a supervised module (no `/api/modules/hub/*`) | **Resolved (§5):** rewrite the binary → restart the *unit* (`systemctl restart` / `launchctl kickstart`), not the process. SPA-initiated hub-upgrade is **OPEN/D4** (lean: CLI-only). |
| R5 | blocker | `expose`/hub-lifecycle coupling missed; `expose off` stops the hub; expose is Tailscale not cloudflared | **Resolved (§4.3):** `expose off` no longer stops the hub (the manager would undo it) — invariant inverts. Tailscale = no Parachute unit; cloudflare = connector `ManagedUnit`. |
| R6 | blocker | `start` cannot be aliased to `install` (full network-touching install path) | **Resolved (§3.3):** add a real `POST /api/modules/:short/start` = pure `supervisor.start(req)` with boot-derived SpawnRequest. |
| R7 | major | **Process-group reaping regression** — supervisor spawns attached, kills leader only → EADDRINUSE-on-restart for wrapper startCmds | **Resolved (§6.1):** group-spawn + `kill(-pgid)` in the supervisor, landed in **Phase 2 before the Phase 3 cutover**, with a regression test. Not optional. |
| R8 | major | restart/upgrade of a not-supervised module → 404 `not_supervised` | **Resolved (§6.2):** CLI treats 404 as fall-through to `start` (and upgrade falls through after the package rewrite). Total over module state, matching Model A. |
| R9 | major | Crashed hub takes all modules down; no backoff cap; hub bounce resets module crash budget | **Resolved (§6.3):** `StartLimitIntervalSec`/`StartLimitBurst` (systemd) + `ThrottleInterval` (launchd) cap hub respawn; a wedged hub becomes a visible `failed` unit. Cross-boot crash-count persistence is **OPEN (minor refinement)**. |
| R10 | major | Migration double-spawn / port-1939 race (reused installer couples install+start) | **Resolved (§7.1):** generalized installer gets `{ start: false }`; cutover order = write-unit → stop-detached → verify-port-free → start-unit. |
| R11 | major | `status`/proxy-state for the **hub itself** under-specified (supervisor doesn't supervise hub) | **Resolved (§6.4):** hub row queries the platform manager (`is-active` / `launchctl print`); Render/Fly report "container runtime (managed)." |
| R12 | major | `logs <svc>` loses per-service file; supervisor streams+discards (no boot-crash replay); off-box returns merged hub log | **Resolved (§6.5, Phase 2):** supervisor keeps a bounded per-module ring buffer; `GET /api/modules/:short/logs` serves buffer + follow. Logging-architecture change, scoped into Phase 2. |
| R13 | major | Concurrency: in-process budget vs unit `Restart=always` compose badly | **Resolved (§6.3):** same StartLimit/Throttle fix; the budget is per-hub-lifetime by design, bounded by the hub's own crash ceiling. |
| R14 | major | README "Service lifecycle" rewrite is far larger than a one-line "no launchd" nod | **Resolved (D2/R23 + Phase 6):** README:181-211 fully rewritten — `run/<svc>.pid` + `logs/<svc>.log` state model retired, `unknown`=externally-managed semantics removed, "Migrating from launchd" subsection reversed, `parachute start --boot` roadmap line resolved (this design *is* it). Tracked as discrete migration-checklist lines. |
| R15 | major | Uninstall/teardown of the hub unit + migrate-archive safety guard failing open | **Resolved (§7.3, §7.4):** `listRunningServices` gains a platform-manager hub check (guard holds); explicit `--teardown` + package-uninstall hook removes the unit. |
| R16 | minor | Orphan adoption single-port only; stale-pidfile-but-alive module stays bound | **Resolved (§7.2):** lsof sweep per services.json port during cutover. |
| R17 | minor | launchd KeepAlive fights an intentional hub stop (SIGTERM resurrects) | **Resolved (§3.3):** hub stop/restart MUST go through `launchctl bootout`/`kickstart`, never a PID signal; the table is explicit. |
| R18 | minor | Port-readiness + structured-preflight parity loss undercuts the headline UX win | **Resolved (§6.5, Phase 2):** post-spawn port-readiness gate + structured start-error in the supervisor; intersects #188. |
| R19 | minor | No-init-system hosts lose background operation entirely (worse than detached) | **Acknowledged caveat (§2 table, D1):** init-less hosts get foreground-`serve`-only (no background), which is *worse* than detached's "survives until reboot." Explicitly documented; **OPEN/D1** whether to keep a transient-unref fallback for this narrow population. |
| R20 | minor | systemd user-unit linger env: supervised children inherit minimal env, can't resolve bun-linked binary on cold boot | **Resolved (§4.1):** the unit `Environment`/`EnvironmentVariables` block carries `PATH` + `BUN_INSTALL` (not just `PARACHUTE_HOME`/`PORT`), so cold-boot linger spawns resolve linked modules. |
| R21 | minor | `PARACHUTE_HOME` import-time resolution; unit must capture the operator's current home | **Resolved (§4.2):** installer captures the current `PARACHUTE_HOME` at install time, bakes it into unit env. |
| R22 | minor | Migration checklist file not created; propagation surface uncatalogued | **Resolved (phasing):** ships with **Phase 1** (the originating implementation PR, per workspace policy), not this design PR — noted in the PR body. |
| R23 | minor | D2 reverses a shipped, documented selling point ("no launchd") | **Resolved (R14 + D2):** not a copy nod — discrete migration-checklist lines rewrite README:183 AND the "Migrating from launchd" subsection (which currently tells operators to *remove* the mechanism we now install). |
| R24 | minor | `init` vault-install + CLI-wizard sub-steps not enumerated as touch points | **Resolved (§3.3 init row + §7):** init order = install-unit → start-unit → wait hub readiness → guarantee operator token → wizard/vault-install against loopback; hub-port readiness reuses `defaultPortListening`; a unit-installs-but-hub-never-binds case surfaces the unit log (no silent wizard hang). |

---

## 10. Open decisions

The owner's fork leans, written as explicit, flippable decisions, plus what the verdicts surface as needing the owner.

- **D1 — Full retirement of the detached model.** *Lean: yes, full-retire (Phase 5 deletes `defaultSpawner`/`ensureHubRunning` detached spawners).* Alternative: keep a transient-`unref` fallback for the narrow init-less-host population (R19) so they retain "survives until reboot." Rationale for full-retire: two models is the root problem; keeping a fallback re-introduces the split. **Flip cost:** low — the fallback is the existing code; not deleting it in Phase 5 preserves it. **Owner call:** accept the init-less-host regression (R19) as the price of one runtime, or keep the narrow fallback?

- **D2 — Mac = launchd by default at `init`.** *Lean: yes.* Alternative: opt-in (`init` prints the launchd install command but doesn't run it). Rationale: reboot survival is the headline win; making it opt-in on Mac leaves laptops in the same down-after-reboot state. **This reverses a shipped, documented selling point** — README:183 sells "no launchd, no manual `bun serve`, no hunting for PIDs," and README:201-207 tells operators to *remove* a launchd agent. The reversal is defensible (the old plist was vault-specific and manual; the new one is the hub, installed and managed by Parachute), but it needs the full README rewrite (R14/R23), not a nod. **Owner call:** launchd-by-default, or opt-in on Mac?

- **D3 — `parachute start/stop/restart <svc>` preserved by driving the running supervisor.** *Lean: yes — preserve the verbs, repoint them at module-ops.* Alternative: deprecate per-module CLI verbs entirely in favor of the SPA. Rationale: the CLI verbs are muscle-memory and scriptable; preserving them (now as supervisor clients) is strictly better than the detached pidfile path. This also makes `expose off` stop-the-hub behavior invert (§4.3) — an owner-visible change. **Owner call:** confirm the verbs stay; confirm `expose off` leaving the hub running is acceptable.

- **D4 — Idempotent cutover migration; SPA hub-upgrade affordance.** *Lean: idempotent `migrate` cutover (yes); SPA-driven `upgrade hub` = CLI-only for now (no SPA button).* Rationale: a unit restarting the very process serving the SPA request is a self-restart hazard (§5.3); the clean path is a shell `parachute upgrade hub`. **Owner call:** is CLI-only hub-upgrade acceptable, or do we want a detached-helper SPA button despite the hazard?

- **Owner-surfaced (from verdicts):**
  - **R9 cross-boot crash-count persistence** — accept the per-hub-lifetime budget (capped by the hub StartLimit), or persist module crash counts so a hub bounce doesn't mask a persistently-broken module? *Lean: accept per-lifetime for Phase 1; refine later.*
  - **R19 init-less hosts** — see D1.
  - **`logs` off-box semantics (R12)** — the ring-buffer tap works on-box; off-box (Render/Fly) the merged hub stream is what journald/the container log holds. *Lean: `logs <svc>` on-box reads the ring buffer via the endpoint; off-box documents that the platform's log viewer shows the merged hub stream (with `[short]` prefixes for grep).* Owner confirm this is acceptable for the container deploys.

---

## Appendix — the retirement, concretely

The target runtime (`serve` + `Supervisor` + `api-modules-ops`) **already ships in containers**. The retirement is mostly deletion + repointing, not new architecture:

- **(a)** Make `serve` reboot-persistent by generalizing `connector-service.ts` to install a launchd/systemd unit running `<bun> <cli> serve` (Phase 2/3).
- **(b)** Rewrite `lifecycle.ts` `start/stop/restart <svc>` to drive the running hub's module-ops API (reading `operator.token`) instead of `defaultSpawner`/pidfiles (Phase 3).
- **(c)** Replace the four `ensureHubRunning` detached-bringup sites — `init.ts:374`, `expose.ts:323`, `expose-cloudflare.ts:659`, `lifecycle` start-hub — with "ensure the unit is installed + started" (Phase 3/4).
- **(d)** Land the supervisor hardening (group-reaping, log ring buffer, port-readiness, structured start-error) in Phase 2 **before** the cutover.

The single biggest correctness payoff — UI module-management working everywhere — falls out automatically: once everything runs under `serve`, the `supervisor_unavailable` 503 in `hub-server.ts:1797-1808/1844-1855` is unreachable.
