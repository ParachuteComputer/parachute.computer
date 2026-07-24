# parachute.computer

Public site + blog for Parachute Computer, built with Eleventy (11ty), served at
**parachute.computer**. The blog is the primary public communication channel.
Standard 11ty repo — `eleventy.config.js` and `_includes/` show how it builds;
this file only carries what the repo can't tell you.

## Gotchas

- **Blog post dates need the `T12:00:00` suffix** (`date: 2026-02-15T12:00:00`).
  A bare date parses as UTC midnight and Eleventy renders it a day early in
  US timezones — the off-by-one is silent and only visible on the rendered site.
- **The header nav lives in two places**: the homepage (`landing-preview.html`)
  and every other page (`_includes/base.njk`). They must stay identical — when
  editing the nav, change both in lockstep.
- **Don't publish fast-changing metrics** — file counts, version numbers, test
  counts — anywhere on the site or in this file. They go stale silently and then
  read as truth; link to GitHub for anything that changes frequently.

Architecture design notes live in `design/`; update them when the shape they
describe changes, not per commit.
