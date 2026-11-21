---
title: "Your own Parachute on your own Cloudflare"
summary: "Parachute Cloud's own code, under your names, on a Cloudflare account you own. One owner, who signs in with a Nostr key. No computer to keep on."
door: run
order: 2
checked: "parachute-cloud door/0.9 612f2b0 deploy/personal; a full rehearsal walk and a cold run of this page from a fresh clone, 2026-11-21 (T-476); Cloudflare's pricing and limits pages read 2026-11-21"
---

This is Parachute Cloud's own two workers, deployed under names you choose on **your** Cloudflare account. You hold the account, the data and the bill; there is no server of yours to keep running. One person owns it and signs in with a Nostr key: there are no email sign-ins and no billing.

**It is early.** It works end to end (deploy, sign in from the app, your AI, backups, upgrades: tested on 2026-11-21), but it has [Cloud's current gaps](#limits-today), and you run upgrades yourself.

**Who it's for:** one person who wants their Parachute on an account they control, is at home in a terminal, and doesn't want to keep a computer on. If you'd rather not touch Cloudflare, use [Parachute Cloud](/docs/run/cloud/). If you want everything on your own disk, or several people on one server, [run your own](/docs/run/self-host/).

## What it costs

Cloudflare's prices, from its own pages (read 2026-11-21; check them before you rely on a number):

| | Free plan | Workers Paid ($5 a month minimum per account) |
|---|---|---|
| Requests | 100,000 a day | 10 million a month, then $0.30 per million |
| CPU per request | 10 ms | up to 5 minutes (30 s default) |
| Vault calls (Durable Objects: one per vault) | 100,000 requests and 13,000 GB-s a day | 1 million requests and 400,000 GB-s a month, then $0.15 per million and $12.50 per million GB-s |
| Vault storage (Durable Objects, SQLite) | 5 million rows read, 100,000 rows written a day; 5 GB | 25 billion rows read, 50 million written a month; 5 GB-month, then $0.20 per GB-month |
| Accounts (D1) | 5 million rows read, 100,000 written a day; 500 MB a database | 25 billion read, 50 million written a month; 10 GB a database |
| Files and backups (R2) | 10 GB-month, 1 million writes and 10 million reads a month | then $0.015 per GB-month; no egress fees on either plan |

Sources: [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/), [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/), [R2 pricing](https://developers.cloudflare.com/r2/pricing/).

- **Free is for trying it.** Its daily limits are for the whole account, shared with everything else on it, and a request gets 10 ms of CPU. When a limit is reached, Cloudflare answers with errors (writes fail) until 00:00 UTC.
- **For a Parachute you use every day, take Workers Paid.** A personal Parachute should sit inside what it includes, so expect the $5. Set a billing notification in Cloudflare, in case an AI loops on your vaults.

## Set it up

You need [Bun](https://bun.sh) 1.4 or newer, git, jq, and a Cloudflare account with a workers.dev subdomain (dashboard: Workers & Pages, your subdomain). Work in a folder of its own, say `~/parachute`: the deploy puts two more repos it needs beside the clone.

1. **Get the code**: `mkdir -p ~/parachute && cd ~/parachute && git clone https://github.com/ParachuteComputer/parachute-cloud && cd parachute-cloud && git checkout door/0.9 && bun install`. The install ends with "Failed to install 2 packages": that's expected, the deploy fetches those two itself.
2. **Your key**, in a file outside the repo: `bun deploy/personal/nip98.ts keygen ~/parachute/me.key` prints its public half. Or put a secret key you already have (`nsec1…`) in that file, and `bun deploy/personal/nip98.ts pubkey ~/parachute/me.key` prints the public half. **Back the file up**: it is your only way in. A second key can be linked as a spare (`POST /account/pubkeys`, which asks for a signature from that key).
3. **Write a profile**, `~/parachute/me.env`:

   ```bash
   ACCOUNT_ID=<32 hex>        # `bunx wrangler whoami` prints it
   PREFIX=me-parachute        # names your workers, database and bucket: starts with a letter; lowercase letters, digits, -;
                              # 4-42 characters; not parachute, parachute-*, arcade-parachute* or *-staging
   WORKERS_SUBDOMAIN=<yours>  # Workers & Pages → your subdomain; needed with `wrangler login` (an API token can look it up)
   OWNER_PUBKEY=<hex or npub1…>   # your key's public half
   OWNER_PLAN=power           # entry, standard, plus or power (10 vaults): set at your first sign-in
   # ADMIN_PUBKEYS=<hex or npub>  # optional: more keys that act as you (an agent's own), comma-separated
   ```

   The deploy keeps what must stay secret (an ops token) in `~/parachute/private/`; keep it, the key and the profile out of git.

4. **Deploy**: `bunx wrangler login`, then `bash deploy/personal/deploy.sh ~/parachute/me.env ~/parachute/evidence` (the last folder gets its log). It takes about a minute, makes the bucket, the database and both workers, and prints two addresses. Yours is the `-identity` one: `https://me-parachute-identity.<subdomain>.workers.dev`. That one address is your Parachute: sign-in, your account and every vault answer there.
5. **Sign in from the Parachute app** (phone or desktop). On its first screen, open **Advanced: paste a secret key**, paste the key file's contents (the hex is fine, though the hint says nsec) and tap **Keep this key**. Then type your address, choose **Mine**, **Sign in with your key**, and **Allow** on your Parachute's page; pick your home vault, **Continue**, and **Allow** once more. Your first sign-in makes your account. This needs an app build from 2026-11-21 or later (it carries the key sign-in for this kind of Parachute); an older one says "This hub doesn't take a key to sign in".
6. **Connect your AI** with a key made for it (below): `https://<your address>/vault/<name>/mcp` for one vault, or `https://<your address>/account/mcp` for a key that names several. Or add `https://<your address>/mcp` as a connector (Claude, ChatGPT): it signs in through your browser, and you pick the vaults it may reach.

In a browser tab (the app's web version) there is no key, and this Parachute sends no email, so open a browser session first with a one-time link from your key (below), then sign in.

### Day to day, from the repo folder

```bash
D=https://me-parachute-identity.<subdomain>.workers.dev                  # your address
bun deploy/personal/nip98.ts token $D ~/parachute/me.key acct.curl      # a 10-minute pass, signed by your key
curl -K acct.curl $D/account/vaults -d '{"name":"home"}'                 # a vault (a few names, like notes, are reserved)
curl -K acct.curl $D/account/keys -d '{"name":"claude","vault":"home","can":"write"}'    # a key for an AI or app
curl -K acct.curl -X DELETE $D/account/keys/claude                       # take it back
curl -K acct.curl $D/account/session-link -d '{}'                        # a one-time browser sign-in link
curl -K acct.curl -X POST $D/account/vaults/home/restore -d '{}'         # newest snapshot → home-restored-<date>
```

A key's `token` is shown once; it lasts a year. [The deploy README](https://github.com/ParachuteComputer/parachute-cloud/blob/door/0.9/deploy/personal/README.md) has the rest.

## Backups and restore

- Every night at 04:00 UTC each vault is snapshotted into your R2 bucket. 14 daily, 8 weekly and 12 monthly snapshots are kept.
- Files you attach live in the same bucket. Snapshots hold the vault, not the files. `GET $D/vault/<name>/api/export` with a key gives you both, any time: keep a copy off Cloudflare too.
- **Restore** is one call, always into a new vault (`<name>-restored-<date>`): `POST /account/vaults/<name>/restore`.
- Take a snapshot now, before something risky: `curl -H "Authorization: Bearer $(cat ~/parachute/private/ops-run-token)" -X POST $D/ops/snapshot-run -d '{"vault":"home"}'`. Name the vault: without one it only redoes stale backups, and a vault backed up last night isn't stale.
- Deleting a vault deletes its snapshots too.

## Upgrades

Pull `door/0.9` and run `deploy.sh` again with the same profile. It upgrades in place: database changes are applied before the new workers start, and your vaults, keys and snapshots stay. To go back, deploy the commit you were on: database changes only ever add, so your data reads, but you lose what the newer code did (going back to before 2026-11-21 takes the app's one address away, and a raised vault limit falls back to your plan's).

To remove it all, first delete every vault, restored copies included (that empties the bucket), and check none is left; only then the rest:

```bash
D=https://me-parachute-identity.<subdomain>.workers.dev
bun deploy/personal/nip98.ts token $D ~/parachute/me.key acct.curl      # a fresh pass
for v in $(curl -fsS -K acct.curl $D/account/vaults | jq -r '.vaults[].name'); do curl -fsS -K acct.curl -X DELETE $D/account/vaults/$v -d "{\"confirm\":\"$v\"}"; done
curl -fsS -K acct.curl $D/account/vaults | jq '.vaults | length'          # must say 0 before you go on
export CLOUDFLARE_ACCOUNT_ID=<your account id>
bunx wrangler delete --name <PREFIX>-identity; bunx wrangler delete --name <PREFIX>-vault
bunx wrangler d1 delete <PREFIX>-identity; bunx wrangler r2 bucket delete <PREFIX>-vault
```

## Limits today

It runs Parachute Cloud's workers, so it has Cloud's current gaps:
- **Add a pack** in the app stops with "This vault's server doesn't let Parachute make types yet". Making a type takes admin access here, for now.
- **Published records have no public page**: marking one published keeps it to you and your keys, and the app gives no link.
- **Changes** lists edits and their put-back, but not deleted records.
- **One owner.** Extra keys can be listed as admins (an agent's own key, say). They act as the owner, but can't change the sign-in keys, open a browser session or delete the account. Dropping one from the profile and deploying again stops its sign-in; its last 10-minute pass runs out, and the app keys it made stay until you revoke them by name. There are no other people's accounts.
- **More vaults**: `bash deploy/personal/vault-limit.sh ~/parachute/me.env 25` (changing `OWNER_PLAN` later doesn't move an account that exists). The refusal at the limit still tells you to write to Parachute; ignore that and use the script.

## Which one is for me

| | [Parachute Cloud](/docs/run/cloud/) | Your own Cloudflare | [Your own computer](/docs/run/self-host/) |
|---|---|---|---|
| Who runs the machines | we do | Cloudflare, on your account | you |
| What you keep on | nothing | nothing | a computer, day and night |
| Sign in | email | your Nostr key (in a browser: a link from a terminal first) | your key, or a password |
| People | anyone who signs up | you (and keys you name) | as many as you add |
| Setup | sign up | about 15 minutes in a terminal; upgrades are yours to run | install one program |
| Cost | [our pricing](/pricing/) | Cloudflare's: free to try, $5 a month for daily use | your computer and power |
| Backups | ours, and your export | nightly to your own R2 (files: your export), one-call restore | `parachute backup` |
| Everything the engine does | Cloud's current set | Cloud's, with its gaps: no packs, public pages or deleted list yet | all of it, first |
