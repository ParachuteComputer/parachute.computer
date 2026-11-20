---
title: "Parachute Cloud"
summary: "We run the server; your vaults are yours to export. Sign up with an email."
door: run
order: 1
checked: "parachute-cloud CLAUDE.md (Cloudflare Workers, one Durable Object per vault, D1, R2), workers/identity/wrangler.toml (ISSUER, APP_ORIGIN, VAULT_PUBLIC_ORIGIN), workers/identity/src/console.ts cardFor"
---

Parachute Cloud is Parachute run for you. Sign up at [my.parachute.computer](https://my.parachute.computer/console) with your email; your account page lists your vaults, each with its connector address and **Copy**.

- **Your vaults** live at `https://my.parachute.computer/vault/<name>/`. The connector address for an AI is that plus `mcp`. See [Connect your AI](/docs/use/connect-your-ai/).
- **Sign in** in the Parachute app with **Sign in with Parachute Cloud**: your email, then the code it mails you. No key needed.
- **Keys** for scripts are made on your account page ([Keys](/docs/build/keys-and-scopes/)).
- **Export** any time, with your files: `GET /vault/<name>/api/export` with a key. It is the same portable markdown a server of your own reads, so moving is a copy, not a migration.
- **Pricing:** [one page says it](/pricing/).

## How it runs

The same vault engine as a server of your own (`@openparachute/core`), on Cloudflare: each vault is its own Durable Object holding its own SQLite database, files in R2, accounts in D1. Sign-in is at `cloud.parachute.computer`. The MCP tools and the REST routes are the same on both; a shared test suite holds them to it.
