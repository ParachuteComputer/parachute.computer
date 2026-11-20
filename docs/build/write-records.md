---
title: "Write records"
summary: "Create, find and change records over MCP, without overwriting what someone else changed."
door: build
order: 3
checked: "parachute-core MCP on 0.9.0-pre.1 (tools/list descriptions of query-records, create-record, update-record, delete-record)"
---

*On a 0.8 server (Parachute Cloud today):* the tools are `create-note`, `query-notes`, `update-note`, `delete-note`; a record's `body` is `content` and its `fields` are `metadata`; types go in `tags`.

A **record** has a `path` (like `Books/Piranesi`), `types`, `tags`, `fields` and a markdown `body`. `[[Wikilinks]]` in the body become links between records.

## Create

```json
create-record { "path": "Books/Piranesi", "types": ["book"], "fields": { "author": "Susanna Clarke" }, "body": "A gift from Sam." }
```

Several at once: `create-record { "records": [ … ] }`. If the path is taken, `if_exists` decides: `error` (the default), `ignore`, `update` or `replace`.

## Find

| You want | Ask |
|---|---|
| One record | `query-records { "id": "Books/Piranesi" }` (an id, a path or a title) |
| Every record of a type | `query-records { "type": "book" }` (subtypes too) |
| By a field | `query-records { "type": "book", "fields": { "status": { "eq": "reading" } } }` |
| In a folder | `query-records { "path_prefix": "Books/" }` |
| By words (and by meaning, where the server has meaning search on) | `query-records { "search": "the book about the house with the statues" }` |
| Near a record | `query-records { "near": { "id": "Books/Piranesi", "depth": 2 } }` |

Lists leave the body out unless you pass `include_body: true`. Field operators: `eq`, `ne`, `gt`, `gte`, `lt`, `lte`, `in`, `not_in`, `exists`.

## Change

```json
update-record { "id": "Books/Piranesi", "fields": { "status": "done" }, "if_updated_at": "<updated_at you read>" }
```

- `fields` merges; `null` removes a field. `types`, `tags` and `links` take `{ "add": [...], "remove": [...] }`.
- The body: `body` replaces it, `append` / `prepend` add to it, `body_edit` changes one passage (`old_text` must occur once).
- Every change but `append` and `prepend` needs `if_updated_at`: the record's `updatedAt` as you read it. If someone (the person, another AI, an applet) changed the record since, the write is refused and you read it again. `force: true` skips the check.

## Delete

`delete-record { "id": "Books/Piranesi" }`. Deleting asks for a connection that can write.

## Every parameter

The tool list is short on purpose. `vault-info { "help": "query-records" }` returns any tool's full reference. All of them: [MCP tools](/docs/build/reference/mcp/).
