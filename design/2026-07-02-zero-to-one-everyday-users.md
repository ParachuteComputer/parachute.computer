# Zero to One for Everyday Users — the first five minutes

**Date:** 2026-07-02 · **Status:** proposal (Aaron to ratify sequencing; steps 1–4 shipped/in-PR same day) · **Layer:** L0→L1

## The problem, stated plainly

We now have every piece of the everyday-user story running in production-shaped form:

- **parachute.computer/v2** — the landing page that gives a taste (interactive vault) and opens three doors.
- **cloud.parachute.computer** — self-serve signup (magic link, passwordless), vault creation, ownership-enforced OAuth.
- **u.parachute.computer/vault/&lt;name&gt;** — a real vault (DO-per-vault), same wire contract as self-hosted.
- **notes.parachute.computer** — the Notes PWA as a standalone static deploy, able to connect to *any* vault via OAuth (unblocked 2026-07-02 by cloud#34's CORS fix).
- **Any AI** — Claude et al. via MCP connector against the vault.

What we did *not* have is a **path** through the pieces. Each hop required knowledge an everyday
person doesn't have:

1. After creating a vault, the console said *"connect your AI with the command below"* and offered
   `claude mcp add --transport http …` — **a terminal command as the default next step.**
2. Nothing anywhere pointed at notes.parachute.computer. The user who just got a vault had no room
   to walk into.
3. If they found Notes on their own, the Add-Vault screen asked for a **"hub URL"** with placeholder
   `http://localhost:1939` — self-host vocabulary shown to a cloud user — and then made them
   **re-type the vault name** free-text at the consent screen (a typo bounces them back with a
   cryptic error code, no description).
4. A fresh vault is an empty sea — no first note teaching write → link → ask-your-AI.

The insight from the landing-page work applies to the whole funnel: **show, don't tell — and the
next step must always be a door, not a manual.**

## Proof it works: the live end-to-end run (2026-07-02)

A Playwright-driven browser session ran the entire journey against the live dev deploys, no code
stubs: **signup at cloud.parachute.computer (magic link) → console → create vault `e2e-notes` →
notes.parachute.computer → Add Vault (pasted URL) → OAuth discovery + DCR + PKCE (both cross-origin
CORS legs, shipped that morning in cloud#34) → consent → connected → wrote "First landing 🪂" →
note confirmed server-side via the vault REST API.** Every step passed. The deployed Notes bundle
is current with source. The four papercuts found (error-description swallowed on the OAuth
callback; connected vault displayed as the issuer origin instead of its name; the re-type-at-consent
step; an invalid `pattern` regex on the vault-name input) are exactly items 3–4 in the gap list
below and are in PR the same day.

## The journey we're designing (target state)

```
land → play the demo → "Get a vault"
  → email → magic link → console                        (exists, works)
  → name your vault → created                            (exists, works)
  → [Open your notes]  ← THE MISSING DOOR                (small: one console button)
  → notes.parachute.computer/?add=<vault-url>            (small: one query param)
  → OAuth approve (already signed in — one click)        (exists, works post-#34)
  → land in Notes, welcome note waiting                  (small: seeded note)
  → write the first real note                            ← 0→1 ACHIEVED, ~90 seconds
  → later, from the console: [Connect your AI]           (exists as copy-paste; needs a friendlier card)
```

Success metric for L1 first-contact: **time-to-first-note < 2 minutes** from landing, and
**time-to-AI-connected < 5** — both demoable live, end to end, no terminal.

## The gap list (smallest changes, in dependency order)

| # | Change | Repo | Status |
|---|---|---|---|
| 1 | CORS on issuer token/register endpoints (browser PKCE) | parachute-cloud | ✅ shipped (#34) |
| 2 | E2E proof of the whole chain in a real browser | — | ✅ passed (above) |
| 3 | Console post-create: **"Open your notes"** primary door → `notes.parachute.computer/?add=<vault-url>`; demote the CLI command to the "Connect your AI" card; token response carries the vault name (hub parity); fix the vault-name input pattern | parachute-cloud | in PR |
| 4 | Notes PWA: accept `?add=<url>` → auto-begin OAuth; Add-Vault copy for both audiences; derive the `vault=` consent hint from a pasted `/vault/<name>` URL (no re-typing); surface `error_description` on OAuth failures | parachute-surface (notes-ui) | in PR |
| 5 | Seed a welcome note 🪂 at vault creation (teaches write/link/ask; deletable). Leaning a tiny three-note web so the graph isn't empty and the /v2 demo promise carries into the product | parachute-cloud (vault DO init) | proposed |
| 6 | Console "Connect your AI" card: per-client instructions (Claude custom connector first, MCP URL front and center; the CLI command as the nerd footnote) | parachute-cloud | proposed |
| 7 | Landing page: once 3+4 are live, "try the beta" can honestly promise notes-in-two-minutes | parachute.computer | copy |

Deliberately **not** in this arc: payments/caps enforcement UI (the cloud v1 plan owns it), scribe,
custom surfaces, per-vault subdomains (Enterprise-gated wildcard DNS), native apps.

## Open questions for Aaron

- **Vault picker vs. paste**: after OAuth against cloud, Notes could list the vaults you own
  (the issuer knows) instead of asking for a URL at all. Bigger seam (new issuer endpoint) — worth
  it as arc 2? The `?add=` param makes it moot for the console-originated path.
- **Welcome-note content**: one note or the three-note web? (Proposal above leans three-note.)
- **notes.parachute.computer deploy cadence**: wire the deploy workflow to auto-run on notes-ui
  merges once it's load-bearing?
- **The GH-Pages 404-status quirk**: the standalone PWA serves SPA deep links via the 404.html
  fallback (works, but every deep link is an HTTP 404 in logs/monitoring — and search engines see
  it too). Fine for beta; a Worker-hosted static deploy would fix status codes when it matters.
