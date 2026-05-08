# Infrastructure setup — parachute.computer

One-time Cloudflare setup for the V1 interest list (issue #25). Aaron runs these once after this PR is reviewed; tentacles do not.

This doc captures only the moving parts that aren't already in the repo. The code (Pages Function, migration SQL, wrangler config, form) all lives in this repo and deploys from main.

---

## Sequence

1. **Create the Cloudflare Pages project**
   - Cloudflare dashboard → Workers & Pages → Create → Pages → Connect to Git → select `ParachuteComputer/parachute.computer`
   - **Production branch:** `main`
   - **Build command:** `npx @11ty/eleventy`
   - **Build output directory:** `_site`
   - **Root directory:** `/` (default)
   - No environment variables needed at this stage
   - Project name suggestion: `parachute-computer` (matches `wrangler.toml`)

2. **Create the D1 database**
   ```
   npx wrangler d1 create parachute-db
   ```
   Copy the `database_id` from the output and paste it into `wrangler.toml` (replace `PLACEHOLDER_FILL_AFTER_D1_CREATE`). Commit + push so the deploy picks it up.

   You can also create the DB from the dashboard (Workers & Pages → D1 → Create database) if you prefer — same result.

3. **Apply the initial migration**
   ```
   npx wrangler d1 migrations apply parachute-db --remote
   ```
   This creates the `interests` table from `migrations/0001_interests.sql`. Confirm the prompt before it runs against prod.

   Smoke-check:
   ```
   npx wrangler d1 execute parachute-db --remote --command "SELECT name FROM sqlite_master WHERE type='table'"
   ```
   You should see `interests`.

4. **Bind D1 to the Pages project**
   - Pages project → Settings → Functions → D1 database bindings → Add binding
   - **Variable name:** `DB`
   - **D1 database:** `parachute-db`
   - Apply to **Production** (and Preview if you want preview deployments to write to D1 — generally fine since duplicate test rows are harmless).

   The `[[d1_databases]]` block in `wrangler.toml` gives the same binding for `wrangler pages dev` locally; the dashboard binding is what production uses.

5. **DNS swap: GitHub Pages → Cloudflare Pages**
   - Pages project → Custom domains → Set up a custom domain → `parachute.computer`
   - Cloudflare will guide the DNS update. If `parachute.computer` is already on Cloudflare DNS, it's a one-click toggle. If it's elsewhere, point the apex to the Pages target Cloudflare gives.
   - Once DNS resolves, the existing `CNAME` file becomes irrelevant (Pages routes via the custom domain config, not `CNAME`).

6. **Archive the GitHub Pages workflow**
   - Either delete `.github/workflows/deploy.yml`, or disable the workflow from GitHub → Actions. CF Pages handles the build + deploy now.
   - I (the tentacle) left it in place on the PR — flip it off after the CF deploy is healthy so we don't double-deploy.

---

## Smoke test (after step 5)

1. Visit `https://parachute.computer/`, submit your email on the subscribe form.
2. You should land on `/subscribe/thanks/`.
3. Confirm the row landed:
   ```
   npx wrangler d1 execute parachute-db --remote --command \
     "SELECT id, email, source_path, created_at FROM interests ORDER BY id DESC LIMIT 5"
   ```

If the form bounces back to `/?subscribe_error=1`, check the Pages Function logs in the dashboard (Pages project → Functions → Logs).

---

## What's still on you (not in V1)

- **Resend integration (V2)** — confirmation email when someone subscribes.
- **Admin UI** — for now, query D1 directly via `wrangler d1 execute`.
- **Identity linking** — wired into the schema (`user_id` column) but not used until Parachute has user accounts (V3).
- **Substack export** — your call whether to migrate existing Substack subscribers in. Schema doesn't care; you can `INSERT` them by hand or via a one-off script.

---

## Useful commands

```
# Local dev with Pages Functions + D1 (after `npm run build`)
npx wrangler pages dev _site --d1 DB=parachute-db

# Apply migrations locally
npx wrangler d1 migrations apply parachute-db --local

# Apply migrations to prod (pause-and-confirm)
npx wrangler d1 migrations apply parachute-db --remote

# Inspect interests in prod
npx wrangler d1 execute parachute-db --remote --command \
  "SELECT * FROM interests ORDER BY id DESC LIMIT 50"

# Count signups by source page
npx wrangler d1 execute parachute-db --remote --command \
  "SELECT source_path, COUNT(*) FROM interests GROUP BY source_path"
```
