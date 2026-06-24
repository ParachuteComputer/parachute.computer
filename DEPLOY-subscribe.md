# Deploying the subscribe Worker (email capture)

The homepage "Stay in the loop" form posts visitor emails to a small
standalone **Cloudflare Worker** backed by **D1**. The site itself stays
on **GitHub Pages** — there's no DNS migration. Only the email-capture
backend lives on Cloudflare.

How it fits together:

- The home form (`index.njk`) does a native `<form method="POST">` to the
  Worker's URL (configured in `_data/site.json` → `subscribeEndpoint`).
- The Worker (`worker/subscribe.ts`) validates + normalizes the email,
  inserts a row into the D1 `interests` table, then **303-redirects** the
  browser to `https://parachute.computer/subscribe/thanks/` on success, or
  back to `https://parachute.computer/?subscribe_error=1` on failure.
- Because it's a native form POST and the browser follows the redirect
  itself (the page never reads the cross-origin response with JS), **no
  CORS** is involved.

The interim D1 store is intentionally dumb — no de-dup, no confirmation
email, no admin UI. The data will later be synced into a Parachute vault.

---

## What's left for Aaron (Cloudflare)

One-time setup. Run these from this repo root.

1. **Log in to Cloudflare**

   ```bash
   npx wrangler login
   ```

2. **Create the D1 database**

   ```bash
   npx wrangler d1 create parachute-interests
   ```

   This prints a `database_id`. **Paste it into `wrangler.toml`** in place
   of the `database_id = "PLACEHOLDER"` line, then **commit that change**
   (the placeholder must not stay in `main`).

3. **Apply the migration to the remote DB** (creates the `interests` table)

   ```bash
   npx wrangler d1 migrations apply parachute-interests --remote
   ```

   (Or `npm run db:migrate`.) For a local dev DB, use `--local` instead.

4. **Deploy the Worker**

   ```bash
   npx wrangler deploy
   ```

   This deploys `worker/subscribe.ts` as the `parachute-subscribe` Worker.
   The deploy output includes a `*.workers.dev` URL.

5. **Point the form at the Worker.** Two options:

   - **Custom domain (preferred):** in the Cloudflare dashboard →
     Workers & Pages → `parachute-subscribe` → Settings → Domains &
     Routes, add the custom domain `subscribe.parachute.computer`. (This
     requires `parachute.computer` to be on a Cloudflare zone for DNS; if
     it isn't, use the workers.dev fallback below.) `_data/site.json`
     already defaults to `https://subscribe.parachute.computer/`, so no
     code change is needed if you use this domain.
   - **workers.dev fallback:** if you don't want a custom domain, copy the
     `*.workers.dev` URL from step 4 into `_data/site.json` →
     `subscribeEndpoint`, and commit. The form will post there instead.

6. **Smoke-test.** Load `https://parachute.computer/`, scroll to the
   closing "Stay in the loop" block, submit a real email. You should land
   on `/subscribe/thanks/`. Confirm the row landed:

   ```bash
   npx wrangler d1 execute parachute-interests --remote \
     --command "SELECT id, email, source_path, created_at FROM interests ORDER BY id DESC LIMIT 5"
   ```

   To test the error path, submit an obviously bad email (e.g. `nope`) —
   you should be redirected back to the home with a discreet inline error.

---

## Notes / known gaps

- **No rate limiting (yet).** The Worker accepts any POST; a bot could
  spam rows. This is an accepted simple-start gap — fine for early
  interest-list volume. When it matters, add a Cloudflare Turnstile check
  or a WAF rate-limit rule on the Worker route (no code redeploy needed
  for the WAF rule).
- **No secrets.** The Worker holds nothing sensitive beyond the D1
  binding (`DB`), which is scoped to this Worker by Cloudflare. The D1
  insert is parameterized (no SQL injection surface).
- **Email validation** is permissive on purpose — catches obvious typos
  (`EMAIL_RE`, 254-char cap), not RFC 5322 compliance. D1 is the source of
  truth; junk gets filtered downstream at vault-sync time.
- **No de-dup.** Duplicate signups are tolerated and preserve signal
  (when someone came back, from where, via `source_path`).
- **`source_path` is often NULL.** It's derived from the `Referer`
  header, but most browsers' default Referrer-Policy
  (`strict-origin-when-cross-origin`) sends only the origin — no path —
  on a cross-origin POST. So expect `source_path` to be NULL for the
  majority of real submissions. Not a bug; the Worker handles it
  gracefully. (If per-page attribution ever matters, add a hidden
  `source` input to the form instead of relying on Referer.)
