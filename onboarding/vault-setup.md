---
layout: post.njk
title: "Starter prompt — set up your vault"
description: "Paste this into Claude Code or Codex with your vault's MCP wired up. It will interview you about how you think about your notes and propose a structure that fits."
permalink: /onboarding/vault-setup/
date: 2026-05-26T12:00:00
---

This is one of two starter prompts ([the other is for building a custom UI](/onboarding/surface-build/)). Paste the block below into an AI client that has your vault's MCP tools wired up — Claude Code or Codex are the easiest paths — and the AI will interview you, then propose a vault structure that matches how you actually think.

**Before you paste**: make sure your AI client has the vault's MCP server connected. The wizard at `/admin/setup` walks you through the `claude mcp add` command (or equivalent for your client).

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

## Round 0: orient (read the current vault)

Before asking me anything, call:
- `vault-info` — see if there's an existing vault description and
  the basic stats (note count, tag count).
- `list-tags` (with schema detail) — see what tag conventions already
  exist, if any.
- `query-notes` with an empty filter (limit 10) — see if there are
  any notes at all, and what they look like.

Report what you find back to me in a short paragraph. Two cases:

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

For each source we agreed to import in Round 1:

- **Obsidian:** run `parachute-vault import <path>` (or remind me to
  run it). Verify with `vault-info` afterward — count should jump.

- **Anything else (Apple Notes, Notion, loose markdown, etc.):**
  before generating a script, MINT A NARROW TOKEN: call your MCP
  client's token-creation flow (the user's MCP setup determines the
  exact UX, but most agentic clients have an "issue token" surface
  against the vault) for scope `vault:<name>:write` with a short TTL
  (1 hour). Tell me the token short ID or hash but NEVER paste the
  raw token into the chat or the script source. Then generate a
  small Bun script (or Python, my preference) that:
  - reads `PARACHUTE_TOKEN` from env
  - reads the source data (file glob, JSON export, AppleScript
    output, whatever)
  - POSTs to `/<vault-path>/notes` (the vault REST endpoint, hub-
    proxied) with appropriate tag + path mapping
  - prints a dry-run summary first, prompts for confirmation, then
    runs the actual import
  Hand me the script + the command to run:
  `PARACHUTE_TOKEN=<token> bun script.ts`. Tell me to revoke the
  token after the run (`parachute auth revoke <jti>` or the SPA's
  Tokens page).

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
