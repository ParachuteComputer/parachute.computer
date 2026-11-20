---
title: "Make a bundle"
summary: "One record says what the app shows: which applets, which are pinned, which opens first."
door: build
order: 5
checked: "parachute src/shell/apps.ts appOf (fields read, the id must match the path), docs/NAVIGATION.md (Apps, Where the choices live), docs/design/APP-RECORD.md (What an unsigned record can change, Security levels)"
---

*On a 0.8 server (Parachute Cloud today):* `create-note`, with `metadata.app` for `fields.app`.

A **bundle** is a record in the person's home vault that the app follows: the applets its list offers, the pins on its bar, the home it opens on. The person picks one in Settings → **Your app**; **Simple** and **Everything** are always there.

*The app and its record still say "app" for a bundle (`Parachute/Apps/<id>`, `fields.app`, the tag `parachute-app`); a rename to "bundle" is planned. Write the record as below until then.*

## Which vault is home

A bundle lives in the person's **home vault**: the vault of their own the app reads its settings from (Settings in the app shows it; by default the first they signed in to). If the vault you are connected to holds `Parachute/Settings` (`query-records { "id": "Parachute/Settings" }`), it is the home. If it doesn't, ask the person which vault is home, and write the bundle with a connection to that vault. A vault's name in a bundle is the name the person's server gives it, the one in your connection's instructions.

## The record

```json
create-record {
  "path": "Parachute/Apps/reading-room",
  "tags": ["parachute-app"],
  "fields": { "app": {
    "contract": 1,
    "id": "reading-room",
    "name": "Reading room",
    "sources": [{ "vault": "home", "applet": "*" }],
    "bar": [{ "vault": "home", "applet": "Applets/Reading" }, { "vault": "home", "applet": "Applets/Journal" }],
    "start": { "vault": "home", "applet": "Applets/Reading" }
  } }
}
```

| Field | What it says |
|---|---|
| `contract` | Always `1`. |
| `id` | Short kebab-case (a-z, 0-9, -), up to 40 characters, and the last part of the path: `Parachute/Apps/<id>`. A record whose path doesn't end in its id is ignored. |
| `name` | What Settings shows (60 characters at most). Optional `glyph` (a character or two) and `note` (a short line). |
| `sources` | Which applets the list offers: one applet (`"applet": "Applets/Reading"`), every applet in a vault (`"applet": "*"`), or every vault on a named server (`"hub": "https://…", "vault": "*"`). No `hub` means the home vault's server. |
| `hide` | Applets to leave out of the list. |
| `bar` | The pins, in order (up to 12 show), then **Applets** (with `look: "launcher"`). Pin the home first to have it there. |
| `start` | The home: the applet the app opens on. |
| `opens` | Which applet opens a kind of record, for every device: `{ "type": "book", "vault": "home", "applet": "Applets/Reading" }`; `"applet": null` is the plain view. |
| `keep` | How many applets stay running while hidden: `"auto"` (6 on a phone, 12 on a computer) or 0 to 12. Only speed hangs on it. |
| `look` | `"launcher"` (the list of applets) or `"notes"` (the simple app's Notes). |
| `security` | Make the app stricter: `{ "approvals": "passcode", "code": "unlock", "join": "passcode", "idle": 10 }`. A bundle can raise these, never lower them. |
| `live` | Follow someone else's bundle: `{ "hub": "https://…", "vault": "…", "path": "Parachute/Apps/…" }`, read from their vault each time. |

`vault` is a vault's name; add `"hub": "https://…"` when two servers hold vaults of the same name. `applet` is the applet record's path or id. A place that names an applet the device can't find is left off, not an error.

## What it can't do

Anyone who can write the vault can write a bundle, so the app reads it for the home, the pins and the list only, and none of them runs code. Words like `grants`, `approved` or `code` in it are not read. The home opens by itself only after the person allowed that applet's code and chose it as home on that device; until then it opens on its card.

## Which bundle a device opens

The device's own choice (Settings → **Your app**), else the settings record's `app` (below), else Everything. The person's choice of one is also what a new device opens.

## The settings record

`Parachute/Settings`, tagged `parachute-settings`, holds `fields.parachute`: `app` (which bundle a new device opens: `"simple"`, `"everything"` or a bundle's id), `hubs` (the person's servers, each `{ "hub": "https://…", "name": "…" }`), and, for Everything, its own `bar` and `start`. Change only what you mean to: entries the app doesn't read are kept as they are.
