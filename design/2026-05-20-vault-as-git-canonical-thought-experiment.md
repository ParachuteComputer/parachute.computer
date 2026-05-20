---
title: "Vault as git-canonical — a thought experiment (Architecture C)"
description: "Exploration of the radical alternative to A/B: git IS the canonical store, SQLite is a runtime cache rebuilt from git checkout. Not a commitment — a structured trade-off map for when this question matures."
---
# Vault as git-canonical — a thought experiment (Architecture C)

**Date:** 2026-05-20
**Status:** Thought experiment, **not a commitment.** Companion to [`2026-05-20-vault-as-git-projection.md`](./2026-05-20-vault-as-git-projection.md). That doc recommends shipping Architecture A in v0.7; this one explores what C — the radical alternative — would actually look like if we ever chose to build it. Read both if you're weighing the trade-off between them.

**Companions:**
- [`2026-05-20-vault-as-git-projection.md`](./2026-05-20-vault-as-git-projection.md) — the A/B/C framing; A is the v0.7 ship.
- [`parachute-patterns/patterns/trust-gradient-isolation.md`](https://github.com/ParachuteComputer/parachute-patterns/blob/main/patterns/trust-gradient-isolation.md) — the "name the audience, ship the smallest viable primitive" pattern this exploration honours.
- [`parachute-patterns/cookbook/vault-portable-export.md`](https://github.com/ParachuteComputer/parachute-patterns/blob/main/cookbook/vault-portable-export.md) — the lossless export format that would become canonical under C.

## Why this doc exists

The companion design doc lays out three architectures (A — sidecar projection, B — bidirectional sync, C — vault-as-thick-UI-over-git). It recommends A and defers C indefinitely. That's the right call for v0.7. But C is *interesting* in a way that deserves more than a "deferred" tag — it's the shape some operators are gesturing at when they describe what they want, and the day someone makes a serious case for it, future-Aaron deserves more to work with than a paragraph.

This is the structured trade-off map. It's not a roadmap entry. It's not a plan. It's "if and when we open this door, here's what's behind it." Build for what's true, not what might be — and write the C-investigation now while the question is fresh, so the answer doesn't have to be invented under pressure.

## 1. The premise — what changes

The core flip:

- **In A/B**, vault is the live system and git is a projection. Vault writes to SQLite; a mirror exports to .md files; git is downstream of vault state.
- **In C**, git is the live system and vault is the UI over it. The .md files in the working tree ARE the notes. SQLite is a derived cache. Vault state is *whatever the filesystem says it is*.

Concretely under C:

- `parachute-vault clone <git-url>` replaces `parachute install vault` as the install command. You don't create a vault — you check one out.
- `git pull` is the sync mechanism between machines.
- `git push` is the backup and sharing mechanism.
- SQLite is rebuilt on demand from the git checkout. Never the source of truth; always derivable.
- The .md files ARE the notes. The .yaml files in `.parachute/schemas/` ARE the schemas.
- An operator can `cd ~/my-vault && nvim notes/inbox.md` and edit the file directly. Vault picks up the change via filesystem watcher (or on next request via a cache invalidation check).
- Vault's API writes flow *through* the filesystem: a REST write becomes "write .md atomically, update SQLite cache, optionally git commit."

This is not "vault with a git option." This is "vault is git, plus an interface." The identity changes — vault becomes a thick UI over a git repo, the way some folks describe Obsidian-on-Syncthing today but with typed schemas, MCP, and a queryable API on top.

## 2. Why this is interesting

Three real draws.

**Obsidian-native interop.** The .md files ARE the data. Drop the vault dir into Obsidian, edit a note, vault sees the change immediately. No sync layer, no projection lag, no "did the export run yet" question. When only one tool writes at a time (operator in vault, then operator in Obsidian, then operator in vault again), there are no conflicts to resolve — it's just one filesystem with two editors taking turns. This is the experience that's hard to deliver in A (mirror is downstream; edits get overwritten) and lossy in B (bidirectional, but with a sync delay and conflict resolution surface).

**Git semantics throughout, native and free.** History, branches, merges, blame, rebase, cherry-pick — all available at the operator's command-line, with no vault-mediated history surface required. `git log <note>.md` shows you the history of that note. `git blame` shows you who changed which line. `git checkout <sha> -- <note>.md` restores a revision. Vault's SPA can still surface this UI for non-CLI users, but the storage layer doesn't have to invent its own history model — it borrows git's. Under A/B, vault has to build a history surface that's *as good as* git; under C, vault *is* git.

**Distributed by default.** Clone, push, pull — multi-machine sync is just git. The "vault sync server" question never has to be answered because git remotes (GitHub, GitLab, a SSH-accessible bare repo) already are the sync server. Sharing a vault with a collaborator is `git clone` + edit + push. Forking a vault is `git clone` + edit + don't push. Backing up a vault is `git push`. Restoring a vault is `git clone`. The whole class of "how do we move vault state between machines" questions collapses into git's well-known answers.

## 3. What it would cost

The costs are real and they cluster around five questions: how fast is the cache, what happens during conflicts, how do attachments live in git, what about schema evolution, and how does MCP stay responsive.

### Performance — the cold-start problem

Every read needs the SQLite cache. The cache has to be built from the git checkout. The cache is invalidated by external edits to the working tree.

- **Tiny vaults (~100 notes):** sub-second cache rebuild on any modern SSD. Performance is a non-issue.
- **Medium vaults (~1k notes):** seconds to rebuild. Fine for occasional cold starts (machine boot, vault upgrade), painful for restart-heavy operational patterns (every `parachute restart vault` becomes a multi-second wait before the first query lands).
- **Large vaults (~10k+ notes):** minutes for cache rebuild. Vault becomes effectively unusable for restart-driven workflows. Cold-start latency dominates.
- **The MCP angle:** vault MCP queries today complete in sub-100ms for typical lookups. If SQLite has to be regenerated from a stale cache before the query can run, MCP latency becomes whatever cache-rebuild-or-incremental-update costs. That's the difference between MCP feeling instant and MCP feeling like a batch job.

The mitigation is incremental cache updates — only re-parse the files whose mtime changed since the last cache build. That works well *most* of the time but breaks on `git checkout <branch>` (many files change atomically, often without mtime granularity matching reality) and on `git pull` after a remote update (same problem at higher scale). The honest answer is "cache rebuild is fast for the common case, slow for the worst case, and the worst case happens whenever the operator does anything git-shaped."

### Conflict resolution — git's merge model meets typed links

Git's three-way merge is line-based. Vault's data model is not.

- A note's frontmatter has structured fields: typed links, tag schemas, attachment references, IDs. Two edits that touch the same frontmatter block produce git conflict markers (`<<<<<<< HEAD ... =======`) in YAML — vault can't parse the result, the schema validators reject it, and the operator has to hand-merge YAML before vault can even read the note.
- A note's body merges roughly the way prose merges in git: fine for distinct paragraphs, painful for two edits to the same sentence. That's the same UX as code, which is at least a familiar pain.
- Typed-link edges are stored in frontmatter (`links: [...]`). Concurrent edits that add different edges to the same note produce a YAML conflict that's syntactically valid-looking but semantically a list-merge problem git doesn't know how to solve.

For Gitcoin Brain's vault-as-job-substrate pattern: multiple agents writing **different** notes simultaneously is fine — git happily takes a `git add` of many new files. Multiple agents writing the **same** note simultaneously produces conflicts. The latter is rarer in practice, but it does happen (e.g., a job updates the state of a long-running task while another job logs a run output to the same note).

The escape valves are:
- Vault refuses concurrent writes to the same note (lock-based, single-writer-wins). Predictable, restrictive.
- Vault produces semantic merges for structured frontmatter (set-union for links, latest-wins for state fields). Powerful, complex to implement correctly, opaque to the operator.
- Vault surfaces conflicts as inline conflict markers and asks the operator to resolve. Familiar to coders, frustrating in the middle of "I just saved a note."

None of these are free.

### Attachment handling — the wart

Binary blobs in git are a problem.

- A 10MB audio attachment goes into the pack file and never leaves. A vault with hundreds of voice-memo attachments balloons the repo to gigabytes within months.
- Git diffs over binary content are opaque ("Binary files a/audio.m4a and b/audio.m4a differ"). The "I can see what changed" promise dies for attachments.
- `git clone` of a binary-heavy repo is slow. Operators on flaky connections feel it.

Three mitigations, each with a downside:

- **git-lfs.** Standard, well-supported. But: requires LFS server-side support (some self-hosted git servers don't ship it), adds operator setup ("install git-lfs first"), introduces a second sync channel (LFS pointers in git, blobs in LFS). The "everything is in git" promise gets an asterisk.
- **git-annex.** More powerful than LFS, weirder, less commonly deployed.
- **Attachments-as-separate-store.** A blob store outside git (S3-compatible, local filesystem). Defeats the C model's central claim — now state lives in two places.

The honest answer: under C, attachments are the wart that doesn't go away. Pick a mitigation, document the trade-off, accept that "everything is in git" has a footnote.

### Schema migrations — git history is forever

Vault's SQLite schema can evolve. Vault's schema is on its 18th version — adding columns, renaming fields, restructuring tag-schema storage. Each migration is a one-time vault-side operation; current notes get re-interpreted under the new schema, old code paths get retired.

Under C, git history is forever. A commit from 18 months ago has `.md` files with the schema of the vault at that point in time. When vault reads that commit (via `git checkout <sha>`, or `git log` browsing), what does it do?

- **Option 1: forwards-compatible across all schema versions.** Vault knows how to interpret schemas v1 through vN simultaneously. Operationally expensive — every schema change has to ship with a "and here's how to read the old shape" shim. Compounds over time.
- **Option 2: old commits are read-only / opaque.** Vault refuses to interpret pre-migration commits, surfaces them as "this commit predates schema v4, content shown as raw markdown without typed fields." Breaks the "history is browseable" promise that's one of C's big draws.
- **Option 3: rewrite history on schema change.** Vault rewrites every old commit to use the new schema (effectively a `git filter-branch` over the whole repo). Massive, disruptive, breaks every existing clone, kills the audit trail. Probably the wrong answer.

For a vault whose schema is stable (post-1.0), this concern shrinks. For a vault whose schema is still evolving (where we are now), this is a serious overhead C imposes that A doesn't.

### MCP responsiveness under cache staleness

Today, vault MCP queries are sub-100ms. The whole "Claude calling vault as a tool" UX depends on that — slower responses break the feel of interaction.

Under C, the model becomes:

- Query arrives → check if cache is stale (mtime-compare working tree vs cache build timestamp) → if stale, rebuild → execute query.
- Two failure modes: the rebuild is fast (transparent to the user, good), or the rebuild is slow (blocks the MCP query for seconds-to-minutes, bad).

Mitigations:

- **Eventually-consistent cache.** Vault answers from whatever cache it has, kicks off a background rebuild, returns possibly-stale data. Fast, but wrong data is wrong data.
- **Strict cache.** Vault blocks the query until the cache is current. Correct, but slow.
- **Watcher-driven cache.** A filesystem watcher keeps the cache up to date in real time, so query-time invalidation is rare. Best of both — but adds a long-running process that has to stay healthy.

C effectively requires the watcher-driven approach to keep MCP responsive. Which means vault needs to be a long-running process that's been watching the filesystem since boot, which means restart-heavy workflows pay the cold-start cost every time. Cold-start is the constraint.

### Operator UX shift — visibility cuts both ways

Today: "where's my vault?" lives at `~/.parachute/vault/data/<name>/`, a hidden detail most operators never touch.

Under C: visible filesystem path the operator owns directly. Probably `~/Documents/my-vault/` or `~/vaults/<name>/`. Closer to how Obsidian works — you pick a folder and that's your vault.

This is genuinely better for some operators (Obsidian power-users, anyone who likes to `cd` and `grep`). It's worse for others — one `rm -rf ~/my-vault` wipes the vault rather than a managed deletion through vault's API. The "managed product" feel diminishes; the "you own the bytes" feel rises. That's a real product choice, not just a technical one.

### Multi-tenant implications

The Computer (self-host) audience runs one vault per operator. C fits this cleanly — the operator owns the git repo, edits the working tree, pushes wherever they like.

A hypothetical Cloud (hosted) deployment would need per-tenant git repos. That's an interesting model — tenants could git push their own data, multi-machine sync is automatic, the storage substrate is git-native. But it's also operationally heavier than centralized SQLite: backup, auth, quota, garbage collection all have to be managed per repo at scale. Whether C is better or worse for hosted Cloud depends entirely on whether "tenants can git push their data" is worth the per-repo operational overhead. We don't know yet.

## 4. What an implementation sketch could look like

Not committed — illustrative.

### Install

```bash
parachute-vault clone https://github.com/me/my-vault
```

Clones the git repo into `~/Documents/my-vault/` (or wherever the operator chooses; the path is part of the prompt). Builds SQLite cache from the .md files. Starts vault server pointed at the cloned dir + cache.

### Filesystem layout (canonical)

```
~/Documents/my-vault/                # operator-visible, git-tracked
  .parachute/
    vault.yaml                       # schema version, vault meta
    schemas/<tag>.yaml               # tag schemas
    attachments/<id>/...             # or git-lfs pointer files
  notes/
    <slug>.md                        # the notes themselves
  _unpathed/<note-id>.md             # pathless notes
```

Identical to today's portable-export format — that's the point. Today's export becomes tomorrow's canonical.

### Cache layout (not canonical)

```
~/.parachute/vault/cache/<name>/sqlite.db   # rebuildable from canonical
```

Wiped and rebuilt at any time. No backups; no migrations across vault versions; if the cache gets weird, `rm -rf` and rebuild.

### Write path

```
Vault API write
  → write .md file atomically (write-tmp + rename)
  → update SQLite cache row
  → if auto-commit: git stage + commit
  → if auto-push: git push (best-effort, async)
  → return success
```

Atomicity: the SQLite update and the filesystem write are paired. If either fails, vault rolls back the other (rewriting the .md from the cache, or evicting the cache row). The git commit is non-atomic — a failure to commit leaves the working tree dirty but the cache consistent; vault retries on next write.

### Read path

```
Vault API read
  → check cache freshness (working tree mtime vs cache build timestamp)
  → if stale: invalidate affected rows, re-parse the changed .md files
  → query SQLite cache
  → return
```

The filesystem watcher (running continuously) keeps "stale" rare for normal operation. The watcher catches up after `git checkout` / `git pull` and pre-invalidates en masse.

### Conflict path

Operator edits `notes/inbox.md` in nvim. Vault API also writes to the same note (e.g., from an MCP-driven update). What happens:

- Watcher detects external mtime change on `notes/inbox.md` after vault loaded it for the write.
- Vault refuses the next write that targets the now-stale note. API returns a 409 with "this note changed underneath you, reload and retry."
- The operator (or the calling client) decides how to merge. Vault doesn't auto-resolve.

For the multi-machine case (operator on machine A pushed a change, machine B pulls and discovers a divergent local edit): standard git conflict markers in the .md file, vault flags the note as "conflicted" until the markers are resolved, operator runs `git mergetool` or edits by hand.

### Sync path

- `git pull` — operator-initiated. Vault's watcher detects the file changes, runs cache invalidation + reparse. The vault is up-to-date with the remote within seconds.
- `git push` — operator-initiated. The local commits flow to the remote. Optional auto-push at write time (matches A's auto-push toggle).

Pull and push are operator-managed by default; vault doesn't try to be a git client. The vault SPA might surface "pull in progress" / "push pending" badges, but the verbs stay in the operator's hands.

## 5. What C wouldn't fit

Three audiences C is the wrong shape for, even if the constraints listed in §3 were all mitigated.

**High-write-rate workloads.** Gitcoin Brain at scale: every job run becomes a git commit. Git scales to thousands of commits per day fine, but vault writes are async + many — burst-paste-imports, agents running in parallel, MCP-driven note updates. Either git operations become serialized (vault slows down behind the git lock), or commits batch (the audit trail gets lossy — multiple writes hidden inside one commit). Both are worse than A's debounce-and-export model, which doesn't have the per-write git overhead.

**Multi-user single-vault.** Two users editing the same vault simultaneously will hit git conflicts often. The Phase 1 multi-user design ([`2026-05-20-multi-user-phase-1.md`](./2026-05-20-multi-user-phase-1.md)) pins each user to a separate vault, which dodges this entirely — but if multi-user-single-vault ever becomes a goal (collaborative team vault, shared knowledge graph), C makes it actively harder than A/B do.

**Hosted Cloud at scale.** Per-tenant git repos work but cost operational overhead per tenant (backup, auth, quota, garbage collection). Centralized SQLite is cheaper to operate at scale. C is plausibly the right shape for Cloud Tier 1 ("bring your own git remote, we run the vault layer over it") but actively wrong for Tier 2 ("hosted vault, we manage everything, you get an API key"). Tier 2 wants SQLite or Postgres, not per-tenant git.

## 6. Conditions under which we'd revisit

No timeline. These are the signals that would make C worth seriously considering. Until at least one shows up, the door stays closed.

- **B's conflict resolution turns out to be more painful than expected.** The companion doc recommends shipping B with last-write-wins + audit log if/when bidirectional sync demand materializes. If the audit log fills up with painful collisions — operators losing real work, having to dig through audit-tagged notes to recover — the appeal of "no conflicts at all" (the C semantic, where the filesystem is canonical and there's nothing for vault to overwrite) gets real.
- **Obsidian power-users become a serious constituent.** If a meaningful share of vault adopters are editing primarily in Obsidian and treating vault as a query/MCP layer over an Obsidian-shaped knowledge graph, the impedance of A/B (sync delays, file divergence, "wait, which one is the truth") becomes a real frustration. C eliminates the impedance.
- **Performance constraints don't bite in practice.** Modern SSDs are fast; small-to-medium vaults could make cache rebuild fast enough that the §3 perf concerns are theoretical. If we measure cold-start at <500ms for 5k-note vaults on real hardware, the perf case for C becomes much stronger.
- **The "deeply integrated" instinct keeps coming up.** Operators describing what they want sounds more like "git that knows about my schemas" than "vault that exports to git." When the language shifts from "I want vault to export" to "I want git to *be* the vault," the constituency is shifting toward C.
- **Schema migrations stabilize.** Once vault hits 1.0 and the schema enters a steady state, the §3 forwards-compat concern shrinks dramatically. Old commits use the steady-state schema; no historical compat shims required.

## 7. Why we're NOT building C right now

Direct, in the voice of the trust-gradient pattern.

- **A delivers 80% of the value for 20% of the complexity.** Git-backed history, audit trail, sharing-as-git-clone, browseable diffs — A gives all of this. C gives *more* on top (Obsidian-native editing, native git semantics in the operator's shell, distributed-by-default sync), but the marginal value isn't worth the architectural cost yet.
- **C is a bigger rewrite than vault's previous evolution combined.** Every layer changes: install ("clone" replaces "install"), read path (cache-rebuild on stale), write path (filesystem + git become co-canonical with SQLite), conflict model (git's merge model meets typed links), upgrade path (schema migrations vs git-immutable history). Validating each of those layers in production is a multi-quarter effort.
- **Reversibility is low.** Once we commit to "git is canonical," walking back is painful — every operator who cloned their vault now expects git to be canonical, and reversing means a forced migration off git for everyone. A is reversible (just stop running the mirror); C isn't.
- **The signals in §6 haven't appeared yet.** Build for what's true, not what might be. The constituency for C is hypothetical right now; the constituency for A (Gitcoin Brain, owner-operators backing up to git) is real and waiting.
- **B might be enough.** Bidirectional sync gives "edit in Obsidian" UX without the canonical-store flip. We don't yet know whether B's conflict resolution actually hurts enough to need C's no-conflict semantic. Ship A, learn whether B is needed, learn whether B is sufficient. C waits.
- **The trust-gradient pattern's framing applies.** Smaller primitives for smaller, well-named audiences. C is the right shape for a narrower audience (git-native power users who treat the filesystem as the product) than A/B reaches (anyone who wants a backed-up, browseable, sharable vault). Don't try to span both audiences in one primitive; ship the wider one first, ship the narrower one if and when its audience demands it.

## 8. Open questions (for future-Aaron to revisit)

The questions that would need real answers BEFORE committing to C. Each one is a load-bearing decision; getting any of them wrong is expensive.

1. **What's the cache rebuild SLA?** How long can operators tolerate vault being unavailable on restart? What's the upper bound (1 second? 10 seconds? 60 seconds?) that makes C viable, and at what vault size does that bound get exceeded? Measure on real hardware before committing.
2. **Conflict resolution UX?** What does the operator see when their nvim edit collides with a vault API write? Inline conflict markers in the .md file (familiar to coders, foreign to non-coders)? A dedicated conflict UI in the vault SPA (more design work)? Refuse-and-explain (predictable, restrictive)? The default surface shapes who the audience is.
3. **Attachment story?** git-lfs (well-supported, adds operator setup), git-annex (more powerful, weirder), external blob store (defeats canonicality). Each has consequences for sharing, cloning, and the "everything is in git" claim.
4. **Schema evolution across history?** How does vault interpret a 2-year-old commit's .md files written under a since-deleted tag schema? Forwards-compat shim (operationally expensive forever)? Read-only old commits (breaks history browsability)? Rewrite history on migration (destructive)?
5. **`parachute-vault clone` semantics.** Does it init from a fresh schema (and the cloned repo's content gets re-interpreted under the new schema) OR adopt the schema from the cloned repo (and vault has to support whatever schema version it finds)? The latter is more correct; the former is simpler.
6. **Multi-vault layout.** The companion doc resolved this for A as "per-vault-repo." Confirm it holds under C (each vault = one git repo, period). The alternative — multiple vaults in one repo — interacts badly with `git pull` and conflict resolution.
7. **MCP query latency under cache-rebuild.** Acceptable degradation (queries are slower during invalidation but still complete), or stop-the-world disaster (MCP times out, Claude's tool-use breaks)? Watcher-driven cache is probably the answer, but it needs to be measured under real load.
8. **What happens to the cookbook?** Today's [`vault-portable-export` recipe](https://github.com/ParachuteComputer/parachute-patterns/blob/main/cookbook/vault-portable-export.md) becomes the *canonical format* under C, not a cookbook recipe. The cookbook entry either migrates to a format spec or dissolves into vault's core docs. Question of where the spec lives, not whether.

## 9. Cross-references

- [`2026-05-20-vault-as-git-projection.md`](./2026-05-20-vault-as-git-projection.md) — the companion design. If you're choosing between A and C, read both.
- [`parachute-patterns/patterns/trust-gradient-isolation.md`](https://github.com/ParachuteComputer/parachute-patterns/blob/main/patterns/trust-gradient-isolation.md) — the precedent for "name the audience, ship the smallest viable primitive." This thought experiment names C's audience (git-native power-users + Obsidian-first editors) and explicitly chooses not to ship for them yet because A's audience is wider and ready now.
- [`parachute-patterns/cookbook/vault-portable-export.md`](https://github.com/ParachuteComputer/parachute-patterns/blob/main/cookbook/vault-portable-export.md) — the format that would become canonical under C. The lossless round-trip property makes C's "git is the truth" claim plausible; without it, C wouldn't be feasible at all.
- [`2026-05-20-multi-user-phase-1.md`](./2026-05-20-multi-user-phase-1.md) — the multi-user design that pins users to separate vaults. Important to read alongside C because C amplifies multi-user-single-vault pain (see §5).

## Closing — what this doc is for

This is a structured exploration, not a plan. If C ever becomes worth shipping, the work in §6 (recognize the signals), §3 (size the costs), §4 (sketch the implementation), and §8 (answer the load-bearing questions) is the starting point. If C never becomes worth shipping, the trade-offs here help articulate *why* A was the right call — not because C is bad, but because C's audience didn't materialize and A's did.

The door is open. Closing it requires real signal. Opening it through requires real commitment. Today we're standing in front of it; tomorrow we're shipping A; the day we walk through the door is the day at least one §6 condition is loudly true.
