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

Don't make assumptions about my structure. Interview me first.

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
  Apple Notes, Notion exports, plain text, etc.)

If I mention Obsidian: tell me Parachute Vault has lossless Obsidian
import (`parachute-vault import <path>`) — I can pull a whole vault
in, IDs preserved, schemas restored.

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
   tags. `notes/2026/may/standup-2026-05-26` is fine; so is no path
   at all.

Propose:
- A starting set of tags (with field schemas where useful)
- A starting path convention (if I want one — some people don't)
- Whether to seed any starter notes (e.g. a "system" note describing
  my conventions for future-me to read)

Ask me to push back. Don't commit anything to the vault until I say so.

## Round 4: execute

Once I approve the structure:
- `update-tag` for each proposed tag with its schema
- `create-note` for any starter notes (use the proposed paths)
- `vault-info` to set a vault description that future-AI sessions
  will read

If I want to import existing data from Obsidian or Apple Notes,
suggest the import command and walk me through it.

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
