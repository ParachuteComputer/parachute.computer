# Real git for cloud vaults — research brief & recommendation

> Ratified by Aaron 2026-07-03; see `Work/launch-readiness-course` in the team vault.

**Date:** 2026-07-03 · **Status:** research deliverable (Aaron's ask: deep research in lieu of the rejected GitHub-API backup) · **Decision-ready**

## TL;DR

Genuine git for cloud vaults — including `git clone https://u.parachute.computer/vault/<name>.git` — is credibly buildable, three ways, and the landscape shifted in April 2026: **Cloudflare now ships a first-party product, "Artifacts" ("versioned storage that speaks Git"), that is almost exactly this feature** — a tiny Zig→WASM git engine in a Durable Object per repo, real clone/fetch/push, currently in **closed beta**.

**Recommendation: B-then-A, with C alongside.**
- **Apply for the Artifacts beta today** (free; decide nothing on its timeline).
- **Days:** ship `parachute vault mirror --from <cloud-vault-url>` — the CLI materializes a *real local git repo* from export tarballs (full, then incremental), reusing the self-host commit machinery. Cloud users get true git history on their own disk, pushable to any remote they own. This is also the portability/exit story forever.
- **Days-to-a-week:** the **incremental commit-builder** in the vault DO + a bare repo in R2, served as **read-only dumb-HTTP git** — the headline clone URL works, token-gated exactly like surface deploy tokens.
- **1–2 weeks, when polish is warranted:** smart-HTTP upload-pack (fast clones/fetches), cribbing the MIT-licensed git-on-cloudflare patterns.
- **If/when Artifacts opens:** point the same commit-builder at an Artifacts remote and retire our serve path. It's the upgrade, never the dependency.

## The load-bearing insight

Git is content-addressed, so **building the next commit is O(changed notes), not O(vault)**: keep path→blob-oid maps in DO SQLite, hash only what changed (WebCrypto SHA-1 + CompressionStream zlib), rebuild only the touched tree spine, emit one commit. A 100 MB vault never transits the 128 MB isolate except at initial build, which chunks across requests. The portable-md serializer is already byte-stable across runtimes, so diffs are clean and the repo doubles as the import source for self-host migration (`git clone` → `parachute-vault import`). Write-side cost: milliseconds + pennies (R2 egress is free).

## Pathways compared (honest)

| Path | What | Effort | Risk |
|---|---|---|---|
| **A. Artifacts** | Push commits to CF's first-party git store; proxy our domain over it, our token gate | ~days once beta access | Closed beta; their timeline; $0.50/GB-mo (tiny for text repos) |
| **B1. DIY dumb-HTTP** | Bare repo in R2, static-served; real `git clone`, slower | days | Nearly none; nightly repack keeps request counts sane |
| **B2. DIY smart-HTTP** | upload-pack (clone/fetch) served by us; proven twice on this exact substrate | 1–2 wks + tail | We own a git server (read-only halves the protocol — no push parsing) |
| **C. Client-materialized** | CLI builds the repo locally from the export contract; fast-export stream later | days | No hosted URL — complement, not the headline |
| ~~D. bun-mirror-from-remote~~ | Remote-replica sync protocol | weeks | Rebuilds "run a box" burden; its useful kernel IS pathway C |
| ~~E. GitHub-API commits~~ | Rejected by Aaron | — | Residual role only: optional mirror push target later |

## Don't-do list

wasm-git/libgit2-WASM in the DO (Gitlip's cautionary tale: custom Emscripten fs, custom pack GC, memory ceilings); isomorphic-git whole-repo ops in-DO (documented memory blowups; incremental/low-level use only); receive-pack/user-push into vaults (that's bidirectional sync in a git costume — read-only remotes, explicitly); betting the ship date on Artifacts.

## How this fits the roadmap

- Wave 5 head: the **versions table in core** later backfills fine-grained history into these same repos via fast-export — the two tracks compose, neither blocks the other.
- Snapshot history (Wave 4, R2 + GFS) is unaffected — it's the everyday-user restore story; git is the power-user/history/migration story.
- Consistency bonus: the token UX (`vault:<name>:read`, Basic `x-access-token`) matches the shipped Surface Git Transport exactly.

*(Full landscape detail, platform limits, costs, and sources are in the underlying research — Artifacts docs/blog, git-on-cloudflare (MIT), Gitlip post-mortems, isomorphic-git memory issues, CF platform limits. Available on request; key URLs embedded in the team-vault copy.)*
