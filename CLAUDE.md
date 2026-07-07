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

**Nav** (one canonical flat nav, identical on the homepage `landing-preview.html` and every `base.njk` page): `Pricing | Blog | Self-host | GitHub | [Get a vault]`. Guides, Docs, and the product pages (Vault/Surfaces/Agents/Modules) live in the footer, not the header. Keep the two headers in lockstep when editing.
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

GitHub Pages deployment needs to run `npx @11ty/eleventy` and serve `_site/`. Options:
- GitHub Action that builds on push to main, then deploys the `_site/` output
- Or configure GitHub Pages to use a GitHub Action workflow instead of serving directly from `website/`

**CNAME**: `parachute.computer` (DNS needs to point to GitHub Pages)

---

## Design notes

Architecture design notes live in `design/` — documents that anchor post-launch direction without committing code. Currently (2026-04-20):

- `2026-04-20-module-architecture.md` — the historical origin of the module protocol (info, services.json, well-known, scope format, extensibility path); the hub-rendered-config-form model and `kind` taxonomy it describes are retired — for current ownership rules see [`parachute-patterns/patterns/hub-module-boundary.md`](https://github.com/ParachuteComputer/parachute-patterns/blob/main/patterns/hub-module-boundary.md)
- `2026-04-20-hub-as-portal-oauth-and-service-catalog.md` — OAuth architecture with hub-as-issuer, phasing, service catalog in token response
- `2026-04-20-cloud-offering-sketch.md` — cloud deployment shape (tenant-per-subdomain, Postgres-backed, CDN-hosted Notes, pooled Scribe)

These are reference material; update them when the shape they describe changes. Cross-cutting patterns that apply to multiple repos live in [`../parachute-patterns/`](../parachute-patterns) and should be linked here rather than duplicated.

## Post-merge hygiene

When a PR is merged, locally:

```
git checkout main && git pull
```

Site is Eleventy-built; drift between local checkout and origin/main doesn't break a running daemon (site is a static build), but it still causes confusion — the local `_site/` output reflects whatever branch is checked out, not main. Convention caught and documented across Parachute repos 2026-04-21.
