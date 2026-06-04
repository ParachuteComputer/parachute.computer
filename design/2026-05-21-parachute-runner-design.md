---
title: "parachute-runner — vault-as-job-substrate engine, MVP shape"
description: "A new committed-core module that finds job notes tagged `job` in a vault and spawns `claude -p` against each on schedule. The lightweight successor to parachute-agent for owner-operated automation."
---
# parachute-runner — vault-as-job-substrate engine, MVP shape

**Date:** 2026-05-21
**Status:** Proposed. Targets v0.7. The Gitcoin Brain prototype (May 2026) and the parachute-agent retirement (2026-05-20) collectively name the audience this module serves; this doc settles its shape.

**Companions:**
- [`2026-05-18-v06-deploy-architecture.md`](./2026-05-18-v06-deploy-architecture.md) — hub-as-supervisor deploy constraints runner must fit
- [`2026-04-20-module-architecture.md`](./2026-04-20-module-architecture.md) — module protocol (info / config / services.json / well-known)
- [`../../parachute-patterns/patterns/trust-gradient-isolation.md`](../../parachute-patterns/patterns/trust-gradient-isolation.md) — the principle that names runner's audience
- [`../../parachute-agent/DEPRECATED.md`](../../parachute-agent/DEPRECATED.md) — what we learned that informs runner
- Aaron's private design notes — `mirrormirror/gitcoin_brain_design/for_parachute_round_4.md` — the seed observation, vault-as-job-substrate exploration

## The decision

parachute-runner is a new committed-core module: an engine that watches a vault for notes tagged `job`, parses their frontmatter as scheduling + invocation config, and spawns `claude -p` against each on schedule. Output stdout becomes a published note in the same vault, tagged for audit and discovery.

It graduates the Gitcoin Brain prototype shape into a first-class Parachute primitive. The module name is **parachute-runner**; the binary is **`parachute-runner`**; the npm package is **`@openparachute/runner`**. Two CLI verbs:

- `parachute-runner serve` — long-running daemon, internal scheduler, supervised by hub
- `parachute-runner once [--only <path>] [--date <date>] [--dry-run]` — one-shot invocation for external cron / launchd / manual debug

The unit of work is the vault note. The runner is the engine. They are explicitly separate, and they stay separate.

## Why we got here

Three converging observations pinned this shape:

**1. The Gitcoin Brain prototype settled the architecture.** Aaron's ~200-line Python `scripts/run_jobs.py` (May 2026) spawns `claude -p --mcp-config <inline-json>` against vault-stored job notes on cron and writes stdout back. End-to-end ~30–45s per job, $0 in API spend (subscription-funded). The pattern worked end-to-end against real jobs (daily Twitter drafts, weekly digests). The remaining friction — synthesizing inline `--mcp-config` JSON — shipped as vault#345's `parachute-vault mcp-config` CLI. What's left is the runner itself.

**2. parachute-agent's deprecation named the audience.** Owner-operators running prompts they wrote against vaults they own don't need container isolation. `parachute-agent/DEPRECATED.md` and `parachute-patterns/patterns/trust-gradient-isolation.md` codify the lesson: design the primitive for one end of the trust gradient. For the flat end — the audience actually using vault-as-job-substrate today — the right shape is subprocess-on-cron, not Docker-supervised containers. parachute-runner is that shape.

**3. The module protocol absorbs runner cleanly.** Hub-as-supervisor (v0.6) spawns child Bun processes that share `~/.parachute/`. Runner is one more child — same `.parachute/info`, same `services.json`, same install path via `parachute install runner`. No new infrastructure category, no special-case deploy.

## What "runner" means precisely

Jobs are vault notes tagged `job`. Their YAML frontmatter declares schedule, model, output destination, and allowed tools. Their body is the prompt — typically templated against `{{date}}` and `{{job_name}}`.

The runner polls the vault for `tag:job` notes on a cadence (default 60s), parses their frontmatter into a schedule table, and on each scheduler tick either matures (cron-string fires) or skips. Maturing means:

1. Fetch the job note (in case the body changed since last poll).
2. Render template variables in the prompt and `output_path`.
3. Construct the inline MCP config via `parachute-vault mcp-config <name>` (or its library equivalent).
4. Spawn `claude -p --strict-mcp-config --mcp-config '<json>' --allowedTools '<list>' --permission-mode bypassPermissions` with the rendered prompt on stdin.
5. Capture stdout, write a new note at the rendered `output_path` with the declared `output_tags` plus standard run metadata.
6. On non-zero exit or empty stdout (threshold: trimmed-empty — whitespace-only output counts as empty, since claude occasionally emits a stray trailing newline on otherwise-empty results): still write the output note, tagged `job-run + job-run-failed`, with stderr captured in frontmatter for triage.

There is no per-job container, no per-job sandbox, no per-job network policy. The trust gradient is flat: the operator wrote the prompts, the operator owns the vault, the operator owns the host. The protection mechanism is OAuth scope on the bearer the runner holds; the discovery surface is the same vault the work lives in.

## The 10 design decisions

### 1. Deploy shape — daemon primary, one-shot alternate

**Decision:** ship `parachute-runner serve` as the primary surface; `parachute-runner once` as the supported alternate.

`serve` is a long-running Bun process. It maintains an in-memory table of `{ job_path → cron-string → next-fire-at }`, parsed on each poll cycle so adding or editing a job note is hot. A single internal tick (every 30s) checks which jobs are due; matured jobs fan out into `claude -p` subprocesses up to `max_concurrent_jobs`. Restart-on-crash is hub-as-supervisor's job, same as vault/notes/scribe.

`once` is the same code path with the scheduler disabled: enumerate matching jobs, mature anything matching `--only <path>` or matching the current `--date <date>`, exit. Useful for external cron (`*/15 * * * * parachute-runner once --only jobs/quarter-hour-x`), launchd, manual force-runs, and CI smokes.

**Why daemon primary, not one-shot primary:** hub-as-supervisor is the v0.6 deploy substrate. There is no system cron in the Render container. A module that requires external scheduling to function at all wouldn't fit. Daemon-mode also makes "hot-add a job by writing a note" trivial — no operator step beyond saving the file.

**Risk acknowledged:** daemon-mode is a long-running TypeScript process spawning N subprocesses that each shell out to Claude. Memory leaks in the parent, zombie children, or claude-CLI panics could all degrade the runner without crashing it. Mitigations:

- Per-job spawn-and-exit (no in-process state survives a job).
- Hard timeout per job (default 10min, declarable in frontmatter).
- Hub's restart-on-crash policy catches outright parent process death; the parent itself OOMing on a 512MB Render box (the v0.6 cap) is the residual risk worth monitoring.
- A future `parachute-runner self-healthcheck` endpoint could expose run-queue depth + last-tick-ago, scraped by hub for "this child is stuck" detection. Phase 2.

The one-shot path is a real alternate, not a deprecated shim: external cron users (existing Gitcoin Brain operators, anyone on bare metal with their own scheduler) still get a clean API. The cost of supporting both modes is one switch in the entry point and a few lines of "exit when queue is drained" logic. The trust-gradient-isolation pattern's "ship two primitives, not one" warning applies to fundamentally different trust models — not to "scheduler-internal vs scheduler-external" on the same trust model. This is a flag, not a fork.

### 2. Language — Bun/TypeScript

**Decision:** Bun/TypeScript.

The prototype is Python. The ecosystem is Bun. Every committed-core module is Bun. The runner spawns `claude -p` via `Bun.spawn`; that boundary is language-agnostic. The ~200-line Python prototype maps to ~200 lines of TypeScript without ceremony.

The benefits compound:

- Hub-as-supervisor spawns child Bun processes; runner inherits the same start/stop/restart contract.
- `services.json`, `.parachute/info`, `.parachute/config/schema`, `.well-known/parachute.json` scaffolding is the same boilerplate every other module uses.
- biome + typecheck + bun-test cohort works out of the box.
- npm publish chain matches the rest of the ecosystem (`@openparachute/runner`, RC versioning per governance rule 2).

The marginal cost — a TypeScript cron-string library instead of a Python one — is trivial. `node-cron` (works on Bun), `croner`, and `cron-parser` are all viable.

### 3. Job discovery — vault `tag:job` polling

**Decision:** runner queries vault for `tag:job` on every poll cycle. Each note's frontmatter is the source of truth for its schedule. Hot-reload schedules per poll. The vault is the source of truth for "what jobs exist." No registry, no manifest, no parallel state file.

This matches the prototype exactly. It scales linearly with the number of jobs (one vault `query-notes` call per poll, plus N body-fetches when jobs mature). At 1000 jobs polled every 60s on a local SQLite-backed vault, this is well within budget. At 100k jobs, we revisit — that's a v0.8 problem if it materializes.

Per-poll concerns:

- **Schedule changes** propagate within one poll cycle (default 60s, configurable).
- **Disabled jobs** (frontmatter `disabled: true`) are loaded but skipped during scheduling.
- **Deleted jobs** are pruned from the in-memory table when the poll no longer returns them.

### 4. Job note schema

**Decision:** match the prototype's schema. Make `schedule`, `model`, and `allowed_tools` required. Everything else has defaults.

```yaml
---
schedule: "0 8 * * *"              # required — cron-string OR named preset (daily, hourly, weekly)
model: claude-opus-4-7             # required — passed verbatim to claude -p --model
allowed_tools:                     # required — passed to claude -p --allowedTools (comma-joined)
  - mcp__parachute-vault-default__query-notes
  - mcp__parachute-vault-default__find-path
output_path: "jobs/runs/{{job_name}}/{{date}}"  # optional — default "jobs/runs/{{job_name}}/{{run_id}}"
output_tags: [job-run]             # optional — default [job-run]; job-run is always added if missing
timeout: 600                       # optional seconds — default 600 (10min)
disabled: false                    # optional — pause without deleting
---

Today is **{{date}}**. ... prompt body ...
```

**Template variables.** Supported: `{{date}}` (ISO date, UTC), `{{job_name}}` (basename of job note path), `{{run_id}}` (ULID assigned at maturation). Unknown variables are a **fail-fast error**, not silently rendered empty — a typo like `{{Date}}` should not silently write to `jobs/runs/job/.md`. The validator runs at maturation, before the spawn. A failing render writes a `job-run-failed` note explaining the typo.

**Validation timing.** MVP validates frontmatter at maturation (the moment before spawn), not at write. A bad schedule string yields a `job-run-failed` note with the parse error. This is "fail loud, fail late" — acceptable for MVP. Phase 2 adds Draft-07 schema enforcement via a vault tag-schema for the `job` tag, which catches typos at note-write time in the vault UI. (vault already supports per-tag schemas via `update-tag fields`.)

### 5. Output writing — successes and failures, both in-vault

**Decision:** every job invocation writes an output note. Success and failure equally. Audit lives in the same substrate as the work.

Successful runs land at the rendered `output_path` with metadata:

```yaml
---
tags: [job-run, <output_tags from job>]
run_started_at: 2026-05-21T08:00:00Z
run_duration_ms: 31420
run_exit_code: 0
parent_job_id: <note_id of source job>
run_id: 01JX...                  # ULID
---

<stdout from claude -p>
```

Failures (non-zero exit OR empty stdout OR timeout OR template-render error) land at the same path with one additional tag — `job-run-failed` — and stderr captured into frontmatter:

```yaml
---
tags: [job-run, job-run-failed, <output_tags from job>]
run_started_at: ...
run_duration_ms: ...
run_exit_code: 124               # 124 = timeout convention
run_error: "Timed out after 600s"
run_stderr_tail: "..."           # last ~2KB of stderr
parent_job_id: ...
run_id: ...
---
```

This is load-bearing for two reasons:

- **Auditability.** "Did the daily-tweets job run?" is `query-notes tag:job-run parent_job_id:<id> updated_at:>=today`. A successful run produces a note; a missing note means the runner is wedged. Failures are visible in the same query.
- **Saved-query UI for free.** A vault saved-query rendering "all `job-run-failed` from the last 7 days" gives runner a no-code admin surface (see decision 7).

### 6. Module-protocol fit

**Decision:** runner ships the standard module surface — no custom protocol extensions.

**`.parachute/info`:**

```json
{
  "name": "parachute-runner",
  "displayName": "Runner",
  "tagline": "Vault-as-job-substrate engine — spawns claude -p against vault job notes on schedule",
  "version": "0.1.0",
  "kind": "tool",
  "iconUrl": "/runner/.parachute/icon.svg",
  "capabilities": ["scheduled-jobs", "claude-p-runner"]
}
```

**`.parachute/config/schema` (Draft-07):**

| Field | Type | Default | Notes |
|---|---|---|---|
| `vault_url` | string (uri) | — required | Origin where the target vault is reachable. Loopback for v0.6 single-container; tailnet/wan when split |
| `vault_name` | string | `default` | Which vault on that origin to read jobs from |
| `vault_token` | string (secret) | — required | Hub-issued JWT bearer with `vault:<name>:write` scope (mint via `parachute auth mint-token`; the `pvt_*` token class this originally specified was retired in vault#412). Stored encrypted on disk (see decision 8) |
| `poll_interval_seconds` | integer | 60 | How often to re-scan for jobs |
| `max_concurrent_jobs` | integer | 4 | Fan-out limit per scheduler tick |
| `disabled` | boolean | false | Global kill switch — daemon stays running but skips all maturation |

**`services.json` entry:**

```json
{
  "name": "parachute-runner",
  "port": 1945,
  "paths": ["/runner"],
  "health": "/runner/healthz",
  "version": "0.1.0",
  "displayName": "Runner",
  "tagline": "Vault-as-job-substrate engine"
}
```

(Per the [canonical-ports pattern](../../parachute-patterns/patterns/canonical-ports.md), runner will claim the next unassigned slot in the reserved 1939–1949 Parachute range at ship time — currently 1945 is unassigned. The formal reservation lands in a PR to `parachute-hub/src/service-spec.ts` (and the canonical-ports table) alongside the runner module ship, not in this design doc. For reference, the current table: hub 1939, vault 1940, channel 1941, notes 1942, scribe 1943, agent 1944, with 1945–1949 unassigned.)

**HTTP surface (small, debug-oriented):**

| Endpoint | Auth | Returns |
|---|---|---|
| `GET /runner/jobs` | `runner:admin` | List of registered jobs + parsed schedule + last-run timestamp + next-fire-at |
| `GET /runner/runs?since=<iso>&limit=<n>` | `runner:admin` | Recent run metadata (proxy to vault query for `tag:job-run` since timestamp) |
| `POST /runner/jobs/<id>/run-now` | `runner:admin` | Force-run a job out-of-schedule (useful for debugging without editing cron) |
| `GET /runner/healthz` | none | `{ok: true, scheduler_active: bool, jobs_loaded: N, last_tick_ago_ms: N}` |

Plus the standard `.parachute/info`, `.parachute/icon.svg`, `.parachute/config`, `.parachute/config/schema` endpoints.

**Scope:** runner defines two scopes — `runner:admin` (read jobs, force-runs, config) and `runner:read` (read jobs and runs only, for dashboards). The vault bearer it holds is configured via `.parachute/config` — runner doesn't issue its own vault scopes; it consumes one.

### 7. Hub admin SPA integration

**Decision:** lean on vault saved-queries for the job-list and run-history UI. The runner's admin page is small — config + global pause/resume + recent failures count.

The hub#260 generic module-config form is free out of the box: it renders `.parachute/config/schema` as a form and PUTs back the values. That covers `vault_url`, `vault_token`, `poll_interval_seconds`, `max_concurrent_jobs`, `disabled`.

The valuable runner-specific UI views ("what jobs exist, when did they last run, which are failing") are *already vault-shaped*. Jobs are notes; runs are notes; tags filter them. A vault saved-query named "Jobs" rendering `tag:job` and one named "Recent failures" rendering `tag:job-run-failed updated_at:>=7d ago` give 90% of the dashboard for $0 of runner code.

What runner's admin page adds beyond the generic config form:

- A "Pause all" toggle (writes `disabled: true` to its own config).
- A count of `job-run-failed` notes in the last 24h (a thin proxy to the vault query).
- A "Force-run" button per job (POSTs to `/runner/jobs/<id>/run-now`).

That's it. Phase 2 can add a richer per-job timeline view if the saved-query path proves insufficient.

**Why this is right:** the alternative — runner maintains its own SQLite of job state and run history — duplicates what the vault already does. The vault is the source of truth for jobs; making it the source of truth for runs too keeps the trust gradient flat and the operational picture coherent. One substrate, one query language.

### 8. Security model — owner-operated trust gradient, named explicitly

**Decision:** runner is explicitly an *owner-operated* primitive per `patterns/trust-gradient-isolation.md`. Multi-tenant scenarios are out of scope. parachute-cloud (TBD) handles container isolation when that demand materializes.

The bearer the runner holds (`vault_token` in its config) has `vault:<name>:write` scope on one vault. Job notes authored by anyone who can write to that vault can in principle prompt-inject the runner into anything that bearer can do.

**Why this is acceptable for the audience:**

- The operator wrote the prompts.
- The operator owns the vault.
- The operator owns the host running the runner.
- Anyone with write access to job notes is already trusted with full vault access via the same operator's MCP setup.

**What runner does to keep the gradient flat, not amplify it:**

- **One bearer, one vault.** A runner instance reads one vault and writes back to the same vault. Cross-vault runners are explicitly not supported in MVP. (Run two runner instances if you genuinely want this, each with its own scoped token.)
- **Bearer storage.** Stored encrypted on disk at `$PARACHUTE_HOME/runner/secrets.db`, AES-GCM with master key at `$PARACHUTE_HOME/runner/master.key` (chmod 0600), same pattern parachute-agent uses for credentials. The encrypted form never appears in logs, never traverses the HTTP admin surface, never lands in any error message. (Runner's `.parachute/config` GET redacts it.)
- **Path-traversal guards on output writes.** A malicious `output_path: "../../../../etc/passwd"` is bounded by the vault REST API's own path normalization; runner doesn't write files outside the vault directly. If the vault accepts the path, the vault accepts the consequences. Runner doesn't try to be a second line of defense — it relies on the vault's existing path discipline. (vault#308 portable-md path-traversal guards are the load-bearing layer here.)
- **No claude-spawned scope escalation.** Runner passes `--allowedTools` to claude verbatim from the job's frontmatter, never widens it. The bearer scope is the upper bound; `--allowedTools` is a further restriction the operator imposes per-job.
- **Subprocess environment scrubbing.** Per [`trust-gradient-isolation.md`](../../parachute-patterns/patterns/trust-gradient-isolation.md) decision 3, runner spawns `claude -p` with a scrubbed env — only the vars claude needs to run (PATH restricted to its expected location, HOME, plus any claude-cli-specific vars), not the runner's full process env. The runner's own bearer + master key never enter the child's env. (If claude-cli grows its own env-scrubbing surface upstream, runner delegates to that; until then, scrubbing happens at the `Bun.spawn` boundary.)

**What runner explicitly does NOT do:**

- Per-job network namespacing.
- Per-job filesystem isolation.
- Per-job CPU/memory limits.
- Container-per-job lifecycle.

All of those mechanisms are correct for parachute-cloud (steep gradient, multi-tenant). For parachute-runner (flat gradient, owner-operated), they would be the same "complexity tax operators don't want to pay" that retired parachute-agent. The pattern is explicit: design the primitive for one end of the gradient. Don't try to span both.

### 9. Naming — `parachute-runner` as module, `parachute-runner serve|once` as binary verbs

**Decision (already settled):** the module is **parachute-runner**, npm `@openparachute/runner`, binary `parachute-runner`. Verbs: `parachute-runner serve` (daemon), `parachute-runner once` (one-shot).

Module-name convention is verb-ish ("runner runs"). Jobs live in vault as notes; runner is the engine; the two are clearly separate. This avoids the trap of naming the module after the data ("parachute-jobs") and then having to explain "jobs are notes in vault, not in parachute-jobs."

Hub's umbrella CLI works the same as every other module: `parachute install runner`, `parachute start runner`, `parachute status runner`, `parachute upgrade runner`. A future polish in hub could add a `parachute jobs ...` umbrella verb that routes to runner's HTTP surface (`parachute jobs list`, `parachute jobs run <path>`) — that's hub-CLI work, not runner work. Out of MVP scope.

### 10. Phasing — MVP for v0.7, polish in v0.8+

**MVP (v0.7 target):**

- `parachute-runner serve` daemon with internal cron-string scheduler.
- `parachute-runner once [--only <path>] [--date <date>] [--dry-run]` one-shot.
- Job discovery via vault `tag:job`; hot-reload per poll.
- Frontmatter parser with required-field validation at maturation.
- Template variables: `{{date}}`, `{{job_name}}`, `{{run_id}}` — unknown vars are fail-fast.
- `claude -p` spawn via `Bun.spawn`; inline MCP config from `parachute-vault mcp-config` (CLI or library).
- Output writing for successes and failures, with metadata.
- Module protocol scaffolding: `.parachute/info`, `.parachute/config/schema`, `.parachute/config`, `.well-known/parachute.json`, services.json self-registration.
- HTTP surface: `GET /runner/jobs`, `GET /runner/runs`, `POST /runner/jobs/<id>/run-now`, `GET /runner/healthz`.
- Hub-supervised on local + Render. Same install path as vault/notes/scribe.
- Encrypted bearer storage (`secrets.db` + `master.key`).

**Phase 2 (v0.8+):**

- Vault tag-schema enforcement for the `job` tag, so frontmatter typos surface at note-write time in the vault UI rather than at maturation.
- Custom admin SPA view beyond the generic config form (per-job timeline, last-run-status grid).
- Pause/resume per job from the UI without editing the note (writes a `paused: true` field to the note via vault PATCH, or maintains a runner-side override table — TBD).
- `parachute jobs ...` umbrella verb in hub CLI.
- Per-run resource limits (CPU/memory bounds on the claude subprocess) — only if real operators hit the limit; not a speculative addition.

**Phase 3 (deferred indefinitely):**

- Multi-vault runners.
- Multi-tenant operation (out of scope — that's parachute-cloud's lane).
- Job-to-job dependency graphs ("run B after A succeeds").
- Conditional triggers (vault webhooks → run-now), if parachute-channel doesn't already cover this shape.

## What's new vs the Gitcoin Brain prototype

For readers familiar with `scripts/run_jobs.py`, here's what runner changes:

| Aspect | Prototype | Runner |
|---|---|---|
| Language | Python | Bun/TypeScript |
| Scheduling | External cron | Internal cron-string scheduler in daemon mode; one-shot mode still works for external cron |
| Job source | Vault `tag:job` query | Same |
| MCP config | Inline JSON synthesized in script | Library equivalent of shipped `parachute-vault mcp-config` CLI |
| Output writing | Successful runs only (mostly) | Successes AND failures, both with metadata |
| Failure visibility | Stderr to operator's terminal | `job-run-failed` notes in the same vault, queryable via tag |
| Module protocol | n/a (it's a script) | Full module surface — info, config, services.json, well-known |
| Hub integration | None | Hub-supervised, hub-installable, admin SPA visible |
| Bearer storage | Env var in shell | Encrypted on disk with master key |
| Trust model | Implicit (operator on own host) | Explicit (named via trust-gradient-isolation pattern) |

The prototype is right; runner makes it operational. Same shape, ecosystem-shaped surface.

## Open questions

These are flagged for resolution during MVP build, not blockers to start:

- **Cron-string library choice.** `node-cron`, `croner`, `cron-parser` — pick one during build. All viable. Probably `croner` for its native ESM + zero deps, but verify Bun compatibility.
- **MCP config synthesis: library or shell out to vault CLI?** The `parachute-vault mcp-config` CLI is shipped; runner could shell out per maturation. Alternative: vault exposes the JSON-construction as a library function imported directly. Library is faster (no subprocess) and avoids the parser cost; CLI is the public API surface that's already documented. Probably library + CLI both call into the same function in vault's `core/`. Mild coordination with vault to ship a library export.
- **Bearer rotation.** If the operator re-mints the vault bearer (a hub-issued JWT post-vault#412; this originally said `pvt_*`), how does the runner pick up the new value? PUT to `.parachute/config` + restart? Hot-reload from disk? Probably PUT-with-restart is the v0.7 answer; hot-reload is a Phase 2 niceness. *(Resolved in Phase 1.2: `vault_token` hot-reloads via PUT-config.)*
- **Multiple runner instances on one host.** Two operators on one machine each want their own runner instance pointing at their own vault. The install-slug pattern (parachute-agent learned this the hard way per paraclaw#91) needs application here — runner storage paths must namespace on something operator-controllable so two installs don't clobber each other's `secrets.db`. Probably `$PARACHUTE_HOME/runner/<install-slug>/` with the slug deriving from cwd-hash, matching the existing convention.
- **Healthcheck semantics.** What counts as "unhealthy" for hub-as-supervisor's restart loop? Last-tick-ago > 5 * poll_interval? Scheduler thread crashed but parent still up? MVP can ship with `last_tick_ago_ms` exposed and "no auto-restart, log loudly" semantics; refine if operators hit wedges.

## Phasing recap

- **MVP (v0.7)**: daemon + one-shot + discovery + spawn + output writing + module protocol + encrypted bearer + minimal admin. The Gitcoin Brain shape, ecosystem-native.
- **Phase 2 (v0.8+)**: tag-schema enforcement, richer admin SPA, per-job pause-from-UI, umbrella CLI verb. Polish.
- **Phase 3 (deferred)**: multi-vault, multi-tenant, dependency graphs. Most of this is parachute-cloud's problem, not runner's.

## Why the architecture is right

Two equivalences make this small primitive load-bearing for the ecosystem:

**The prototype-to-production equivalence.** A Gitcoin Brain operator running a 200-line Python script with cron should be able to migrate to parachute-runner without changing their job notes. The schema is identical. The model is identical. The output paths are identical. Migration is "install runner, point it at the same vault, disable the old cron entry." That equivalence is how we prove the design honors what already worked.

**The owner-operated audience equivalence.** Anyone who was considering parachute-agent for owner-operated automation against a trusted vault should now consider parachute-runner instead. Same audience, lighter primitive, ecosystem-native. The trust-gradient-isolation pattern's deferred-to-the-future "parachute-jobs (TBD)" reference becomes parachute-runner, real and committed.

The runner is small on purpose. ~200 lines of Python became ~200 lines of TypeScript plus the standard module-protocol scaffolding. The substrate it operates on (the vault) is where the real complexity lives — schemas, query, MCP, OAuth, durable storage. Runner is the thin engine that glues claude to the substrate. Keeping it thin is the design.
