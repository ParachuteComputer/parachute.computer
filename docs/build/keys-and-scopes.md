---
title: "Keys and what they reach"
summary: "Every connection reaches one vault at one level: read, write or admin. Keys for scripts are made the same way."
door: build
order: 7
checked: "parachute-core packages/vault/src/mcp-http.ts (tools filtered by scope), tools/list at each level on 0.9.0-pre.1, packages/cli/src/front.ts and keys.ts (parachute keys new); parachute docs/design/SCOPES.md"
---

A connection to a vault (an AI app, a script, the Parachute app) holds a **scope**: `vault:<name>:<level>`.

| Level | It can | MCP tools it sees |
|---|---|---|
| `read` | read records, types, files | `query-records`, `list-types`, `vault-info`, `docs`, `doctor`, `read-attachment`, `attachment-url` (download) |
| `write` | also create, change and delete records, add files; make a new type, and add fields to a type it made | + `create-record`, `update-record`, `delete-record`, `manage-types` (at the vault's own address) |
| `admin` | also change any type, the vault's description and keys | + every `manage-types` action, `manage-keys` |

A tool a connection can't use isn't listed to it, and calling it by name fails. A scope can also be narrowed to some tags: the connection then sees only records with them.

## An AI app

The person picks the level on the server's page when they connect it. Ask for the least that works.

## A script or a job

Make a key for it:

- **In a conversation:** `manage-keys { "action": "mint", "scope": "vault:home:read", "name": "nightly-digest" }`. Short-lived by default: 15 minutes, `ttl_seconds` up to an hour, or up to 90 days (`7776000`) with `long_lived: true`. A key can't reach further than the connection that made it.
- **On the server:** `parachute keys new nightly-digest --vault home --can read` (0.8: `parachute auth mint-token --scope vault:home:read`).
- **On Parachute Cloud:** keys come from the account API (`POST /account/keys`, read or write); a page for them is coming. In a conversation, Cloud's 0.8 tool is `manage-token`.

Use it as `Authorization: Bearer <key>`: [Scripts and the REST API](/docs/build/scripts/). Revoke it with `manage-keys { "action": "revoke", "name": "nightly-digest" }` or `parachute keys revoke nightly-digest`.

## Applets are narrower

An applet doesn't hold a key. The app holds the person's sign-in and lets each applet reach only the folders on its card, in its own vault ([What Allow means](/docs/use/allowing-applets/)). When an applet that writes is allowed and the app can only read that vault, the server asks the person once more, for that vault.
