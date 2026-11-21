---
title: "Make a type"
summary: "A type names a kind of record and its fields. Make one before you write records of a new kind."
door: build
order: 2
checked: "parachute-core MCP on 0.9.0-pre.1 (manage-types, list-types, create-record; vault-info {help}), packages/vault/core/src/mcp-short.ts"
---

*On a 0.8 server (Parachute Cloud today):* `manage-types` is `update-tag` (the same `tag`, `description`, `fields`, `parent_names`), `list-types` is `list-tags`, and `create-record` is `create-note` (types go in `tags`, fields in `metadata`).

A **type** is a kind of record: `book`, `meeting`, `recipe`. It has a description and fields. A record has any number of types (usually one), plus any number of **tags** (plain labels, no fields).

## First, look

```json
list-types {}
```

Every type and tag, with counts. `list-types { "name": "book" }` gives one with its fields. Reuse a type that fits; make a new one when none does. Don't stretch the nearest one.

## Make it

```json
manage-types {
  "tag": "book",
  "description": "A book I am reading or have read",
  "fields": {
    "author": { "type": "string" },
    "status": { "type": "string", "enum": ["want", "reading", "done"], "default": "want", "indexed": true },
    "finished": { "type": "string" }
  }
}
```

- `tag` is the type's name, lower case. A `/` in a name (`media/film`) only groups it; `parent_names` (below) is what makes a subtype.
- `fields`: each has a `type` (`string`, `number`, `integer`, `boolean`, `date`, `reference`, `array`, `object`), and may have `enum`, `default` and `indexed`.
- `indexed: true` makes queries on that field fast. Index the fields you filter by.
- Checks are advice by default: a record that breaks one is still written, and its `validation_status` says what's wrong. Add `"strict": true` to a field to refuse such writes.
- `parent_names: ["media"]` makes `book` a subtype of `media`: a query for `media` finds books.

With a connection that can write, `manage-types` makes a type nobody has defined yet, and adds fields to a type that connection made. Changing or removing a field, a type someone else made, and the actions below need one that can manage the vault (admin); so does `manage-types` at the one address for all vaults (`https://<server>/mcp`): use the vault's own address. It also renames (`action: "rename"`), merges and deletes types, drops unused indexes (`prune`) and changes a field's values (`migrate`); `prune` and `migrate` are dry runs until you pass `"apply": true`.

## Then write records of it

```json
create-record { "path": "Books/Piranesi", "types": ["book"], "fields": { "author": "Susanna Clarke" } }
```

`status` comes back as `want`, the default. Next: [Write records](/docs/build/write-records/).
