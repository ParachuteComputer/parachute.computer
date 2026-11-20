---
title: "Scripts and the REST API"
summary: "Everything the MCP tools do is also plain HTTP, for a script, a cron job or your own app."
door: build
order: 8
checked: "parachute-core 0.9.0-pre.1 (GET /vault/<v>/api/records?type=, POST /api/notes; server instructions' REST line), packages/cli keys new"
---

Every vault answers REST at `<server>/vault/<vault>/api/`, with a key as `Authorization: Bearer <key>` ([make one](/docs/build/keys-and-scopes/)). On Parachute Cloud the server is `https://my.parachute.computer`.

## Read

```bash
curl -s "https://your-server.example/vault/home/api/records?type=book" \
  -H "Authorization: Bearer $PARACHUTE_KEY"
```

## Write

```bash
curl -s -X POST "https://your-server.example/vault/home/api/records" \
  -H "Authorization: Bearer $PARACHUTE_KEY" -H "content-type: application/json" \
  -d '{"path": "Books/Piranesi", "types": ["book"], "fields": {"author": "Susanna Clarke"}, "body": ""}'
```

The record routes (`/api/records`) take the same words as the MCP tools: `body`, `fields`, `types`, `tags`.

## On a 0.8 server (Parachute Cloud today)

The routes are `/api/notes`, with the older words: `content` for the body, `metadata` for fields, and types as `tags`.

```bash
curl -s "https://my.parachute.computer/vault/home/api/notes?tag=book" -H "Authorization: Bearer $PARACHUTE_KEY"
curl -s -X POST "https://my.parachute.computer/vault/home/api/notes" \
  -H "Authorization: Bearer $PARACHUTE_KEY" -H "content-type: application/json" \
  -d '{"path": "Books/Piranesi", "tags": ["book"], "metadata": {"author": "Susanna Clarke"}, "content": ""}'
```

0.9 keeps `/api/notes` working, and marks it as going in 1.0.

## Keep keys short

A key in a script should reach one vault at the lowest level that works, and expire when it can (`parachute keys new … --ephemeral`). Keep it in your secret store, not in the script.
