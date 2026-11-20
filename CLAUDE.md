# parachute.computer

Public site + blog for Parachute Computer, built with Eleventy (11ty), served at
**parachute.computer**. The blog is the primary public communication channel.
Standard 11ty repo — `eleventy.config.js` and `_includes/` show how it builds;
this file only carries what the repo can't tell you.

## Gotchas

- **Blog post dates need the `T12:00:00` suffix** (`date: 2026-02-15T12:00:00`).
  A bare date parses as UTC midnight and Eleventy renders it a day early in
  US timezones — the off-by-one is silent and only visible on the rendered site.
- **One layout, one nav** (`_includes/base.njk`), the homepage included (since T-476; the
  2026-07 self-contained landing is archived at `archive/home-v2/`).
- **The docs are `docs/<door>/<page>.md`** (door: use, build, run), each with `title`,
  `summary`, `door`, `order` and `checked` (the code it was checked against) in its front
  matter. Every page is also served as markdown at `/docs/<door>/<page>.md`
  (`docs-md.njk`), and `/llms.txt` and `/llms-full.txt` are generated from them: write a
  page once and both readers get it. The MCP `docs` tool in parachute-core reads these
  `.md` addresses, so a page's address is a contract: rename one only with a redirect.
  `docs/build/reference/` is generated (`npm run docs:sync`): don't edit it by hand.
- **Don't publish fast-changing metrics** — file counts, version numbers, test
  counts — anywhere on the site or in this file. They go stale silently and then
  read as truth; link to GitHub for anything that changes frequently.

Architecture design notes live in `design/`; update them when the shape they
describe changes, not per commit.
