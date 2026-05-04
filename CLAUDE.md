# website/ — parachute.computer

> Website, blog, and documentation for Parachute Computer.
> Built with Eleventy (11ty). Domain: **parachute.computer**

---

## Structure

```
website/
├── index.njk               # Landing page
├── roadmap.njk              # Current roadmap / scope of work
├── style.css                # Shared styles (all pages use this)
├── CNAME                    # parachute.computer
├── eleventy.config.js       # Build configuration
├── package.json             # Dependencies (just @11ty/eleventy)
├── _includes/               # Nunjucks layout templates
│   ├── base.njk             # Base layout (nav + footer)
│   └── post.njk             # Blog post layout
├── blog/                    # Blog posts (replaces Substack)
│   ├── index.njk            # Blog listing (auto-populated from posts collection)
│   ├── *.md                 # Posts (frontmatter + markdown, auto-rendered)
│   └── drafts/              # Unpublished drafts (excluded from build)
├── architecture/            # Technical architecture docs (passthrough, not templated)
│   ├── index.html           # Architecture overview
│   ├── docs.css             # Architecture-specific styles
│   ├── app-*.html           # Flutter app docs
│   ├── computer-*.html      # Python server docs
│   └── ...
└── archive/                 # Superseded content (passthrough, not linked from nav)
```

---

## Building the Site

```bash
cd website
npm install                  # First time only
npx @11ty/eleventy           # Build to _site/
npx @11ty/eleventy --serve   # Dev server with hot reload
```

The `_site/` output is gitignored. GitHub Pages deployment should build from the 11ty output, not the source directory directly.

---

## Adding a Blog Post

1. Create a markdown file in `blog/` with frontmatter:
   ```markdown
   ---
   layout: post.njk
   title: "Post Title"
   subtitle: "Optional subtitle"
   date: 2026-02-15T12:00:00
   author: "Author Name"
   permalink: /blog/post-slug/
   description: "Meta description for SEO"
   ---

   Your post content in markdown...
   ```

2. That's it. The blog listing auto-populates from the `posts` collection (sorted newest first). The post layout renders the title, date, author, and content automatically.

**Dates**: Use `T12:00:00` suffix on dates to avoid timezone off-by-one issues with Eleventy.

**Drafts**: Put draft markdown in `blog/drafts/`. These are excluded from the build.

---

## Editing Templates

All pages use `_includes/base.njk` for nav and footer. Blog posts additionally use `_includes/post.njk`.

**Nav**: `Blog | Docs | Roadmap | GitHub`
**Logo**: "Parachute Computer" (links to `/`)
**Footer**: Copyright + same four links

All template links use absolute paths (`/blog/`, `/docs/`, `/roadmap/`).

Historical architecture HTML and NVC/pitch content live under `archive/` (see `archive/architecture-v1/` and `archive/nvc/`). They're passthrough-copied but not linked from the main nav.

---

## Technical reference

Current-era architecture lives in `design/` as markdown design notes, indexed from `docs.njk`. Older HTML architecture docs are in `archive/architecture-v1/` for historical reference only.

**When to update design notes**: After significant architectural changes (new modules, API redesigns, trust model changes). Not after every commit.

---

## Keeping Things Current

### Roadmap
- Update `roadmap.njk` at least biweekly
- Move timeline items from "Upcoming" to "Done" as they complete
- Update the "Now" badge to reflect current week

### Blog
- New posts when shipping features, making announcements, or sharing thinking
- Blog is the primary public communication channel (replaces Substack)
- Just write markdown — 11ty handles the rest

### Design notes
- Review after major PRs that change system architecture
- Don't maintain file counts, line numbers, or other fast-changing metrics
- Link to GitHub for anything that changes frequently

### Archive
- Move superseded content to `archive/` rather than deleting
- Don't link to archive from the main nav
- Archive is for historical reference only

---

## Deployment

**As of #25 (2026-05): migrated from GitHub Pages → Cloudflare Pages.** The Pages project builds with `npx @11ty/eleventy` (output `_site/`) and auto-deploys on push to main. The old GH Pages workflow is archived; the `CNAME` file is no longer load-bearing (Cloudflare manages the custom domain).

**CNAME**: `parachute.computer` (DNS now points at Cloudflare Pages)

---

## Interest list / backend

The site has a small backend now (issue #25): an interest-list signup form on the homepage that writes to D1.

```
functions/api/subscribe.ts    Pages Function — POST handler
                              validates email, inserts into D1,
                              redirects to /subscribe/thanks/
migrations/0001_interests.sql D1 schema for the `interests` table
wrangler.toml                 D1 binding (`DB`) + Pages config
subscribe/thanks.njk          /subscribe/thanks/ success page
index.njk                     hosts the inline subscribe form
INFRASTRUCTURE.md             one-time CF setup steps Aaron runs
```

**The schema** (`interests`): `id`, `email`, `name`, `source_path`, `user_id` (reserved), `resend_contact_id` (reserved), `created_at`. No UNIQUE on email — duplicate signups preserve signal.

**No de-dup, no Resend, no admin UI in V1.** Query D1 with `wrangler d1 execute parachute-db --remote --command "SELECT * FROM interests ORDER BY id DESC LIMIT 50"` when you want to see the list. V2 adds Resend; V3 links to a future Parachute user store.

**Adding new Pages Functions**: drop a TypeScript file under `functions/`. The path mirrors the URL — `functions/api/subscribe.ts` → `/api/subscribe`. Export `onRequestPost` / `onRequestGet` / etc. Cloudflare's Pages docs cover the conventions.

**Local dev with the function + D1**: `npx wrangler pages dev _site --d1 DB=parachute-db` (after `npm run build`). Plain `npx @11ty/eleventy --serve` works for static-only iteration.

**Migrations**: `wrangler d1 migrations apply parachute-db --local` (local) or `--remote` (prod). Always pause-and-confirm before running against prod.

---

## Design notes

Architecture design notes live in `design/` — documents that anchor post-launch direction without committing code. Currently (2026-04-20):

- `2026-04-20-module-architecture.md` — the canonical module protocol (info, config, services.json, well-known), third-party extensibility path, scope format
- `2026-04-20-hub-as-portal-oauth-and-service-catalog.md` — OAuth architecture with hub-as-issuer, phasing, service catalog in token response
- `2026-04-20-cloud-offering-sketch.md` — cloud deployment shape (tenant-per-subdomain, Postgres-backed, CDN-hosted Notes, pooled Scribe)

These are reference material; update them when the shape they describe changes. Cross-cutting patterns that apply to multiple repos live in [`../parachute-patterns/`](../parachute-patterns) and should be linked here rather than duplicated.

## Post-merge hygiene

When a PR is merged, locally:

```
git checkout main && git pull
```

Site is Eleventy-built; drift between local checkout and origin/main doesn't break a running daemon (site is a static build), but it still causes confusion — the local `_site/` output reflects whatever branch is checked out, not main. Convention caught and documented across Parachute repos 2026-04-21.
