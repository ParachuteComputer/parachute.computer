---
title: "Vault as git projection — v0.7+ architecture"
description: "Design for making vault tightly integrated with its git mirror — live projection, bidirectional sync, history in the UI. Builds on the lossless portable-markdown export."
---
# Vault as git projection — v0.7+ architecture

**Date:** 2026-05-20
**Status:** Design proposal — the v0.7+ arc that follows the small `--watch` / `--git-commit` step shipping in **vault#346** (parallel PR). Informs the implementation chain that comes after.

**Companions:**
- [`2026-05-20-vault-as-git-canonical-thought-experiment.md`](./2026-05-20-vault-as-git-canonical-thought-experiment.md) — focused exploration of Architecture C as a thought experiment (not a commitment)
- [`2026-05-18-v06-deploy-architecture.md`](./2026-05-18-v06-deploy-architecture.md) — single-container deploy shape (the substrate this lives inside)
- [`2026-05-20-multi-user-phase-1.md`](./2026-05-20-multi-user-phase-1.md) — multi-user foundation (each user pinned to a vault; mirror config is per-vault)
- [`2026-04-20-module-architecture.md`](./2026-04-20-module-architecture.md) — module + scope shape
- [`parachute-patterns/cookbook/vault-portable-export.md`](https://github.com/ParachuteComputer/parachute-patterns/blob/main/cookbook/vault-portable-export.md) — the lossless export this builds on
- [`parachute-patterns/patterns/trust-gradient-isolation.md`](https://github.com/ParachuteComputer/parachute-patterns/blob/main/patterns/trust-gradient-isolation.md) — the owner-operated framing this assumes

## The decision

v0.7+ moves vault toward being **architecturally aware of its git projection**. Vault remains the runtime (live SQLite + REST + MCP); a configured git mirror becomes the canonical at-rest store, the audit trail, and the portability surface. Like git's working tree vs `.git` store — inverted. Vault is the working tree clients edit; the git mirror is what survives the box.

The arc has three stations: **(A) sidecar projection** (vault → mirror, one-way, ships in v0.7), **(B) bidirectional sync** (mirror → vault flows back, ships if real demand materializes), **(C) vault-as-thick-UI-over-git** (git is canonical, SQLite is a runtime cache — deferred indefinitely). Ship A; defer B and C until operators are loudly asking.

## The shape Aaron is asking for

Two threads converge here. **Gitcoin Brain** (vault-as-job-substrate per the "Gitcoin Brain (2026-05)" pattern — internal design notes) treats jobs as notes, runs as notes, and wants git history of the team brain for free — audit, time-travel, code-review-able diffs over decisions, commitments, run outputs. The existing portable-markdown export already gets them most of the way (see the [vault-portable-export cookbook](https://github.com/ParachuteComputer/parachute-patterns/blob/main/cookbook/vault-portable-export.md)); they wire it via cron + shell loop today. **Owner-operator export/import workflows** (the broader pattern the cookbook codifies) want the same shape: vault as live store, git as the artifact you back up, diff, share, and read offline in Obsidian / IDE.

The friction the current setup leaves on the floor:

- **Manual export cadence.** A note written at 11:03 doesn't land in the mirror until the next cron tick. The operator's mental model is "I edited a thing; the git history reflects it" — reality is "the git history reflects what cron caught."
- **No vault-aware commits.** The shell loop's commit messages are generic ("projection: vault changes since ..."). Vault knows *what changed* (which notes, which tags, which tag-schemas) but that knowledge dies before reaching the git author.
- **No bidirectional sync.** An operator who edits `inbox/2026-05-12-meeting.md` in Obsidian or Vim sees the change clobbered on the next re-export. The export is a one-way projection; mirror-side edits are a fork that gets stomped.
- **No UI history.** Vault's SPA doesn't surface git log per note, diff between revisions, or restore-to-revision. The git history exists; the user can't see it without leaving vault.

The end-state Aaron is gesturing at: vault has a **mirror mode**. Configure the mirror once; every write triggers an incremental export + commit (+ optional push). Eventually, edits to `.md` files in the mirror flow back into vault. Eventually, the SPA renders git history natively.

## What's already built vs what's new

### Already shipped

The portable-markdown export is mature and lossless. The [`vault-portable-export` cookbook](https://github.com/ParachuteComputer/parachute-patterns/blob/main/cookbook/vault-portable-export.md) is authoritative; the headline shape:

- `parachute-vault export <dir> [--since <ISO>] [--vault <name>]` — full or incremental.
- `parachute-vault import <dir> [--blow-away --yes]` — round-trips to byte-equivalent state.
- IDs, typed links, tag schemas, attachments preserved. Fixed frontmatter key order, deterministic emit. Implementation: [`core/src/portable-md.ts`](https://github.com/ParachuteComputer/parachute-vault/blob/main/core/src/portable-md.ts).
- The pattern is **vault-as-primary, git-as-projection**: mutation in vault → re-run export → commit; mutation in git is a one-way fork.

This is the primitive everything below builds on. Re-architecting around git as canonical (option C) would discard this; building on top of it (options A + B) treats it as the load-bearing substrate.

### Ships in the parallel PR (vault#346)

A small step from "shell loop + cron" toward "vault knows about its mirror":

- `parachute-vault export <dir> --watch` — long-running mode that re-exports incrementally on a polling interval (default 5s). Polling rather than filesystem watchers because vault DB writes are HTTP-mediated and opaque to fsevents — there's no filesystem signal to subscribe to.
- `parachute-vault export <dir> --git-commit` — runs `git add -A && git commit -m <message>` after each export pass when the diff is non-empty.
- `parachute-vault export <dir> --git-push` — optional, runs `git push` after commit; failures non-fatal (logged, loop continues).
- Composable: `parachute-vault export ~/mirror --watch --git-commit --git-push` is the "fire-and-forget shell loop, but the process owns it" version of the cookbook recipe.

This stays inside the CLI surface. No schema changes, no hub-side config, no UI surface. It validates the **timing model** (polling re-export on a fixed interval) before committing to architectural awareness — and surfaces the cost (a 5s upper bound on projection latency, every interval whether anything changed or not) that Architecture A's event-driven post-write hooks improve on.

### What THIS design doc covers (v0.7+)

The next architectural step — vault becomes config-bound to its mirror, not external-CLI-bound:

- **Vault knows about its git mirror** — mirror path + commit config live in vault config (or hub_settings, see open question 5), not as flags on a long-running CLI.
- **Bidirectional sync** — file changes flow back into vault (option B, deferred behind demand signal).
- **UI integration** — per-note history tab, diff view, restore-to-revision.
- **Conflict resolution** — what happens when vault and mirror both move.
- **Multi-vault layouts** — one repo per vault vs one monorepo for many vaults.
- **The vault-as-thick-UI-over-git model** — git as the source of truth, SQLite as cache (option C, longer-horizon).

## Architectural options

Three increasingly-ambitious shapes. Each is a strict superset of the prior.

### A — Sidecar projection (smallest delta)

Vault writes trigger export to a configured mirror directory. The configuration is bound — vault reads it on boot, registers post-write hooks, runs incremental re-exports through the existing `--since` machinery. Auto-commit (and optional auto-push) shells out to `git`.

This refinement adds two axes of operator choice (location + watch mode) while keeping the architecture A-shaped. The mirror is still a one-way projection; the underlying data flow doesn't change.

- **Direction:** one-way. Vault → mirror. Mirror-side edits get overwritten on the next re-export.
- **Conflict model:** none required. Vault is the source of truth; the mirror is a derivation.
- **Surface:** new hub admin page at `/admin/vault-mirrors` (mirroring the multi-user phase-1 `/admin/users` pattern). One mirror config per vault.
- **Size:** ~1-2 PRs. Strict superset of the parallel PR's `--watch + --git-commit` CLI mode — the same primitive, just hub-managed instead of operator-managed.

This is the "vault mirrors itself" pattern. It operationalizes what cookbook readers wire by hand today.

#### Two axes of operator choice

A's surface area opens along two independent axes:

- **Axis 1 — Mirror location.**
  - *Internal:* vault-managed at `~/.parachute/vault/data/<name>/mirror/`. Hidden under the vault's own data dir; the operator never has to think about where it lives. Can't be borked — if it goes missing, vault recreates it on next boot. Not designed for direct operator browsing.
  - *External:* operator picks a path (`~/Documents/my-vault-mirror/`, `~/notes/team/`, etc.). Visible. Designed for the operator to open in Obsidian, push to GitHub, share, back up alongside other documents.
- **Axis 2 — Watch mode.**
  - *Auto-watch:* vault keeps the mirror live via the export-watch loop (the v0.7-bootstrap primitive from vault#346). Writes propagate within the debounce window.
  - *Manual:* vault doesn't auto-export; the operator runs `parachute-vault export --vault <name>` when they want a fresh snapshot. Explicit control over export cadence.

All four combinations are technically valid; the system surfaces three as presets.

#### Three preset modes

When the operator enables vault-sync, they pick from three presets. The form pre-fills location + watch + commit settings to match.

**Preset 1 — "History" (internal + auto-watch).** Vault auto-exports to a hidden mirror at `~/.parachute/vault/data/<name>/mirror/`. Always-on; the mirror stays current. The operator doesn't think about it and never sees it unless they go looking. *Use case: "give me an audit trail without operating overhead."* This is the lowest-friction option — one click, no path picker, no permissions to worry about.

**Preset 2 — "Live Mirror" (external + auto-watch).** The operator picks a path (`~/Documents/my-vault-mirror/`, etc.). Vault keeps it live via the watch loop. Optional auto-commit + auto-push for the GitHub-backed scenario. *Use case: "I want to push to GitHub, open in Obsidian, or share with my team."* The visible-folder + always-current shape that matches the cookbook recipe most operators wire by hand today.

**Preset 3 — "Manual Export" (external + manual).** The operator picks a path. No auto-watch; they run `parachute-vault export --vault <name>` when they want a fresh snapshot. Optional auto-commit on each manual export. *Use case: "I want explicit control over when exports happen."* For operators who'd rather batch exports (end-of-day snapshot, pre-meeting freeze, etc.) than have a process polling in the background.

The fourth combination — internal + manual — is technically supported but isn't surfaced as a preset. Internal mirrors get most of their value from being always-current; if an operator wants manual control, external is the natural shape (they can browse the result). Advanced operators can still configure it via the raw config form if a use case shows up.

The defaults framing is **opt-in always.** No mirror exists until the operator explicitly enables vault-sync. When they do, the three presets cover the common cases; the raw config form covers the rest.

### B — Bidirectional sync (real two-way)

A filesystem watcher (the same primitive options A uses, extended to read events) watches the mirror dir for `.md` file changes. On a change: parse the markdown via the existing import machinery, diff against in-vault state, apply changes. Conflict resolution becomes load-bearing.

- **Direction:** two-way. Edit in Obsidian / Vim / IDE → vault reflects within seconds.
- **Conflict model:** last-write-wins by timestamp (default) with an audit log of overridden changes. Future escalation to a conflict UI if loss-of-work becomes common.
- **Surface:** same admin page as A, gains a "bidirectional sync" toggle per vault. Vault writes a status indicator visible in the SPA when a mirror-side edit is being applied.
- **Size:** ~3-5 PRs. Real complexity around watching, conflict resolution, and the import code path having to tolerate partial / in-flight edits.

This is the "edit your notes in Obsidian" pattern. It assumes the operator is the same person editing in both places; cross-tenant bidirectional sync is a different problem (see ["What this doesn't cover"](#what-this-doesnt-cover)).

### C — Vault-as-thick-UI-over-git (the deepest model)

Git repo *is* the canonical store. SQLite is a runtime cache, rebuilt on demand from a git checkout. The operations log becomes git commits. `parachute-vault clone <git-url>` becomes the install method; `git pull` becomes vault sync; conflicts resolve via git merge semantics.

- **Direction:** git is canonical; vault is a view.
- **Conflict model:** three-way merge (git's). Operator resolves merge conflicts the way they resolve merge conflicts in code.
- **Surface:** entire vault model rebases on git. SPA grows commit-graph chrome. The CLI grows git-shaped verbs.
- **Size:** ~6+ PRs. Full architectural rework. Probably v0.8+ work if it ever ships.

This is the "vault is just a fancy git client" model. Powerful — and a different product. Cite Foam, Logseq's `git` mode, the `git-bug` model as priors. Don't commit to it; reserve it as a possibility.

## Recommended path

Ship A. Defer B behind demand signal. Don't commit to C.

- **v0.7 — ship A.** Operationalize the "vault mirrors itself" pattern. Validate against real usage (Gitcoin Brain + any operator on the cookbook recipe). The shape is a strict superset of the parallel PR; the work is incremental.
- **v0.7.5 or v0.8 — ship B if demand materializes.** "I want to edit my notes in Obsidian and have vault catch up" is a real ask but it's not Aaron's stated friction today. Build it when the friction is loud and concrete, not before. The bidirectional case introduces conflict resolution complexity — LWW is simple but not free, and a conflict UI is meaningful design work — that needs real signal to justify.
- **C — defer indefinitely.** Stay on A/B unless operators are loudly asking for git-as-canonical. If they are, the door is open: A's mirror is already byte-identical to what C would expect, so the migration story is "switch which side reads from which."

The pattern this follows is the same one [`trust-gradient-isolation.md`](https://github.com/ParachuteComputer/parachute-patterns/blob/main/patterns/trust-gradient-isolation.md) named for runtime primitives: **name the audience first, ship the lightest viable thing for them, don't span audiences in one primitive.** A is the lightest thing that closes Aaron's stated friction. B is a different audience (the Obsidian-first editor). C is a different product entirely.

## Concrete v0.7 implementation (architecture A in detail)

### Schema additions

One new `hub_settings` key per vault, namespaced by vault name. The shape carries both axes (location + watch mode) plus the commit/push settings:

```jsonc
// hub_settings table — one row per vault that has a mirror configured
{
  "key": "vault_mirror_<name>",       // e.g. "vault_mirror_gitcoin"
  "value": {
    "enabled": true,
    "location": "internal",           // "internal" | "external"
    "external_path": null,            // path string when location === "external", null when internal
    "watch": false,                   // true = auto-watch loop runs; false = manual export only
    "auto_commit": true,
    "auto_push": false,
    "commit_template": "export: {{date}} ({{notes_changed}} note{{plural}})"
  }
}
```

Field semantics:

- **`enabled`** — explicit on/off. Mirror config rows with `enabled: false` are kept for restore but ignored at runtime. Disabling is non-destructive (the mirror dir stays where it is).
- **`location: "internal"`** — vault uses the canonical `~/.parachute/vault/data/<name>/mirror/`. `external_path` is null. Vault bootstraps the directory as a git repo on first enable (`git init` + initial commit) — internal mirrors are vault-managed end to end, so auto-init is right here in a way it isn't for external.
- **`location: "external"`** — `external_path` is required and must be a string pointing at an existing directory that's already a git repo. Validated at config save time; clear error otherwise. Vault never auto-`git init`s an external path — the operator made the location decision consciously and the repo's lifecycle is theirs.
- **`watch: true`** — vault keeps the mirror live via the export-watch loop (post-write hooks + debounced incremental re-export). Same primitive as the parallel PR's `--watch` mode, just process-owned.
- **`watch: false`** — no auto-export. Operator runs `parachute-vault export --vault <name>` themselves. If `auto_commit: true`, each manual export still commits.

The presets map to these fields as:

| Preset | `location` | `external_path` | `watch` | `auto_commit` (default) | `auto_push` (default) |
|---|---|---|---|---|---|
| History | `internal` | `null` | `true` | `true` | `false` |
| Live Mirror | `external` | operator-supplied | `true` | `true` | `false` (toggle to enable for GitHub-backed flow) |
| Manual Export | `external` | operator-supplied | `false` | `true` | `false` |

The wiring decision (vault config vs hub_settings) is open question 5 below. The shape above assumes hub_settings; if vault config wins, the same JSON moves under a `mirror:` block in vault's `config.yaml`. The fields are identical either way.

### Vault-side

- On vault start: read mirror config for each vault. If `enabled: true && watch: true`, register post-write hooks. If `enabled: true && watch: false`, do nothing on writes — the operator drives via CLI.
- For internal mirrors on first enable: vault creates `~/.parachute/vault/data/<name>/mirror/`, runs `git init`, performs the initial full export, and commits an initial revision. The operator sees a one-time "initial sync in progress" status; subsequent passes are incremental.
- For external mirrors on first enable: validate that the path exists and is inside a git repo; surface a clear error otherwise. Perform an initial full export so the mirror starts at byte-equivalent state.
- After every successful write (note created / updated / deleted, tag schema changed, attachment added) when `watch: true`: schedule a debounced re-export. Debounce window starts at **2 seconds** — long enough that a burst of 50 writes from a paste-import collapses to one export, short enough that the operator's "I just saved a note" expectation lands within human-perceptible time. The window is tunable per vault if real usage demands.
- Re-export uses the existing `--since <cursor>` machinery. The cursor lives inside the mirror's `.parachute/` sidecar (same convention as the cookbook recipe), updated atomically after each successful export.
- If `auto_commit: true`: after the export, shell out to `git add -A && git commit -m "<rendered_template>"`. If `auto_push: true`: follow with `git push`. (Push behavior on internal mirrors is undefined — internal mirrors have no remote by default; setting `auto_push: true` with `location: "internal"` is rejected at config-save time.)
- The commit template gets a small variable set: `{{date}}` (ISO timestamp of the export), `{{notes_changed}}` (number of notes touched), `{{plural}}` ("" or "s" for grammatical agreement), `{{change_summary}}` (a short human-readable summary built from the changed-note tags + count), `{{since}}` (the export cursor that produced this pass), `{{vault_name}}`.
- Failures are non-fatal. A git misconfiguration (no remote, dirty tree from manual edits, missing SSH key) logs a warning, writes a status entry visible in the admin SPA, and continues. The next write retries — vault doesn't half-fail because git did.

### Hub-side admin UI

A new admin SPA page at `/admin/vault-mirrors`. Mirrors the multi-user phase-1 `/admin/users` pattern in chrome + interaction shape.

The three presets are the primary entry point. Operators pick a preset; the form pre-fills location + watch + commit settings. Advanced operators can drop into the raw config to customize (or land on the fourth combination — internal + manual).

Surface:

- **List view.** Table: vault name, preset label ("History" / "Live Mirror" / "Manual Export" / "Custom"), location (internal hidden / external path), watch status, last export time, last commit sha, error indicator.
- **Enable wizard.** When a vault has no mirror configured: a "Enable vault-sync" button opens a preset picker (the three named modes, one-sentence description each). Picking a preset opens the form with appropriate fields pre-filled.
  - "History" → confirm-only (no path picker; vault knows where).
  - "Live Mirror" / "Manual Export" → path input with a "validate" button that checks the path exists and is a git repo.
  - Auto-commit + commit-template fields shown for all presets.
  - Auto-push field shown for external presets only (hidden / disabled for internal).
- **Configure (existing mirror).** Per-vault form with the same fields. Switching preset mode is a one-click flip with confirmation (see open question 6).
- **Status surfaces.** Last export time, last commit sha, recent errors (the last 5 surfaced with timestamps). A "force re-export now" button for the operator's debugging. For `watch: false` mirrors, the button is the primary "make the mirror current" surface.

### UX considerations

- **External mirror dir must exist and be a git repo.** Validate on save; show a clear error if either fails. Don't auto-`git init` for external — that hides the "where does this live" decision the operator should make consciously. Internal mirrors are different (vault manages them end to end), so first-enable auto-init is correct there.
- **The vault process needs write access to the mirror dir.** Internal mirrors live under vault's own data dir, so permissions are not a concern. For external mirrors in a self-hosted local install where the operator chooses a path under `~/notes/<vault>/`, vault must be running as a user with write access — surface the error clearly if not. In v0.6's single-container deploy, external mirrors live under a configured `/parachute/mirrors/<vault>/` on the same mounted disk; permissions are not a concern there either.
- **If the mirror path goes missing** (external mirror only — operator `rm -rf`'d it, the disk unmounted, etc.): vault logs a warning, doesn't crash, the admin SPA shows "mirror unreachable" with the option to re-validate the path or unset the config. Internal mirrors are recreated on next boot if the directory is gone (vault owns the lifecycle).
- **Initial sync.** Configuring a mirror for an existing vault triggers a full export (not incremental) so the mirror starts at byte-equivalent state. The operator sees a one-time "initial sync in progress" status; subsequent passes are incremental.
- **Manual mode export hint.** For `watch: false` mirrors, the admin SPA shows the exact CLI invocation (`parachute-vault export --vault <name>`) the operator runs, so there's no guesswork about where the export entry point lives.

## Conflict resolution (option B — if and when we ship it)

The trade-offs the bidirectional case forces a pick on:

- **Last-write-wins (LWW)** by timestamp. Simple, predictable, sometimes loses work silently. Pair with an audit log of overridden changes so the operator can recover from "wait, where did that paragraph go?" — the log records both sides of every conflict, with the chosen winner highlighted.
- **Conflict UI.** Prompts the operator to choose. Expensive UX (an admin SPA modal in the middle of "I just saved a note in Obsidian"), but no silent loss. Right for "real conflicts are rare but expensive."
- **Three-way merge** (git-style, for text-heavy content). Complex to implement (need a base revision to merge against), but produces results most editors would find familiar. Right if the audience is editor-power-users.

**Recommendation for v0.7.5:** LWW with audit log. Cheapest to ship; matches the audience (one operator editing in both places, conflicts mostly transient — say, "I edited in vault while my offline laptop was still queued to push"). If loss-of-work complaints accumulate, escalate to a conflict UI. Three-way merge is overkill for the v0.7.5 audience.

The audit log lives in vault as `tag:conflict-resolution` notes (one note per conflict, with `metadata.original`, `metadata.overridden`, `metadata.winner`). This is recursive but appropriate: vault's audit shape is "audit lives in vault," same as the run-output convention Gitcoin Brain uses.

## UI history surface (v0.7+)

Once the mirror is git-backed, vault SPA can render git history natively:

- **Per-note "history" tab.** Shows the git log of that note's `.md` file. Each entry: commit sha, timestamp, commit message, author.
- **Diff view.** Click a history entry → view the diff between that revision and the current state, rendered as a side-by-side or inline markdown diff.
- **Restore to revision.** "Restore this revision" button on each history entry. Restoration is a vault write (the restored content becomes the current state), which itself triggers the next mirror export, which itself becomes the next commit. The restore is auditable as a git commit.

Implementation: hub queries the mirror git repo via `git log --follow <file>` (handles path renames as long as git's rename detection catches them), parses the output, renders. No new persistent storage — the git repo is the storage.

This surface is **gated on a mirror being configured**. Vaults without mirrors have no history tab. The UI degrades gracefully — "Configure a git mirror in the admin SPA to see note history" — not "broken feature."

Could ship in v0.7 alongside A or split into v0.7.5 (open question 3). Splitting is the safer ship; the history surface is "nice to have" while the mirror itself is the load-bearing primitive.

## Multi-vault layouts

Two operator preferences, both supportable:

- **One repo per vault.** Cleaner separation. Easy to share one vault's history without exposing others. Each vault's mirror config points at its own repo. Right for "I want to give my friend access to my recipes vault as a git repo without leaking everything else."
- **Monorepo with per-vault subdirs.** One git repo, many vaults under subdirectories (e.g. `~/parachute-mirror/vaults/<name>/`). Easier to manage many vaults — one `git pull`, one set of credentials, one push target. Right for the multi-user phase-1 "twenty vaults for twenty people" case where the operator wants one git remote covering everything.

Support both. The schema is just a path — vault doesn't care whether the path is a repo root or a subdirectory of a larger repo. The admin SPA's path validation accepts either ("is this directory inside a git repo?") and exposes the resolved repo root in the status display so the operator knows what they're committing to.

No opinion at the schema level. The cookbook entry grows two recipes — "one repo per vault" and "monorepo" — and points to each from the admin SPA's help text.

## What this doesn't cover

- **Encrypted vaults.** A mirror exports plaintext markdown. If the vault contains encrypted content, the operator's choice is to (a) leave the mirror plaintext and trust the disk, (b) encrypt the git repo at rest (e.g. `git-crypt`), or (c) not mirror. Vault doesn't make the call. Document the trade-off in the admin SPA's help text; don't pretend mirror-side encryption is automatic.
- **Massive vaults (10k+ notes).** The watch + incremental export pattern is built around the existing `--since` machinery, which currently materializes the full vault in memory before iterating (per the cookbook's "1M-note bulk-load ceiling" note). At v0.7 scale this is fine; at 100k+ notes per vault the export pass needs the streaming follow-up tracked at vault#317 F5. Validate performance against real workloads before promising sub-second projection for a 10k-note vault.
- **Hosted Parachute (when it ships).** Per-tenant git mirroring is a separate cloud architecture concern. The patterns in this doc are owner-operated; "give each tenant a git repo and credentials" is a different control surface that the [cloud sketch](./2026-04-20-cloud-offering-sketch.md) will eventually have to address. Out of scope here.
- **Cross-tenant bidirectional sync.** Option B assumes a single operator editing in both places. "Multiple people editing the mirror via git" is a different problem (you're really asking for vault to merge concurrent git branches), and the right answer is option C if it ever lands — not a bigger conflict resolution layer bolted onto B.

## Trade-offs to flag for review

- **Architecture A is the right v0.7 ship.** Pragmatic, builds on the existing primitive, validates the pattern. The parallel PR's `--watch + --git-commit` is the dress rehearsal; A formalizes it.
- **B and C are deferred.** Until real friction signals show up. The cost of building B prematurely is a conflict resolution surface that doesn't match the conflicts users actually hit. The cost of building C prematurely is throwing away the lossless-export substrate before it's clear we don't need it.
- **Mirror config: vault config vs hub_settings.** The choice has real consequences and isn't obvious. See open question 5.
- **Debounce window of 2s is a guess.** Sub-second feels reactive; >5s feels stale. 2s is the midpoint; validate with real usage and tune per vault if needed.
- **Failure modes around git.** No SSH key for push? Dirty working tree from manual edits? Diverged remote? Each needs a clear error surface in the admin SPA — vault keeps running, the mirror status shows "needs attention," the operator gets enough information to fix it without reading hub logs.
- **The "what happens to the run-output flood" question.** Gitcoin Brain's job runner writes a new note per run (potentially many per hour). Every run produces a mirror commit. The git history fills with `run: daily-tweet-drafts/2026-05-12` commits. This is *what we want* — the audit trail of runs is the value — but the commit-noise is real. Mitigation: per-mirror commit-strategy field (`every-write` vs `every-N-minutes` vs `every-N-writes`). Default `every-write`; let operators with high-write-rate vaults tune. Not in v0.7's minimum surface but worth flagging.

## Open questions for Aaron

These need an explicit call before any code starts:

1. **A vs B vs C as the v0.7 ship.** Recommended A, but the call is yours. B is a real audience (Obsidian-first editors) and might be worth more weight than this doc gives it; C is the most opinionated and would reshape vault's identity (worth doing if right, costly if wrong).
2. **Multi-vault default layout.** Per-vault repos (clean separation) or monorepo (easier to manage many vaults)? The schema supports both; the question is which one the admin SPA's "create new mirror" wizard defaults to, and which the docs lead with.
3. **UI history in v0.7 or split to v0.7.5.** History surface is gated on A landing; we can ship them together or land A first + UI second. Splitting is safer; shipping together is more cohesive.
4. **Bidirectional sync as a roadmap item (vs maybe-someday).** Should B be on the public roadmap (signaling intent to ship) or in the "if demand materializes" bucket (the door is open but no promise)? The framing affects whether early-adopter operators design their workflows around it.
5. **Mirror config — vault config or hub_settings.** Vault config keeps the mirror knowledge co-located with the vault (move the config.yaml to a new box, the mirror follows). Hub_settings keeps it administratively centralized (one place to see all mirrors, easier for the multi-user case where the admin manages per-user vault mirrors). The decision is a coupling choice: is the mirror an operational concern (hub_settings) or a vault-level configuration (vault config)? The schema is identical either way; the question is which surface owns it. **Current lean: hub_settings** — the admin SPA is where the operator is already managing user-vault assignments, and centralizing mirror config there matches the multi-user phase-1 shape.
6. **Preset mode change — one-click flip or full re-entry?** Switching an existing mirror from one preset to another (e.g. "Manual Export" → "Live Mirror") could be a single confirmed click that flips `watch: false` → `watch: true` and keeps the same path, or it could force the operator to re-enter all settings as if configuring a new mirror. One-click is more convenient and lower-risk for axes-only changes; full re-entry is more deliberate but adds friction. Minor UX call; the cost of getting it wrong either direction is small.

## What this changes about earlier docs

Nothing in [`2026-05-18-v06-deploy-architecture.md`](./2026-05-18-v06-deploy-architecture.md) changes — the mirror lives on the same persistent disk hub already manages (`/parachute/mirrors/<vault>/`). Nothing in [`2026-04-20-module-architecture.md`](./2026-04-20-module-architecture.md) changes — the mirror is internal to vault, not a new module. The [`vault-portable-export` cookbook](https://github.com/ParachuteComputer/parachute-patterns/blob/main/cookbook/vault-portable-export.md) grows a new recipe ("hub-managed mirror") once A ships, and the existing "nightly git projection" recipe becomes the bootstrap path for operators on pre-v0.7 hubs.

The multi-user phase-1 design ([`2026-05-20-multi-user-phase-1.md`](./2026-05-20-multi-user-phase-1.md)) gets a small future ripple: the admin SPA's `/admin/vault-mirrors` page sits next to `/admin/users`, and the "assign vault to user" flow can grow a "with mirror configured" badge so the operator sees at a glance which user-vaults are git-backed. Optional and not v0.7-gating.

## Why the architecture is right

The criterion that locks A in: **the existing portable-markdown export is the load-bearing primitive, and A is the smallest config-bound wrapper around it.** Everything that's already deterministic about the export — fixed key order, byte-equivalent re-emit, lossless round-trip — applies to A's commits unchanged. The git diffs stay clean. The round-trip stays lossless. The cookbook readers' mental model stays intact; the only thing that changes is "you don't have to run cron anymore."

B and C re-derive useful properties (real two-way editing, git as canonical) at significant cost. They're real audiences; they're just not the audience Aaron's current friction is calling out. Shipping A first keeps the door open for both without committing to either prematurely. That's the same shape the [`trust-gradient-isolation`](https://github.com/ParachuteComputer/parachute-patterns/blob/main/patterns/trust-gradient-isolation.md) pattern names at the runtime layer, applied here at the storage layer: name the audience, ship the lightest thing, don't try to span audiences in one primitive.
