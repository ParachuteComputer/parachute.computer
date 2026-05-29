---
layout: post.njk
title: "Starter prompt — set up your vault"
description: "Paste this into any AI client with your vault's MCP server connected — Claude.ai, Claude Code, Codex, Goose, Cursor. The AI will look at what's already in your vault, interview you, and propose a structure."
permalink: /onboarding/vault-setup/
date: 2026-05-26T12:00:00
---

This is one of two starter prompts ([the other is for building a custom UI](/onboarding/surface-build/)). Paste the block below into any AI client with your vault's MCP server connected — **Claude.ai** (with MCP enabled), Claude Code, Codex, Goose, Cursor, OpenCode, or any other MCP-aware client.

The prompt assumes your MCP is already wired up. The first thing the AI does is try a few MCP tools — if those fail, it'll ask you to set up MCP first and point you at the right command for your client. Not connected yet? [Connecting MCP clients](/install/#connect-mcp-clients) has the per-client steps; the endpoint is always `<hub-origin>/vault/<name>/mcp`.

---

## Copy this:

```markdown
I'm setting up a Parachute Vault and I want you to help me think through
how to structure it. The vault is a knowledge graph with notes, tags,
and links — bare primitives, no opinions baked in. Your job is to help
me figure out my own opinions.

You have these MCP tools available against my vault:
- `create-note` (single or batch) — content, tags, links, metadata
- `query-notes` — single by ID/path, filter, search, graph traversal
- `update-note` — content, tags, links, metadata merge
- `delete-note`
- `list-tags` — with schema detail
- `update-tag` — upsert tag schema (description, fields, parents)
- `delete-tag`
- `find-path` — BFS shortest path between two notes
- `vault-info` — vault description + stats

Don't make assumptions about my structure. Look at what's already
here first, then interview me.

## Round 0: orient (read the current vault — or detect missing MCP)

Before asking me anything, call:
- `vault-info` — see if there's an existing vault description and
  the basic stats (note count, tag count).
- `list-tags` (with schema detail) — see what tag conventions already
  exist, if any.
- `query-notes` with an empty filter (limit 10) — see if there are
  any notes at all, and what they look like.

**If those tools aren't available** (you can't see them in your tool
list, or the calls fail with "tool not found"), the vault's MCP isn't
connected to this client yet. Stop here and tell me:

> "I don't see Parachute Vault's MCP tools. Add the vault as an MCP
> server in your client first. The endpoint is always
> `<hub-origin>/vault/<name>/mcp` — your hub's URL (the same one you
> sign in at), your vault name, and the literal `/mcp` suffix (the
> bare `/vault/<name>` path is a metadata page, not the MCP endpoint).
> For Claude Code: `claude mcp add --transport http <name>
> <hub-origin>/vault/<name>/mcp` (it walks you through hub sign-in
> automatically), or `parachute-vault mcp-install` on the machine
> running the hub. For Claude.ai (web): Settings → Connectors → add a
> custom connector pointing at that URL. For Codex / Goose / OpenCode:
> paste that URL into your client's MCP config. Full per-client steps:
> https://parachute.computer/install/#connect-mcp-clients —
> re-paste this prompt once they're wired up."

**If the tools work**, report what you find back to me in a short
paragraph. Two cases:

- **Empty vault** (no notes, no tags, default vault description):
  "You have a blank vault. Let's design it together."
- **Existing vault** (has notes or tags or a custom description):
  "Here's what you already have: [N notes, M tags, brief
  summary]. We can extend this, restructure it, or start fresh.
  Which sounds right?"

The interview that follows adapts. Don't pretend the vault is empty
if it isn't, and don't propose new tag schemas that conflict with
existing ones unless I ask for that.

## Round 1: where my data lives

Ask me one question at a time. Don't batch. Adapt your follow-ups to
what I say.

Start with: "Where do your notes and thoughts currently live? List
every place — apps, files, your head, post-it notes, voice memos, email
drafts, whatever. Don't filter."

Once I've listed places, ask about:
- Which of those do I want to bring into the vault?
- Which do I want to leave outside it (mental clarity matters here)?
- What format are the import-worthy ones in? (Obsidian markdown,
  Apple Notes, Notion exports, plain text, voice memo transcripts,
  iMessage, Roam, Logseq, RSS subscriptions, anything else).

**For each import source, propose a concrete path:**

- **Obsidian** → built-in lossless import:
  `parachute-vault import <path-to-vault>`. Walk me through it.
  IDs preserved, schemas restored, frontmatter intact.
- **Apple Notes / iMessage / Notion** → no built-in importer.
  Offer to write me a script: a short Bun / Python script that
  reads from the source's export format and writes to the vault via
  REST. You can mint a narrow `vault:<name>:write` token via MCP
  for the script to use (you'll never see the raw token — it lives
  in an env var the script reads). Tell me roughly how long the
  script will be before generating it, so I can opt out if I want
  to do it by hand instead.
- **Loose markdown / text files in a folder** → write a glob-and-
  POST script using the same pattern. ~20 lines.
- **Voice memos** → if scribe is running on this hub, mention that
  `parachute-scribe` can transcribe them; piping the transcripts
  into the vault is then the same scripted-import shape.

If I prefer to import nothing and start fresh, that's fine too.
Don't push.

## Round 2: how I think

Once I've named where my data is, ask me how I naturally think about
my work and life. Some prompts (use whichever lands):
- "What are the big categories of things you're tending to right now?"
- "If you had to name 3-5 active projects, what are they?"
- "Are there people who recur across notes? Places? Recurring meetings?"
- "Do you have rituals — daily writes, weekly reviews, something else?"

Listen for: entities (people, projects, places), workflows (capture,
review, plan), preferred levels of structure (some operators want
schemas; others want pure free-text; both are fine).

## Round 3: propose a structure

Based on what I told you, propose a baseline. The vault supports two
organizing primitives:

1. **Tags** — `list-tags` and `update-tag` let you define typed tags
   with optional schemas. A `#person` tag can declare fields like
   `email` and `phone`; a `#project` tag can declare `status` and
   `owner`. Tag schemas help the AI (you) write structured notes that
   surface in queries. Treat tags as types, not just labels.

2. **Paths** — every note has an optional `path` field (like a folder
   in the vault). Paths organize browsing; they're independent of
   tags. `notes/2026/may/standup-2026-05-26` is fine. Some people
   prefer flat notes with tag-driven organization; both work, but
   you'll want at least one of the two — wide-open chaos is hard to
   navigate at 1000+ notes.

Propose:
- A starting set of tags (with field schemas where useful). Recommend
  at least 3-4 to start so the vault has handles to grab.
- A starting path convention if I want one (skip if I'm going pure-tag).
- A short starter note describing the conventions we just agreed on,
  so future-AI sessions reading the vault can orient quickly.

Ask me to push back. Don't commit anything to the vault until I say so.

## Round 4: execute

Once I approve the structure:
- `update-tag` for each proposed tag with its schema
- `create-note` for any starter notes (use the proposed paths)
- `vault-info` to set a vault description that future-AI sessions
  will read

## Round 5: import (only if I have data to bring in)

For each source we agreed to import in Round 1. **Default to whichever
path requires the least terminal use from me.**

### Path 1: Direct via MCP (default for small + medium imports)

This is the cleanest path — no shell, no script, no token handoff.
You have `create-note` (batch variant supports many at once) and
`update-tag` via MCP. For most imports under ~1000 notes:

1. Ask me to paste the source content directly into chat, OR ask me
   to point you at a file/folder if your MCP client has a filesystem
   tool wired up.
2. Parse the content per source (Obsidian markdown frontmatter,
   Notion CSV/JSON, Apple Notes plist, etc.).
3. Map each source-record → a Parachute note with `content`, `tags`,
   `path`, `metadata`. Use the tag schemas + path convention we
   agreed in Round 3.
4. Dry-run summary first: "I'm going to create N notes across M tags.
   First 3 examples: [...]." Confirm before committing.
5. Batch `create-note` calls (50-100 per batch). Report progress.
6. `vault-info` after — note count should match.

This works for: pasted text dumps, exported JSON/CSV in chat,
small-to-medium markdown collections accessible via filesystem MCP.

### Path 2: Built-in Obsidian importer (CLI required on the hub host)

If I'm importing an existing Obsidian vault and I (or someone with
shell access on the hub) can run a command:

  `parachute-vault import <path-to-vault>`

This is lossless: IDs preserved, schemas restored, frontmatter
intact. Faster than the MCP path for large Obsidian vaults.

If I can't access the hub's shell (most non-developer friends), fall
back to Path 1 — read the Obsidian vault's markdown files via MCP
filesystem tool and batch-create them.

### Path 3: Scripted import (large data or live API sources — power-user only)

**Caveat: this path needs me to run a script in a terminal. Most
friends won't be doing this.** Skip if I'm not comfortable with
"open Terminal, set an env var, run `bun script.ts`."

Use Path 3 only when:
- The import is too large for chat-pasted MCP batching (10k+ notes)
- The source is a live API (RSS, IMAP, etc.) that needs to fetch on
  every run
- I explicitly ask for a script

If we go this route, mint a vault token. Every option below issues a
**hub JWT** (revocable via the hub's token registry); the legacy `pvt_*`
tokens are being retired. Pick the one that fits:

1. Get a token for the script. Options, least-to-most terminal use:
   - **Ephemeral, AI-driven (best for a one-shot import):** if you've
     given me a `vault:<name>:admin` MCP session, I can call the
     `manage-token` MCP tool myself — `action: "mint"` with a narrow
     scope (`vault:write`) and a short TTL. These are short-lived hub
     JWTs (default 15 min, max 1 hour), pinned to this vault and
     attenuated to a subset of my own scope. You never see the raw
     token — it goes straight into an env var the script reads, and I
     revoke it (`action: "revoke"`) the moment the import finishes.
   - **Durable, for a script you'll re-run (CI, scheduled sync):** on
     the hub host, run
     `parachute auth mint-token --scope vault:<name>:write` (default
     lifetime 90 days). It prints the JWT to stdout — pipe it into the
     script's env, don't paste it back into chat.
   - **From the vault admin SPA:** the Tokens page mints durable hub
     JWTs with an optional tag-scoped allowlist. Hand me the token via
     an env var, not chat.

2. Generate a small Bun script that uses
   `@openparachute/surface-client`'s `VaultClient` (the canonical
   JS/TS scripting library for talking to a vault). Shape:

   ```ts
   import { VaultClient } from "@openparachute/surface-client";

   const vault = new VaultClient({
     hubOrigin: "https://...",     // my hub URL
     vaultName: "default",          // or the name I gave
     token: process.env.PARACHUTE_TOKEN!,
   });

   // ...read source data, transform into the vault note shape...

   const result = await vault.createNotes(notes);
   console.log(`Created ${result.created.length}, skipped ${result.skipped.length}`);
   ```

   Dry-run first, prompt for confirmation, then commit. The lib
   handles auth headers + error mapping; no raw fetch needed.

3. Hand me the script + the command:
   `PARACHUTE_TOKEN=<token> bun script.ts`

4. Revoke the token when the import is done. If I minted it via
   `manage-token`, I'll revoke it myself (`action: "revoke"` with the
   `jti` from the mint). Otherwise revoke it from the vault admin SPA's
   Tokens page, or — on the hub host — run
   `parachute auth revoke-token <jti>`.

**For Python** or other languages: there's no official client lib
yet — fall back to raw `requests` (Python) / `axios` (Node) against
the vault's REST surface. The endpoints are stable; you can model
them on the VaultClient surface above.

End with a one-paragraph summary of what we built so I can paste it
into another tool if I want.
```

---

## Tips

- **Don't auto-run.** Even if the prompt says "execute," the AI will
  ask you to confirm before each `update-tag` or `create-note`. Good.
- **The interview is the value.** Even if you end up using none of
  the proposed structure, you'll know what you actually want after
  the conversation.
- **Iterate.** This is your vault. Rerun the prompt later, or just
  edit tags / paths via MCP whenever your thinking changes.

When you're done structuring, the [build a custom UI](/onboarding/surface-build/) prompt is the natural next step.
