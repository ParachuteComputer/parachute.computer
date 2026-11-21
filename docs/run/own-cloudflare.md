---
title: "Your own Parachute on your own Cloudflare"
summary: "Parachute Cloud's own code, under your names, on a Cloudflare account you own. One owner, who signs in with a Nostr key. No computer to keep on."
door: run
order: 2
checked: "parachute-cloud door/0.9 deploy/personal (README.md, deploy.sh, vault-limit.sh, smoke.ts) and a full rehearsal walk on 2026-11-21 (T-476); Cloudflare's pricing and limits pages read 2026-11-21"
---

This is Parachute Cloud's own two workers, deployed under names you choose on **your** Cloudflare account. You hold the account, the data and the bill; there is no server of yours to keep running. One person owns it and signs in with a Nostr key: there are no email sign-ins and no billing.

**Who it's for:** one person who wants their Parachute on an account they control, is at home in a terminal, and doesn't want to keep a computer on. If you'd rather not touch Cloudflare, use [Parachute Cloud](/docs/run/cloud/). If you want everything on your own disk, or several people on one server, [run your own](/docs/run/self-host/).

## What it costs

Cloudflare's prices, from its own pages (read 2026-11-21; check them before you rely on a number):

| | Free plan | Workers Paid ($5 a month minimum per account) |
|---|---|---|
| Requests | 100,000 a day | 10 million a month, then $0.30 per million |
| CPU per request | 10 ms | up to 5 minutes (30 s default) |
| Vault storage (Durable Objects, SQLite) | 5 million rows read, 100,000 rows written a day; 5 GB | 25 billion rows read, 50 million written a month; 5 GB-month, then $0.20 per GB-month |
| Accounts (D1) | 5 million rows read, 100,000 written a day; 500 MB a database | 25 billion read, 50 million written a month; 10 GB a database |
| Files and backups (R2) | 10 GB-month, 1 million writes and 10 million reads a month | then $0.015 per GB-month; no egress fees on either plan |

Sources: [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/), [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/), [R2 pricing](https://developers.cloudflare.com/r2/pricing/).

- **Free works for trying it and light use.** Our rehearsal ran on a free account. The daily limits are for the whole account, so everything else on it shares them. When a limit is reached, Cloudflare answers with errors (writes fail) until 00:00 UTC.
- **For a Parachute you use every day, take Workers Paid.** A personal Parachute should sit inside what it includes, so expect the $5.

## Set it up

You need [Bun](https://bun.sh) 1.4 or newer, git, a Cloudflare account with a workers.dev subdomain (dashboard: Workers & Pages, your subdomain), and a Nostr key. The Parachute app makes you a key: **Make a new key** when you first open it, then Settings shows its public half (`npub1…`).

1. **Get the code**: `git clone https://github.com/ParachuteComputer/parachute-cloud && cd parachute-cloud && git checkout door/0.9`.
2. **Write a profile**, a small file kept outside the repo, say `~/parachute/me.env`:

   ```bash
   ACCOUNT_ID=<your Cloudflare account id, 32 hex>
   PREFIX=me-parachute        # names your workers, database and bucket
   OWNER_PUBKEY=npub1…        # your key's public half
   OWNER_PLAN=power           # 10 vaults; you can raise it later
   ```

3. **Deploy**: `bunx wrangler login`, then `bash deploy/personal/deploy.sh ~/parachute/me.env ~/parachute/evidence`. It takes about a minute, makes the bucket, the database and both workers, and prints your address: `https://me-parachute-identity.<subdomain>.workers.dev`. That one address is your Parachute: sign-in, your account and every vault answer there.
4. **Sign in from the Parachute app** (phone or desktop): type that address, choose **Mine**, **Sign in with your key**, and allow. Your first sign-in makes your account. Then make vaults from your account page or the account API.
5. **Connect your AI**: give it `https://<your address>/vault/<name>/mcp` with a key made for it (`POST /account/keys`, read or write, one vault or several), or add it as a connector, which signs in through your browser. The [deploy README](https://github.com/ParachuteComputer/parachute-cloud/blob/door/0.9/deploy/personal/README.md) has the commands.

In a browser tab (the app's web version) there is no key, and this Parachute sends no email. So open a browser session first with a one-time link from your key (`POST /account/session-link`; the README shows it), then sign in.

## Backups and restore

- Every night at 04:00 UTC each vault is snapshotted into your R2 bucket. 14 daily, 8 weekly and 12 monthly snapshots are kept.
- Files you attach live in the same bucket. Snapshots hold the vault, not the files; `GET /vault/<name>/api/export` gives you both, any time.
- **Restore** is one call, always into a new vault (`<name>-restored-<date>`): `POST /account/vaults/<name>/restore`.
- Take a snapshot now, before something risky, with `/ops/snapshot-run` and the ops token the deploy kept in `private/`.
- Deleting a vault deletes its snapshots too.

## Upgrades

Pull `door/0.9` and run `deploy.sh` again with the same profile. It upgrades in place: database changes are applied before the new workers start, and your vaults, keys and snapshots stay. To go back, deploy the commit you were on. Database changes only ever add.

## Limits today

It runs Parachute Cloud's workers, so it has Cloud's current gaps:
- **Add a pack** in the app stops with "This vault's server doesn't let Parachute make types yet". Making a type takes admin access here, for now.
- **Published records have no public page**: marking one published keeps it to you and your keys, and the app gives no link.
- **Changes** lists edits and their put-back, but not deleted records.
- **One owner.** Extra keys can be listed as admins (an agent's own key, say), and they act as the owner. There are no other people's accounts.
- **More vaults**: `bash deploy/personal/vault-limit.sh ~/parachute/me.env 25`. The refusal at the limit still tells you to write to Parachute; ignore that and use the script.

## Which one is for me

| | [Parachute Cloud](/docs/run/cloud/) | Your own Cloudflare | [Your own computer](/docs/run/self-host/) |
|---|---|---|---|
| Who runs the machines | we do | Cloudflare, on your account | you |
| What you keep on | nothing | nothing | a computer, day and night |
| Sign in | email | your Nostr key | your key, or a password |
| People | anyone who signs up | you (and keys you name) | as many as you add |
| Setup | sign up | about 15 minutes in a terminal | install one program |
| Cost | [our pricing](/pricing/) | Cloudflare's: free to try, $5 a month for daily use | your computer and power |
| Backups | ours, and your export | nightly to your own R2, one-call restore | `parachute backup` |
| Everything the engine does | Cloud's current set | the same as Cloud | all of it, first |
