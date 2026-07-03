# From Here to a Real Product — the Course of Action

> Ratified by Aaron 2026-07-03; see `Work/launch-readiness-course` in the team vault.

**Date:** 2026-07-03 · **Author:** Uni (Aaron + Claude) · **Status:** RATIFIED 2026-07-03 — Aaron's answers to Part IV are folded into the [execution plan](/design/2026-07-03-launch-execution-plan/)
**Grounding:** three code-level investigations tonight (cloud caps/history/export machinery; vault seeding + Surface Starter + importers; the dormant Stripe control plane). Every "exists today" claim below is verified at file level.

---

## Part I — The experience we're building (the through-line)

One person, start to finish. Every wave below serves a moment in this story:

1. **She finds parachute.computer.** The page doesn't explain — it lets her drop thoughts into a vault and watch them connect. Thirty seconds in, she gets it. The copy sounds like people, not software.
2. **She clicks Get a vault.** Email, magic link, done. No password invented, nothing to remember.
3. **She names her vault and lands somewhere warm.** Not a dashboard — a room. Three notes are already there, connected, showing her the shape of the thing. A quiet checklist knows where she is: open your notes ✓, write one ✓, connect your AI, put it on your phone.
4. **She writes for a week.** Phone, laptop. She pastes one URL into Claude and her AI starts remembering her. Nothing has asked her for money.
5. **The vault becomes where her mind lives.** She pays $3 — not because she hit a wall, but for more room, nightly snapshots she can restore, and knowing it's cared for.
6. **Any day, she can leave with everything.** Export always works — free or paid, over cap or not. That promise is what makes everything else safe to say.

**Principles that fall out:**
- The next step is always a **door, not a manual** (proven today: console → Notes is one click + one approve).
- **The product teaches the product** — guides are notes in the vault; the graph demos itself.
- **Money buys room and care, never rescue** — no feature held hostage; caps warn softly, stop writes gently, never touch reads or export.
- **One canonical source per thing** — one starter-pack definition, one wire contract, one copy voice.

---

## Part II — The workstreams

### A. Homepage migration (parachute.computer)

- **/v2 becomes the homepage** after two gates: the **FUBU copy session** (you, Neil, Jon hand-write the hero, ledes, and join card — I fit everything around your words) and a final design read.
- Mechanics: landing content takes index position; `/v2/` redirects home; blog/docs/start/roadmap keep routes, reachable from the footer; a proper **og-image** (the parachute mark on paper) so shares look right; a patterns **migration file** ships with the promotion (canonical-path change).
- **Cloudflare Web Analytics** (cookieless, free) so we can *see* the funnel: land → play → signup-click → account → first note. Without it, every future design debate is vibes.
- **ToS + Privacy pages** (short, honest, PBC-voiced) — legally needed before payments; written now so Wave 4 isn't blocked.

### B. Production posture (cloud infrastructure)

- **Environments:** `[env.production]` with `ENVIRONMENT=production` (issue #33) + a staging deploy; production D1/R2 separated from dev debris. Same CF account for now; a dedicated account is a later, disruptive move made when revenue justifies it.
- **CI/CD on parachute-cloud** (none exists): typecheck + both vitest suites on PR; merge→staging deploy; tag→production deploy. Ends the local-gates-in-PR-bodies era.
- **Observability:** Workers Logs retention; alerts on `magic_link_send_failed` (wired tonight) and 5xx rate; /health uptime checks; a small weekly ops digest email.
- **Fix the live leak first:** every export already writes a tarball to `vault-<name>/exports/` in R2 and **nothing prunes them** (a flagged pre-deploy TODO). Retention/GC lands here, before any snapshot cron makes it worse.
- **DR:** verify D1 Time Travel (30-day PITR) covers identity; the vault side becomes the Wave-4 snapshot machinery (same artifact).
- **Security before money:** KDF strengthen (#28), DO-backed rate limiter (#30), CORS posture reconcile (#35), abuse-fence pass under the production flag.

### C. Guided arrival (onboarding as interface)

- **Console first-run:** zero-vaults state becomes one warm action — *name your vault* — plus two research questions (what do you take notes in / what's the first thing your AI should remember). **The second answer is written into the vault as her actual first note** — market research becomes onboarding.
- **Checklist card** (per-user, persisted, done-detected where cheap): Open your notes → Write a note → Connect your AI → Add to your phone → Import your old notes. Each item a door with a 30-second guide. Import is real *today* for Obsidian-zip + loose markdown — notes-ui's importer runs client-side against any connected vault, cloud included (verified). Apple Notes/Notion stay roadmap.
- **Connect-your-AI card done right:** Claude custom-connector walkthrough with a copy-button MCP URL first; the CLI command as the nerd footnote.
- **Email drip** (Email Sending is live as of tonight): day-0 welcome with your three links; day-3 "connect your AI?" *only if* no token activity; day-14 feedback ask. Three emails, behavior-aware, unsubscribe honored.
- **In Notes:** empty-states that teach; the welcome web (shipped tonight) stays the in-app guide.

### D. Money — metering, plans, payments, admin

**What already exists (verified):** aggregate storage-cap enforcement in the vault DO — live `databaseSize` + an O(1) R2 byte-meter, 1 GiB global fallback, clean 413 shape, deletes always allowed, 100 MB upload gate. And crucially: a **per-vault `cap_bytes` override seam that nothing writes yet** — the exact hook plans wire into.

1. **Plan column + wiring:** add `plan` to identity D1 (`vaults`/`users`); on plan change, the issuer pushes `cap_bytes` into the vault DO's existing config seam. Vault-count cap enforced at `createVault` (trivial — ownership table exists).
2. **Metering rollup:** a scheduled worker enumerates the `vaults` table, pulls `databaseSize + r2_bytes` per DO, writes a daily D1 `usage` row. Powers admin, cap warnings, and billing sanity.
3. **Plans (proposal):**
   - **Free** — 1 vault, 100 MB (ratified value — supersedes the 1 GiB draft figure; motivates the paid step and caps free-tier COGS structurally, storage costs us ~2¢/GB-mo).
   - **Parachute — $3/mo or $30/yr** — 5 vaults, 10 GiB total, **nightly snapshot history with 30-day restore**, priority support.
   - One paid tier at launch. A bigger tier only when real users ask for it.
4. **Cap behavior:** warn banner + email at 100%, writes stop at 120% (413s already shaped), **reads and export never stop**. Downgrades never delete — over-cap vaults go write-limited with a long, kind runway.
5. **Stripe:** port the dormant control plane's verified-good core — `stripe-client` (Workers-correct webhook verification), hosted Checkout with tenant correlation, the two-layer-idempotent webhook router, invoice/subscription lifecycle handlers, soft-dunning posture (flag, never auto-suspend), 3-day/30-day grace constants — all portable with their tests, needing only Drizzle→raw-D1 rewrites. **Build new:** customer portal (never existed), the entitlement shape (old one was VM-sizes), Stripe Tax on.
6. **Admin console** (`/admin`, operator-role-gated via the real session model, replacing the old bearer pattern): users, vaults, usage, plan overrides/comps, suspend switch, recent send-failures, signups/day. Read + moderate; no impersonation.

### E. History (the git question, answered)

**Ground truth:** core schema has no versions table; note updates are destructive in both runtimes. Self-host "history" is git *outside* the DB (export-watch → git commit) — impossible in workerd. The cloud's export tarball (portable-md, byte-shaped like self-host) already lands in R2 per export.

- **Now (Wave 4, the paid differentiator): snapshot history.** A nightly cron exports each vault to R2 (the machinery is half-built; needs the cron, vault enumeration from D1, and the retention/GC from Wave 2). **Paid:** 30 daily + 12 monthly restore points, one-click restore-to-new-vault. **Free:** weekly internal snapshot for *our* disaster recovery only.
- **Not metered into the user's quota.** Charging people for their own safety net teaches them to fear it; history is included room with fixed retention. (This answers your "paid offering vs count into storage" question: paid feature, flat retention, never quota.)
- **Honest v1 caveat:** the sync export excludes attachment binaries (documented divergence — the DO can't await R2 mid-export). Restore v1 = notes + links + tags complete, attachments referenced but not restored. An async attachment-inclusive export is the follow-up *before* we market "full restore."
- **Later (core roadmap, lifts both runtimes): note-level version history** in `@openparachute/core` — a versions table on update, "history of this note" in Notes. That's the real time machine. Git-remote access to cloud vaults (à la Surface Git Transport) is the power-user tail — noted, not scheduled.

### F. Vault + starter unification (the seed question, answered)

**Ground truth:** the bun vault seeds two notes (Getting Started + Surface Starter) from `core/src/onboarding.ts`, voiced *to a connected AI*. The cloud seeds three notes + three tags from its own `welcome.ts`, voiced *to a person* — the divergence was deliberate (different audiences), but the content now lives in two places.

- **Named seed packs in core** (`core/src/seed-packs.ts`) — both runtimes already import core subpaths and share the same idempotent Store-write shape, so this is cheap. Three packs:
  - `welcome` — the person-voiced three-note web + Notes' required tags (what cloud ships tonight).
  - `getting-started` — the AI-orientation guide. **Keeps its seat**: `vault-projection` surfaces it as the "start here" pointer to every connecting AI, for cloud vaults too.
  - `surface-starter` — **a button, not a default** (your instinct, confirmed safe: nothing depends on it but one wikilink, which gets softened). Console button ("Building a surface? Add the guide") + `parachute vault add-pack surface-starter` CLI. The pack pattern also gives us future packs — journal, meeting notes — that seed the L2 story.
- **Defaults:** both runtimes seed `welcome` + `getting-started`. Self-hosters get the friendly web too (their graph view shouldn't start empty either); cloud vaults get the AI orientation (their AI connects via MCP just the same).
- **Parity pinned by a cross-runtime conformance test** (content + Notes' required tags), so the schema-banner class of bug can't return.

---

## Part III — The waves (order, gates, size)

| # | Wave | Contents | Gate to start | Size |
|---|---|---|---|---|
| 1 | **Front door** | FUBU copy session → homepage promotion + redirects/og + CF analytics + ToS/Privacy drafts | The team hour (only human-gated item) | 1 session + the hour |
| 2 | **Production posture** | env.production + staging, CI/CD, observability, export-R2 GC (live leak), DR verify, KDF/limiter/CORS | none — starts immediately, parallel with 1 | 1–2 sessions |
| 3 | **Guided arrival** | Console first-run + checklist + Connect-AI card + drip + seed packs in core + Surface-Starter button | after 2's staging exists (ships safer) | ~2 sessions |
| 4 | **Money** | plan column + cap wiring → metering rollup → admin console → Stripe port + portal → snapshot history (paid) | Aaron: Stripe keys, pricing sign-off, ToS review | 2–3 sessions |
| 5 | **Deep history** | note-level versions in core → Notes history UI; git-remote tail | real user pull | unscheduled |

Waves 1+2 in parallel; 3 after 2; 4 after 3 — **onboarding before monetization**: people pay for a thing they already love. The live browser E2E re-runs at every wave boundary as the funnel's regression suite. Migration files ship with every canonical-path change. Every PR reviewer-gated as tonight.

---

## Part IV — Decisions I need from you (the review)

1. **Pricing:** Free = 1 vault / 1 GiB (today's cap, unchanged). Paid = $3/mo or $30/yr, 5 vaults / 10 GiB + snapshot history. Yes / adjust numbers? *[Answered: adjusted — free tier is **100 MB**; see the execution plan's locked decisions.]*
2. **One paid tier at launch** — no Plus until users ask. Yes?
3. **History = paid snapshot feature, fixed retention, never metered into quota.** Yes?
4. **Homepage promotion after the FUBU session** — schedule the team hour. Yes?
5. **Production = env-split in the current CF account now; dedicated account later.** Yes?
6. **Surface Starter → a button/pack, out of the default seed; both runtimes seed welcome + getting-started.** Confirm?
7. **Email drip as described** (3 emails, behavior-aware, unsubscribe honored). Comfortable?
8. **Free-tier restore:** internal-DR-only for free (paid gets restore points) — or should free users get a 7-day restore too?

Answer these (even tersely, by number) and I execute the whole course, wave by wave, reporting at each boundary.
