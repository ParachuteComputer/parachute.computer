---
title: "Getting Started"
description: "The start-here note written for your AI — every new vault ships with it, so your AI can set the vault up with you."
permalink: /guides/getting-started/
order: 6
vault_path: "Getting Started"
---

# Getting Started

This is the **start-here guide** for this Parachute vault — think of it like a
`SKILL.md`: practical instructions for setting up and growing the vault. Read it
when you're **getting the vault started** or orienting yourself to it — you don't
need to re-read it every session. It's a **starting point, not a script**, and
it's adaptable: edit it (see "Adapt this note") as the vault takes shape.

When the operator says something like *"help me set up my parachute,"* this is
your brief: design their structure with them, import what they already have, and
shape the vault around how they actually think and work.

## What a Parachute vault is

A vault is **notes + tags + links** in one graph, reachable over MCP (you, now),
a REST API (scripts), and any surface (a UI). It ships *nearly blank* — just a
small welcome web and the `capture` tag the Notes surface uses; no other
predefined tags or schema. You and the operator design the structure that fits
*their* life and work. The vault is the engine; the meaning is yours to bring.

Core moves you already have as MCP tools:
- `create-note` / `update-note` / `delete-note` — write notes (single or batch).
- `query-notes` — by id/path, by tag, full-text `search`, or graph `near` a note.
- `list-tags` / `update-tag` / `delete-tag` — manage the tag vocabulary + schemas.
- `find-path` — shortest link path between two notes.
- `vault-info` — refresh the live schema/stats projection any time.

`[[wikilinks]]` in note content auto-link to the note at that path — use them
freely; they resolve even if the target is created later.

## Tags vs paths vs schemas — the design vocabulary

These three axes are the heart of vault design. Use the right one for the job:

- **Tags = types / membership.** A tag answers *"what kind of thing is this?"*
  (`#person`, `#meeting`, `#project`). Queries **expand over tags**: a tag can
  declare `parent_names` so `tag:X` also returns its subtypes (e.g. tagging a
  note `#meeting/standup` with `parent_names: [meeting]` means `query-notes
  { tag: "meeting" }` finds it). Tags are how you ask *"show me all my people."*
  This is the primary structure — reach for a tag first.

- **Paths = organization / filing.** A path (`Projects/Acme/Kickoff`) is *where*
  a note lives — a human-browsable address, unique per note. Paths are for
  folders and named docs (like this one). They do **not** drive type queries;
  don't encode meaning in a path that a tag should carry. A note can have a
  path, tags, or both.

- **Schemas = typed metadata fields.** Attach a schema to a tag (via
  `update-tag`) to declare typed metadata fields — e.g. `#meeting` with a
  `held_on` date, `#person` with an `email`. Each field can **optionally** be
  marked `indexed: true` to make it **queryable with operators** (`query-notes
  { tag: "meeting", metadata: { held_on: { gte: "2026-01-01" } } }`); indexing
  is opt-in per field, not automatic. Add a schema (and index a field) when you
  find yourself wanting to filter or sort on a value, not before.

Rule of thumb: **type with tags, file with paths, make-it-queryable with
schemas.** Start minimal — invent tags as real notes need them, declare a
schema only when a query demands it. Over-designing an empty vault is the
common mistake.

Declaring a schema is one `update-tag` call — the `fields` object maps each
field name to `{ type, enum?, indexed? }` (`type` is `"string"`, `"boolean"`,
or `"integer"`):

```
update-tag {
  tag: "meeting",
  description: "A meeting with notes",
  fields: {
    held_on: { type: "string", indexed: true },              // queryable with operators
    status:  { type: "string", enum: ["scheduled", "done"] }, // first enum value is the default
    rating:  { type: "integer" }
  }
}
```

`fields` is **merged** (new keys added, existing replaced); `parent_names` and
`relationships` are replaced wholesale when passed. Only `indexed: true` fields
support operator queries (`metadata: { held_on: { gte: "..." } }`) and
`order_by`; all tags declaring the same field must agree on its `type` and
`indexed` flag.

## Write gotchas

A few behaviors worth knowing before you write at scale:

- **`update-note` requires optimistic concurrency by default.** Pass
  `if_updated_at` with the `updated_at` you last read; a mismatch returns a
  conflict error (re-read, reconcile, retry). For bulk/scripted writes where
  concurrency is known-safe, pass `force: true` to waive the *requirement to
  supply* it. `append`/`prepend`-only updates are exempt (no-conflict-by-design).
- **A schema field's default is filled in on write, so it shows up even when you
  didn't set it.** When a note gets a tag whose schema declares a field, the
  missing field is back-filled: an `enum` field → its **first listed value**, an
  `integer` → `0`, a `boolean` → `false`, a plain string → `""`. So a
  `rating: { type: "integer" }` reads as `0` on notes nobody rated — that `0`
  is "unset," not "rated zero." Order an `enum`'s values so the first is a sane
  default, and don't read a back-filled `0`/`""`/`false` as a real value.
- **Validation is advisory, never blocking.** A type/enum mismatch comes back as
  a `validation_status` warning on the write response — the write still lands.
  Read those warnings and self-correct on the next turn.

(Full design guide, with copy-paste examples: https://parachute.computer/scripting/)

## Importing existing notes

If the operator already keeps notes (Obsidian, Markdown, etc.), bring them in
rather than starting cold:

- **Obsidian / a Markdown folder:** `parachute-vault import <path>` — preserves
  frontmatter, tags, `[[wikilinks]]`, and file paths.
- **A portable Parachute export** (a dir with `.parachute/vault.yaml`): the same
  `import` command auto-detects it and does a lossless round-trip (ids, typed
  links, tag schemas, attachments).
- **Ad hoc / pasted content:** just `create-note` it. Then help the operator tag
  and schematize: read a sample of imported notes, propose a small tag
  vocabulary, and apply it.

After an import, orient yourself: `vault-info` for the new schema picture,
`list-tags` to see what vocabulary arrived, `query-notes { search: "..." }` to
spot-check. Then propose structure — don't impose it silently.

## Later: a custom surface

Building a custom UI over the vault (a dashboard, a notes app) is usually **not**
the starting point — get the notes and structure right first. If and when the
operator wants one, add the **Surface Starter** guide to this vault — it's a
seed pack that isn't installed by default. Run
`parachute-vault add-pack surface-starter` (or use the console's add-pack
affordance) to seed it; it covers building a surface with
`@openparachute/surface-client` + `@openparachute/surface-render`.

## Adapt this note

This guide is a **default starting point, not gospel** — edit it to fit this
vault. As you and the operator settle on a tag vocabulary, conventions, or a
surface, you can record that here so a future session inherits the current shape
of the vault instead of this blank-slate default. Useful things to capture:
- the tag vocabulary you've settled on and what each tag means;
- naming/path conventions for this vault;
- which schemas exist and why;
- anything a fresh AI would need to be immediately useful.

Treat setup as a relationship, not a one-time install.
