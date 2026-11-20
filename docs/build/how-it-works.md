---
title: "How it works"
summary: "One reading tracker, followed through every layer, from the vault to the screen."
door: build
order: 1
checked: "a run on a parachute-core 0.9.0-pre.1 hub (manage-types, create-record, query-records, POST /api/notes); parachute docs/WRITE-AN-APPLET.md, docs/NAVIGATION.md, src/applet/modules/vault.ts"
---

Parachute has four layers, and each is records in a vault. Here is one person's reading tracker passing through all four.

| Layer | What it is | The reading tracker |
|---|---|---|
| **Vault** | Where records are kept: on Parachute Cloud or a server of your own. | The person's home vault, `home`. |
| **Types and records** | A record is a body (markdown) with typed fields. A type says which fields its records have. | A type `book` (author, status). Records under `Books/`. |
| **Applets** | A small screen, one record of code. Runs in the app, sealed, after the person allows it. | `Applets/Reading`: the books by shelf, and a line to add one. |
| **Bundle** | One record that says what the app shows: the home, the pins, the list. | Reading pinned on the bar. |

The person's AI wrote all four over MCP. The person tapped **Allow** once.

## 1. The type

The AI asks the vault what types it has (`list-types`), finds no `book`, and makes one:

```json
manage-types { "tag": "book", "description": "A book I am reading or have read",
  "fields": { "author": { "type": "string" },
              "status": { "type": "string", "enum": ["want", "reading", "done"], "default": "want", "indexed": true } } }
```

## 2. Records

```json
create-record { "path": "Books/The Overstory", "types": ["book"],
  "fields": { "author": "Richard Powers", "status": "reading" }, "body": "Started on the train." }
```

`query-records { "type": "book", "fields": { "status": { "eq": "reading" } } }` finds it again. The record is plain markdown with its fields; it exports as a file.

## 3. The applet

One record, tagged `applet`. Its fields are the manifest (what it may do); its body is the code, one TSX module on the app's kit:

```tsx
import { useEffect, useState } from "react";
import { Empty, Field, List, Loading, Page, ready, vault } from "parachute";
// … the rest is in Make an applet
```

The manifest asks to **read and add** in `Books/` and to **open** `book` records there. A book the applet adds gets the type `book`, and the type's default fills `status: want`.

## 4. The bundle and the card

The AI pins Reading on the bar by writing the bundle record. The next time the person opens Reading, the app shows its card: *Read and add notes in Books/. Open book notes in Books/ when you tap one.* They tap **Allow**; the app signs that approval with their key, and their other devices run the same code without asking again.

## Where each part is checked

- The vault checks types and fields, and who may read and write (the connection's scope).
- The app checks the applet: its manifest (an unknown key refuses the whole applet), every call against its folders, its code's hash against the signed approval.
- Nobody but the person makes code run.

## What an applet can't do, and who does it instead

An applet writes **only a record's body**, in the folders on its card; never fields, types or tags, and never deletes. So the person's AI moves a book to *Read* (`update-record` with `"fields": {"status": "done"}`), or the applet keeps that state in the body. Plan for it when you design one.
