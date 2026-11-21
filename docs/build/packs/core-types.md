---
title: "Core types (a pack)"
summary: "People, projects, meetings and tasks, linked to each other, each with a template, and a view of open tasks. The pack Parachute's app adds with one tap."
door: build
order: 3.6
checked: "parachute src/kit/packs/core-types.json (the same block; scripts/check-packs.mjs compares them), e2e/packs.spec.ts"
---

People, projects, meetings and tasks, linked to each other. Each has a template (a meeting starts with Attendees, Notes, Decisions and Actions), and tasks have a saved view of the open ones.

**In the app:** Vault, your vault, **Add a pack**, **Add Core types**. **To your AI:** "Apply the Core types pack from parachute.computer/docs/build/packs/core-types.md to my vault."

A type you already have keeps its fields; a record of yours at one of these paths stays as it is. Adding it again changes nothing.

## For an AI applying it

Apply the block below exactly as written, its words too: read this page's markdown, https://parachute.computer/docs/build/packs/core-types.md, not a summary of it. If you can't read the block exactly, stop and tell the person: don't rebuild it from a summary. The full rule is in [Templates and packs](/docs/build/templates/); in short:

1. `list-types { "include_schema": true }` and `query-records { "id": "Parachute/Receipts/core-types" }`.
2. Each type: `manage-types { "tag": "<name>", "kind": "type", "description": …, "fields": … }` if it is missing. If it is already a type, keep its fields and send only the fields it lacks; if that is refused, add nothing and say so.
3. The records: one `create-record { "records": [ … ] }` with `"if_exists": "ignore"` inside each item. An item that comes back `existed: true` is the person's.
4. Last, the receipt, listing only what you made (types with the fields you sent; records that came back `existed: false`, with their `id` and `updatedAt`). Skip it if you made nothing and the receipt is there; if it is there and you made something, `update-record` it, keeping what it listed.
5. Tell the person what you added and what you left as theirs.

```text
create-record { "path": "Parachute/Receipts/core-types", "tags": ["parachute-receipt"], "body": "Core types, version 1.",
  "fields": { "receipt": { "contract": 1, "id": "core-types", "name": "Core types", "version": 1,
    "source": "https://parachute.computer/docs/build/packs/core-types",
    "made": { "types": { "person": ["email", "org"], … }, "records": [ { "path": "Templates/person/Person", "id": "…", "updated_at": "…" }, … ] },
    "skipped": [ "what you left, and why, in a sentence each" ] } } }
```

```json
{
  "parachute_pack": 1,
  "id": "core-types",
  "name": "Core types",
  "version": 1,
  "source": "https://parachute.computer/docs/build/packs/core-types",
  "summary": "People, projects, meetings and tasks, linked to each other, each with a template, and a view of open tasks.",
  "types": {
    "person": {
      "description": "Someone you know or work with.",
      "fields": { "email": { "type": "string" }, "org": { "type": "string" } }
    },
    "project": {
      "description": "Something you are working toward, with an end.",
      "fields": {
        "status": { "type": "string", "enum": ["idea", "active", "paused", "done"], "default": "active" },
        "lead": { "type": "reference" }
      }
    },
    "meeting": {
      "description": "A conversation at a time, with people.",
      "fields": {
        "date": { "type": "date" },
        "people": { "type": "reference", "cardinality": "many" },
        "project": { "type": "reference" }
      }
    },
    "task": {
      "description": "One thing to do.",
      "fields": {
        "status": { "type": "string", "enum": ["todo", "doing", "done"], "default": "todo" },
        "due": { "type": "date" },
        "project": { "type": "reference" },
        "who": { "type": "reference" }
      }
    },
    "template": {
      "description": "A starting point for new records of one type. Its body is the new record's body.",
      "fields": { "for": { "type": "string" }, "default": { "type": "boolean" }, "guide": { "type": "string" } }
    }
  },
  "records": [
    {
      "path": "Templates/meeting/Meeting",
      "types": ["template"],
      "fields": { "for": "meeting", "default": true, "guide": "Fill Attendees from the invite. Leave Actions empty until the end." },
      "body": "## Attendees\n\n## Notes\n\n## Decisions\n\n## Actions\n"
    },
    {
      "path": "Templates/project/Project",
      "types": ["template"],
      "fields": { "for": "project", "default": true, "guide": "One line for Why. Done when says how you'll know it is finished." },
      "body": "## Why\n\n## Done when\n\n## Notes\n"
    },
    {
      "path": "Templates/person/Person",
      "types": ["template"],
      "fields": { "for": "person", "default": true, "guide": "How we met in a line or two. Notes is for what's worth remembering." },
      "body": "## How we met\n\n## Notes\n"
    },
    {
      "path": "Templates/task/Task",
      "types": ["template"],
      "fields": { "for": "task", "default": true, "guide": "Say what done looks like in a sentence." },
      "body": "## Done when\n\n## Notes\n"
    },
    {
      "path": "Parachute/Views/task/Open",
      "tags": ["parachute-view"],
      "fields": { "view": { "contract": 1, "layout": "table", "sort": { "by": "due", "dir": "asc" }, "where": [{ "field": "status", "op": "ne", "value": "done" }], "group": null } },
      "body": ""
    }
  ]
}
```
