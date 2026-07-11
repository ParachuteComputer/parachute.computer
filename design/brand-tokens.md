---
title: "Parachute brand tokens — seed reference"
description: "The new-brand palette, type, and shape tokens extracted from landing-preview.html + style.css — OBSERVED vs PROPOSED, with per-app adoption deltas. A seed, not a ratified design system."
---
# Parachute brand design tokens — seed reference

Extracted from the new "vibrant" brand as piloted on `parachute.computer`. This is a **seed**, not a
ratified design system — Todd asked "is there a design system?" and the honest answer today is "not
yet." Everything marked **OBSERVED** is copied verbatim from source. Everything marked **PROPOSED** is
a judgment call this document is introducing — never treat a PROPOSED value as already-decided.

Primary source (§§1–4 as originally written, 2026-07-09): `parachute.computer/landing-preview.html`
(self-contained, THE canonical new-brand artifact — see its own header comment at lines 21-35 for the
stated tone target). Secondary source: `parachute.computer/style.css` + `_includes/base.njk` (inner
pages — ports the landing's tokens, with some drift; drift is called out throughout, not smoothed
over).

> **Update (app v0.5.0, 2026-07-11) — the palette has since been ratified downstream, and this doc now
> mirrors that.** `parachute-app` (seeded from notes-ui, now the portable super-surface) shipped the
> "hybrid" pass — `app-w2-1-tokens`, merged app PR #12 — moving from the audit's PROPOSED sketches to
> real, shipped values: warm cream/forest/sage grounds, the coral accent **retained as-is**, sage-tinted
> shadows, a pill-plus-24px-card radius system, self-hosted Fraunces + Figtree, and a real "forest
> night" dark theme (Aaron's ratified decision c: "app + site move together"). §1–§3 below have been
> updated to mirror `parachute-app/src/styles/index.css` at that tag exactly, so this doc no longer
> just describes what the site does — for grounds/ink/accent/shadow/radius/type it now records the
> ecosystem's **canonical, shipped** values, sourced from the app rather than the site. **The site's own
> `landing-preview.html` / `style.css` have not been repainted to match** — they still carry the
> pre-hybrid hex values recorded below as OBSERVED; adopting the new palette into the site's actual CSS
> is separate, un-started work. Original per-app delta notes (§5) are left as historical audit record
> unless a callout says otherwise.

---

## 1. Palette

### Grounds

**SHIPPED (app v0.5.0)** — grounds move from blush paper to a cream/sage world; the app's card lifts a
breath off the canvas instead of sitting at hard white. The site's own `landing-preview.html`/`style.css`
have not adopted these yet — the "OBSERVED at" column below still points at the site's pre-hybrid values.

| Token | Hex (shipped, app v0.5.0) | Was (site OBSERVED at) | Notes |
|---|---|---|---|
| `--pc-paper` | **`#fafaf6`** | `#fdfaf4` — landing:41, style.css:23 | cream canvas, app `--color-bg` |
| `--pc-paper-2` | **`#f7f5ec`** | `#f7f1e6` — landing:42, style.css:24 | recessed/wash band, app `--color-bg-soft` |
| `--pc-sky-band` | `#eef5f9` (unchanged) | landing:43 (`--sky`), style.css:25 (`--sky-band`) | cool sky band — **name collision, see below** — not touched by the hybrid pass |
| `--pc-card` | **`#fefefa`** | `#ffffff` — landing:44, style.css:26 | app `--color-card`; a breath off the canvas, not hard white |

**Naming collision to flag:** the landing page names this token `--sky` (landing-preview.html:43).
`style.css` renamed it `--sky-band` (style.css:25) and then **reused the bare name `--sky`** for a
completely different color — `#5b8fa8`, a mid-tone blue used as the "active" status hue (style.css:61,
used at style.css:933-935 `.status-active`). So within `parachute.computer` alone, `--sky` means two
different colors depending which file you're in. Any shared token package must not carry the bare
`--sky` name forward without resolving this — recommend `--pc-sky-band` (pale wash) vs
`--pc-status-active` (`#5b8fa8`) as distinct names.

### Inks

**SHIPPED (app v0.5.0)** — ink moves from warm brown to **forest**, with a sage-cast secondary tier;
values below are the app's, the "Was" column is the site's current (unchanged) values.

| Token | Hex (shipped, app v0.5.0) | Was (site OBSERVED at) | Notes |
|---|---|---|---|
| `--pc-ink` | **`#233c2a`** | `#2a2521` — landing:45, style.css:27 | forest ink, app `--color-fg` — 11.46:1 on the new `--pc-paper` |
| `--pc-ink-soft` | **`#5b6f5e`** | `#6b6459` — landing:46, style.css:28 | sage-cast secondary text, app `--color-fg-muted` — 5.17:1 |
| `--pc-line` | **`#e4ece4`** | `#ece5d8` — landing:47, style.css:29 | lighter hairline, sage-cast, app `--color-border-light` |
| `--pc-line-2` | **`#d6e2d6`** | `#e2d9c8` — landing:48, style.css:30 | visible hairline, sage-cast, app `--color-border` |

The doc's own open question is now resolved: `--fg-dim` (`#9a9184`, style.css:55 — "New token, not in
the canonical landing file... worth deciding if it's promoted") **is promoted**, as `--pc-ink-dim`, with
a new shipped value: `#8a968b` (app `--color-fg-dim`, 2.94:1 — tertiary/placeholder text only, sub-AA
**by design**, never body copy). The site's own `#9a9184` inner-pages-only value is unchanged.

### Accents

**Coral confirmed RETAINED, unchanged, by the hybrid pass (ratified decision c)** — the accent hue does
not move; only the grounds and ink around it do. Ratios were recomputed on the new cream canvas and
still pass AA: `--pc-coral-btn` is 4.97:1 white-on-button (unchanged) and 4.75:1 sitting directly on the
new `--pc-paper` (was checked against the old paper before). One value shifts (`--pc-grass-soft`) and one
token is net-new (`--pc-sage`) — both called out below; everything else in this table is unchanged.

| Token | Hex | OBSERVED at | Role |
|---|---|---|---|
| `--pc-coral` | `#e05d3c` | landing:49, style.css:31 | display accent — **large text only**, not for small UI (in-source comment). **Retained as-is in app v0.5.0.** |
| `--pc-coral-btn` | `#bf4a2a` | landing:50, style.css:32 | button bg + white text — 4.97:1 (documented in-source). **Retained as-is**; recomputed at 4.75:1 on the new cream canvas (app). |
| `--pc-coral-soft` | `#fbe4d9` | landing:51, style.css:33 | tinted background for coral-family chips/badges/"featured" cards. **Retained as-is.** |
| `--pc-coral-ink` | `#8f3417` | landing:52, style.css:34 | coral-family text on `coral-soft` background (AA). **Retained as-is** — 6.44:1 (app). |
| `--pc-link` | `#2f6f96` | landing:53, style.css:35 | link color / secondary interactive text — 5.26:1 |
| `--pc-link-hover` | `#245570` | style.css:36 only (`--link-hover`, aka "blue-ink") | not a separate token in landing's `:root`, but landing uses the identical hex inline as `--blue-ink` (landing:55) |
| `--pc-link-light` | `#7ba7c1` | style.css:37 only | soft blue for borders/bullets/dots — inner-pages-only addition, not in landing |
| `--pc-blue-soft` | `#dcebf3` | landing:54, style.css:38 | tinted blue background (chips) |
| `--pc-sun` | `#f4c020` | landing:56, style.css:39 | playful highlight; ink text on it is ~9:1 (in-source). **Retained as-is.** |
| `--pc-sun-soft` | `#fdf1c9` | landing:57, style.css:40 | tinted sun background. **Retained as-is.** |
| `--pc-sun-ink` | `#6b5200` | landing:58, style.css:41 | sun-family text. **Retained as-is.** |
| `--pc-grass` | `#3f8a58` | landing:59 | "grow-with-you" green, large accent only. **Retained as-is.** |
| `--pc-grass-btn` | `#2f7647` | landing:60 | button-weight grass. **Retained as-is.** |
| `--pc-grass-soft` | **`#e1f0e4`** (was `#dcefe0`) | landing:61 (site unchanged); app `--color-grass-soft` | tinted grass background — nudged sage-ward in app v0.5.0; grass-ink is 6.67:1 on it |
| `--pc-grass-ink` | `#245c39` | landing:62 | grass-family text. **Retained as-is.** |
| **`--pc-sage`** (NEW, app v0.5.0) | **`#527e5d`** | app `--color-sage`, `src/styles/index.css` | the app prototype's sage **green** — eyebrows, section labels, quiet icons (4.46:1 on `--pc-paper`, 4.27:1 on `--pc-paper-2`). **Naming collision, flagged so it isn't repeated:** the app's own codebase (notes-ui lineage) previously had `--color-sage` meaning *blue* (identical to `--pc-status-active` / app `--color-sky`, `#5b8fa8` — see the `--sky` collision above); v0.5.0 fixed that in-app (five call sites repointed to `--color-sky`) so `--color-sage` now means green, as any reader would assume. This doc has never carried a `--pc-sage` token before now, so there's nothing to rename here — just don't reintroduce the blue meaning under this name. |

**Inconsistency:** the full `--grass` family (5 values, landing:59-62) is **not carried into
style.css's `:root` at all**. style.css only reuses the grass hue as hardcoded literals in one place —
`.status-done` (style.css:927-930: `rgba(63, 138, 88, .12)` background, `#245c39` text) — with an
in-source comment ("grass — 'shipped' reads distinct from the sky 'active'") confirming intent, but no
actual `--grass*` custom properties exist on the inner pages. If grass becomes a real semantic color
(success/shipped), it needs to be promoted to a token, not left as copy-pasted rgba literals.

### Semantic gap (not yet a token anywhere in the brand)

There is **no dedicated error/danger token** in either the landing page or `style.css`. The one error
state that exists — `.join-error` (landing:358) — is hardcoded: `background:#fbe4e0; color:#8f2c1c`,
never assigned to a `--pc-*` variable. Both downstream apps already have real danger tokens
(notes-ui `--color-danger:#c0492f`; cloud console `--danger:#a5372b`) — the brand itself is the outlier
here and should mint `--pc-danger`/`--pc-danger-soft`/`--pc-danger-ink` following the same
soft/ink-on-soft pattern used for coral/sun/grass, ideally reconciled with the two apps' existing
reds rather than introducing a fourth.

### Dark theme

**The site itself (landing page + `style.css`) still has no dark theme, `prefers-color-scheme`, or
`data-theme` handling** — that part of the original observation stands, unchanged. But the "PROPOSED,
unverified" sketch that used to fill out this section is now **superseded by a real, shipped dark
theme**: `parachute-app` v0.5.0 shipped **"forest night"** — a net-new dark design (the prototype this
palette comes from never had a dark mode to fall back on), not a proposal. The table below replaces the
old sketch with the app's actual shipped values, read from `src/styles/index.css`'s private `--_d-*`
dark-token block; ratios are the app's own recomputed figures, not estimates.

The technique (private `--_d-*` tokens behind both `@media (prefers-color-scheme:dark)` and an explicit
`[data-theme="dark"]` override, so both gates share one source of truth) is unchanged from the prior
notes-ui lineage — see brand-tokens §5 for that history. What's new in the hybrid pass is the palette
itself: warm near-black gives way to a **green-cast** near-black, and the coral accent lightens for the
dark ground exactly as the old proposal predicted, with contrast now measured rather than guessed.

| Token | Hex (shipped, app v0.5.0) | Was (this doc's prior PROPOSED sketch) | Notes |
|---|---|---|---|
| `--pc-bg-dark` | **`#161d18`** | `~#1c1815` (proposed) | forest-night ground, app `--_d-bg` |
| `--pc-bg-soft-dark` | **`#1c241d`** | *(not previously proposed)* | recessed dark surface, app `--_d-bg-soft` |
| `--pc-card-dark` | **`#1e271f`** | `~#252019` (proposed) | app `--_d-card` |
| `--pc-ink-dark` | **`#e7ece5`** | `~#f0ebe1` (proposed) | app `--_d-fg` |
| `--pc-ink-soft-dark` | **`#a7b3a7`** | `~#a89f8f` (proposed) | app `--_d-fg-muted` |
| `--pc-ink-dim-dark` | **`#71806f`** | *(not previously proposed)* | tertiary/placeholder, app `--_d-fg-dim` — mirrors the `--pc-ink-dim` promotion above |
| `--pc-line-dark` | **`#303b31`** | `~#3a332a` (proposed) | app `--_d-border` |
| `--pc-line-light-dark` | **`#283229`** | *(not previously proposed)* | app `--_d-border-light` |
| `--pc-coral-dark` | **`#ec7a5c`** | `~#ec7a5c` (proposed — landed exactly) | app `--_d-accent` — 6.14:1 on `--pc-bg-dark`, 5.50:1 on `--pc-card-dark` |
| `--pc-coral-hover-dark` | **`#f08d70`** | *(not previously proposed)* | app `--_d-accent-hover` — 7.15:1 on `--pc-bg-dark` |
| `--pc-sage-dark` | **`#8fb096`** | *(net-new; `--pc-sage` itself is new — see Accents)* | app `--_d-sage` — 7.21:1 on `--pc-bg-dark`, 6.46:1 on `--pc-card-dark` |
| `--pc-grass-soft-dark` | **`#1e3527`** | *(not previously proposed)* | app `--_d-grass-soft` |

**The WCAG-AA on-accent flip, now real:** because the dark accent *lightens* (unlike the light-mode
accent, which is a saturated button hue), white-on-accent text would fail contrast in dark mode. The app
resolves this by flipping `--color-on-accent` to a **dark warm ink** (`#2a1710`, 6.11:1 on the dark
accent) whenever dark mode is active, rather than keeping white — the same on-accent-flip technique the
prior notes-ui dark theme used, now carrying the coral hue instead of forest-green.

Treat this table as the shipped reference for whenever the *site* adopts a dark theme — the app side of
this is no longer a sketch.

---

## 2. Typography

### Families (exact stacks as written)

| Token | Stack | Role | OBSERVED at |
|---|---|---|---|
| `--font-serif` | `ui-serif,"New York","Iowan Old Style",Georgia,"Times New Roman",serif` | display headlines | landing:64, style.css:47 |
| `--font-round` | `ui-rounded,"SF Pro Rounded","Arial Rounded MT Bold","Hiragino Maru Gothic ProN",Quicksand,system-ui,sans-serif` | UI chrome — buttons, nav, labels, eyebrows | landing:63, style.css:46 |
| `--font-body` | `-apple-system,system-ui,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif` | body copy | landing:65, style.css:48 |
| `--mono` | `ui-monospace,"SF Mono","JetBrains Mono",Menlo,Monaco,"Cascadia Code",monospace` | inner-pages-only micro-labels | style.css:70 — **not present in landing at all** |

All three brand fonts were deliberately **system stacks — no webfont download**. This was explicit,
stated intent: landing-preview.html:27-28 ("Fonts are system stacks... no webfont download") and
style.css:12 ("Fonts are system stacks... Google Fonts retired"). **The site itself still holds this
line** — landing-preview.html and style.css are unchanged, still system-stack-only.

**SHIPPED (app v0.5.0) — the app has since moved off system stacks, on purpose, letter and all:**
`parachute-app` now ships **Fraunces (display) + Figtree (body/chrome)**, self-hosted via
`@fontsource-variable` (OFL-licensed, woff2 bundled by Vite, precached by the service worker — no
Google Fonts, no CDN request, ever; `font-display: swap` with the tuned system stacks above kept as
fallbacks so first paint is never blocked on the font download). Read literally, this breaks the old
"no webfont download" sentence — but it keeps the principle that sentence was protecting (no
third-party/CDN font request, CSP-safe, works offline): self-hosted is not the same risk as
Google-Fonts-hosted. The app's actual stacks:

| Token (app) | Stack | Role |
|---|---|---|
| `--font-serif` | `"Fraunces Variable", ui-serif, "New York", "Iowan Old Style", Georgia, serif` | display headlines — ships the `opsz` (optical-size) axis **and** the italic file; the optical-size axis IS the display voice, and the italic file is load-bearing for the accent-word device below |
| `--font-sans` | `"Figtree Variable", -apple-system, system-ui, "Segoe UI", Roboto, sans-serif` | body copy **and** UI chrome — buttons, nav, labels, eyebrows |
| `--font-round` | alias of `--font-sans` | **retired** as a distinct family — the rounded UI voice folded into Figtree; the var name is kept (zero component churn) but it now just points at the body stack |

Font weight, in the site's own precache-budget terms: Fraunces (opsz + italic) + Figtree (upright), all
subsets bundled, is **~344 KiB** woff2 (a latin-only subset would run closer to ~165 KiB) — within the
app's own ~350 KB type budget.

**The one coral italic accent word.** Fraunces's italic file exists specifically to carry a device the
app uses on hero/arrival copy: exactly one word per headline set in italic coral (`--pc-coral`/
`--color-accent-light`), the rest of the headline in the regular serif weight/color — "playfulness kept
contained" (§4) made literal in type rather than decoration. Real italics (not a synthetic
oblique) are why the italic axis had to ship alongside the upright opsz axis.

The site's own system-stack fonts remain unchanged; adopting Fraunces/Figtree on the site is not part of
this update.

### Scale (fluid `clamp()` literals — there is no discrete `--text-*` scale on the brand side)

| Role | Spec | OBSERVED at |
|---|---|---|
| Display (hero h1, landing) | `font-serif` 600, `clamp(2.4rem,7vw,4.3rem)`, line-height 1.08, letter-spacing `-.012em` | landing:159-163 |
| Display (hero h1, inner pages) | `font-serif` 600, fixed `4.5rem`, line-height 1.05, letter-spacing `-0.03em` | style.css:363-371 |
| Heading (`h2.big`, landing) | `font-serif` 600, `clamp(1.9rem,4.6vw,2.9rem)`, line-height 1.12, letter-spacing `-.005em` | landing:129-133 |
| Heading (`.section h2`, inner) | `font-serif` 600, fixed `1.75rem`, letter-spacing `-0.01em` | style.css:422-431 |
| Heading (`.post-header h1`) | `font-serif` 600, `3rem`, line-height 1.15, letter-spacing `-0.02em` | style.css:1034-1041 |
| Heading (`.roadmap-header h1`) | `font-serif` 600, `3rem`, letter-spacing `-0.02em` | style.css:803-809 |
| Lede/sub | `font-body`, `clamp(1.05rem,2vw,1.2rem)`, color `ink-soft`, max-width `34rem` | landing:134, 165 |
| Eyebrow / micro-label | `font-round` 600, `.82rem`, letter-spacing `.14em`, uppercase, color `coral-ink` | landing:124-128 |
| Body | `font-body`, line-height 1.6 (landing) / 1.65 (style.css) | landing:83, style.css:87 |
| Small print | `.82rem`–`.88rem`, `ink-soft` | landing:168, 371; style.css:785 |
| Buttons | `font-round` 600, `~1.02rem` (primary), `.92rem` (nav-scale) | landing:106, 150 |

**Inconsistency, called out plainly:** letter-spacing on serif display headings ranges from `-.005em`
(landing h2) to `-0.03em` (inner-page hero h1) — no single curve is applied consistently by size, and
the inner-page hero doesn't even reuse the landing's own hero values (different line-height, different
letter-spacing, no fluid clamp at all — it's a fixed `4.5rem`). Recommend picking one
tighter-at-larger-sizes curve when this gets formalized, rather than porting the current per-page
literals forward.

Letter-spacing habit for uppercase micro-labels is more consistent: generous tracking, `.06em`–`.14em`
range (landing eyebrow `.14em`; style.css's mono labels `.1em`; `.sow-meta dt` `.06em`).

---

## 3. Shape & rhythm

### Radii

The one universally agreed shape motif across the **entire** ecosystem (landing, inner pages, notes-ui,
cloud console) is **pill buttons at `999px`/`9999px`**. Everything else diverges:

| Surface | Card radius range | OBSERVED |
|---|---|---|
| Landing (`landing-preview.html`) | **18–26px** — `.vg-static`/`.vg-vault` 24, `.vg-recall` 20, `.price` 22, `.join-card` 26, `.moment`/`.vcard` 18 | landing:186,211,271,320,339,294,301 |
| Inner pages (`style.css`) | **8–13px** — `.product`/`.blog-post-card`/`.cta` 12, `.code-inline` 8, `.nav-menu-panel` 13, `.ladder-rail rung` 11 | style.css:548,986,628,700,294,1516 |
| **`parachute-app` (SHIPPED, v0.5.0)** | **24px cards/modals** (`--radius-2xl`, net-new) — `.card`, `.dialog-panel`; `--radius-lg` 10→12px, `--radius-xl` 14→16px also stepped up; `.btn`/`.input`/`.select` moved to full pills (`--radius-full`, 9999px), `.textarea` to `--radius-xl` | `src/styles/index.css` `--radius-*` block |
| notes-ui (pre-hybrid baseline `parachute-app` was seeded from) | **3–14px** systematic ramp (`--radius-xs` 3 → `--radius-xl` 14), cards use `lg` = 10px | agent report, 2026-07-09 audit |
| Cloud console | **7–14px** one-off literals, `.card` 14, inputs/buttons 9 | agent report |

**The biggest shape gap in the original audit is now partly resolved, one surface at a time.**
`parachute-app` (seeded from notes-ui) has moved its card radius from 10px all the way to **24px** —
landing directly closer to the homepage's generous 18–26px softness than any downstream surface managed
before. The site's own inner pages (`style.css`, 8–13px) and the cloud console (7–14px) are unchanged and
still sit in the tighter "boxy-professional" range — so the gap between the *site's* two faces (soft
landing vs. boxy inner pages) is exactly as unresolved as it was on 2026-07-09. Only the app side has
moved. If 24px/pill is meant to become *the* brand card language, the site's own `style.css` and the
cloud console are the surfaces still left to convert.

### Borders / hairlines

Base hairline is `1px solid var(--line)` everywhere (landing, style.css, notes-ui, cloud's `.line`).
Landing additionally uses a **thicker 1.5–2px border on things you touch** — buttons (`2px`, landing:107),
`.vg-note` (`1.5px`, landing:195), chipset labels (`1.5px`, landing:353), signup input (`1.5px`,
landing:347). This "thicker border = interactive" convention isn't clearly mirrored on inner pages
(mostly flat 1px) or in either app.

### Shadows

`--shadow-soft: 0 10px 30px rgba(60,45,30,.08)` and `--shadow-lift: 0 18px 44px rgba(60,45,30,.12)` —
warm, ink-tinted, ported **byte-identical** from landing:66-67 into style.css:43-44. But style.css
doesn't apply them consistently: several inner-page components fall back to hardcoded **neutral**
`rgba(0,0,0,…)` shadows instead — `.product` (style.css:551), `.blog-post-card` (style.css:991),
`.sow-meta` (style.css:831), `.nav-menu-panel` (style.css:295) — which read flatter/colder than the
landing's warm glow. Cloud console has **zero** `box-shadow` declarations anywhere — it conveys
elevation purely through borders and flat background swaps, which is the flattest-reading surface in the
whole set. (All of the above is still true and unchanged — it describes the site + cloud console, not
the app.)

**SHIPPED (app v0.5.0) — the tint moves from warm-brown to sage-green, and the geometry changes too.**
The old notes-ui shadows were warm ink-mixed (`color-mix(in srgb, #2c2a26 N%, transparent)` —
`#2c2a26` and the site's `rgba(60,45,30,…)` were close cousins in the same warm-brown family, an
encouraging if uncoordinated convergence). The hybrid pass retunes that tint to **forest** for the
elevation ramp, and gives the resting/floating pair (`-soft`/`-lift`) a genuinely different geometry —
sage-tinted, negative-spread, in `oklch` rather than `rgba`:

| Token | Shipped value (app v0.5.0) | Notes |
|---|---|---|
| `--shadow-sm` | `0 1px 2px color-mix(in srgb, #24422e 6%, transparent)` | app `--shadow-sm` — same percentages as before, tint moved warm-brown→forest |
| `--shadow-md` | `0 2px 8px color-mix(in srgb, #24422e 8%, transparent), 0 1px 2px color-mix(in srgb, #24422e 5%, transparent)` | app `--shadow-md` |
| `--shadow-lg` | `0 8px 24px color-mix(in srgb, #24422e 12%, transparent), 0 2px 6px color-mix(in srgb, #24422e 6%, transparent)` | app `--shadow-lg` |
| `--shadow-soft` | `0 12px 40px -18px oklch(40% 0.05 152 / 0.22)` | app `--shadow-soft` — the prototype's negative-spread "settling gently onto paper" resting-card shadow; net-new geometry, not a retint of the old `--shadow-soft` |
| `--shadow-lift` | `0 24px 60px -30px oklch(40% 0.05 152 / 0.28)` | app `--shadow-lift` — floating sheet / FAB / popover / command-palette elevation |

This is a real divergence worth flagging, not smoothing over: the site's own `--shadow-soft`/`-lift`
(warm-brown `rgba`, byte-identical since landing:66-67) and the app's `--shadow-soft`/`-lift` (sage-green
`oklch`, negative-spread) now share names but not values or even color models. If this file becomes the
single source of truth, that collision needs a resolution (rename one, or accept that "soft/lift" means
two different things depending on surface) — flagging the decision, not making it, same as the radii
gap above.

### Gradient / wash motifs

- **Sky-wash**: a fixed `body::before` gradient at the very top of the page —
  `linear-gradient(180deg,#eaf3f8 0%,#f4f6f2 32%,var(--paper) 70%)` at `70vh` (landing:89-92) vs
  `linear-gradient(180deg, #eaf3f8 0%, #f4f6f2 34%, var(--paper) 72%)` at `60vh` (style.css:96-105) —
  same three colors, slightly different stop percentages and height. Minor drift, not a hard
  inconsistency, but worth syncing if this file ever becomes the single source of truth.
- **Section band gradients**: `.vault-sec`/`.layers-sec` fade a paper-2 or sky band in and out at the
  top/bottom of a section for a "breathing" rhythm (landing:181, 314) — landing-only, not replicated on
  inner pages.
- **Parachute-drop note motif**: the tilted note chip that free-falls under a tiny parachute icon and
  settles with a bounce (`.vg-node`, landing:227-269) is the brand's literal core visual metaphor. It
  exists only in the homepage's interactive demo right now — nowhere else references it.
- **Hand-drawn parachute mark**: the open SVG glyph (`#pchute` symbol), colored via `.pc-canopy`
  (coral) / `.pc-gore` (coral-btn) / `.pc-string` (ink-soft) / `.pc-load` (sun) / `.pc-load-ring`
  (sun-ink) — shared between landing and every `base.njk` page (nav + footer). Explicitly NOT Apple's
  copyrighted glyph and NOT the old network-graph logo (in-source comment, landing:29-30).
- **SHIPPED (app v0.5.0) — canvas wash retinted, coral → grass/sage.** `parachute-app`'s own top-of-page
  wash (`--canvas-wash`, consumed by `.app-canvas`) moved from a coral-tinted glow to a grass/sage-tinted
  one — "the blush wash → misty sage morning" move, at 7% in light mode / 5% in dark. This is a
  different wash from the site's blue "sky-wash" gradient above (different hue family, different
  technique — a `color-mix` radial vs. a fixed linear gradient) — noted here for completeness, not as a
  claim that the two are related.

### Spacing rhythm

Landing sections use fluid `clamp(3.5rem,8vw,6rem) 0` top/bottom padding throughout (landing:121).
style.css uses fixed `5rem 2rem` main padding plus `4.5rem` section margins, with a single `@640px`
breakpoint override (style.css:329,419,1248-1312) — comparable *magnitude*, different *technique*
(continuous fluid scaling vs. one discrete breakpoint).

---

## 4. Voice cues

The file's own header comment states the target directly (landing-preview.html:24-28): **"the MIDDLE
between 'we are very smart' (serif-editorial) and 'fun toddler' (all-rounded, emoji-heavy) — serif
display headlines over the warm palette; playfulness lives in the demo, not in decoration."** That's
the calibration to hold apply-pass judgment calls against.

In practice that shows up as: warm, specific, small-scale copy over abstract claims ("Call Mom,"
"Mom's birthday — Sept 3," "a dream about flying — again" rather than generic feature bullets); short,
punchy ledes that undercut their own cleverness ("Storage is easy. Connection is everything.");
open-source/self-hosted pride stated plainly, not boastfully ("Open source · yours forever"); and
playfulness kept contained to the interactive demo (parachutes literally falling and settling) rather
than leaking into UI chrome, which stays calm and legible.

---

## 5. Delta notes per app

> **2026-07-11 update:** the section below is left as the historical 2026-07-09 audit record — it's
> what prompted the swaps, not a live status board. For the record: `parachute-app` (seeded from
> notes-ui — `git log` shows "Scaffold parachute-app — the super-surface (seed from notes-ui 0.2.1)")
> has since shipped several of the "highest-impact swaps" listed for notes-ui below, most visibly #2
> (ground warmth — now the full cream/sage grounds, not just a small nudge), #4 (card radius — now 24px,
> not just 16-20px), and a version of #3 (font sourcing — Fraunces + Figtree, self-hosted, rather than
> either "keep Instrument Serif" or "adopt the brand's bare system stack"). See the updated §1–§3 above
> for the shipped values. Swap #1 (accent hue) reads as already-coral in the current app codebase, so it
> must have shipped in an earlier pass not covered by this doc.

### notes-ui (`parachute-surface/packages/notes-ui`)

Currently: a full Tailwind v4 `@theme`-driven token system, Google-Fonts-loaded Instrument Serif
(headings) + DM Sans (body) + JetBrains Mono, a forest-green/sage accent (`#4a7c59` family, not
coral), complete light+dark parity, a systematic 3–14px+pill radius ramp, and already-warm ink-mixed
shadows. It's explicitly self-documented in its own file header as "the CANONICAL starting point other
Parachute surface authors copy" — so any change here has ecosystem-wide ripple, not just local effect.

Highest-impact swaps:
1. **Accent hue** — sage (`#4a7c59` family) → coral (`#e05d3c`/`#bf4a2a` family) across
   `--color-accent`/`-hover`/`-light` and the matching `--_d-accent-*` dark tokens. The single biggest
   brand-alignment move.
2. **Ground warmth** — `--color-bg:#faf8f4` → `--pc-paper:#fdfaf4`. Low-risk: notes-ui is already warm,
   this is a tiny nudge, not a hue change.
3. **Font sourcing** — decide whether to drop Google Fonts' Instrument Serif for the brand's system
   `ui-serif`/New York stack (which would also honor the "Google Fonts retired" decision already made
   in `style.css`'s own header comment), or keep Instrument Serif deliberately as a close-in-spirit
   serif choice. This is a judgment call for the apply pass, not a mechanical find-replace.
4. **Card radius** — notes-ui's `--radius-lg` (10px) sits with `style.css`'s tight inner-page language,
   not landing's soft 18–26px cards. If soft-big-radius becomes canonical, `--radius-lg` likely needs
   to move toward 16–20px — a system decision, not a token copy.
5. **Status/accent-tinted badges** — notes-ui already has more semantic tokens than the brand does
   (`--color-danger`/`-warning`/`-positive`); these should stay as-is, but need a coral-family
   "featured/highlight" equivalent to match landing's `--coral-soft` treatment (e.g. `.price.feature`).

### Cloud console (`parachute-cloud/workers/identity/src/ui.ts`)

Currently: a hand-rolled 8-variable palette (`bg #f4f6f1`, `card #fff`, `ink #2b332a`, `muted #6a7566`,
`line #dde3d6`, `sage #5f7a57`/`#4c6547`, `danger #a5372b`), Google Fonts Instrument Serif + DM Sans, no
radius/shadow/spacing tokens at all (every value is a one-off literal), no dark theme, **zero**
`box-shadow` usage anywhere, and a narrow centered form-page layout (`max-width:30rem`) — a much older,
smaller implementation than notes-ui's.

Highest-impact swaps:
1. **Build the token layer first.** Today there are only 8 loose custom properties; everything else
   (roughly a dozen recurring near-white utility grays like `#eef0ea`/`#eff3ea`/`#e4e8dd`, and a
   7–14px radius cluster) is a hardcoded literal repeated across 40+ selectors. Promoting those to
   named tokens is a prerequisite for a clean brand swap, not optional — otherwise coral has to be
   hand-chased through scattered hex values.
2. **Accent hue** — sage (`#5f7a57`/`#4c6547`) → coral, same directional move as notes-ui. Worth
   noting: two ecosystem surfaces independently landed on sage/forest-green as an accent before this —
   naming that as a "previous shared convention" might be useful context when it's swapped out.
3. **Ground warmth** — `#f4f6f1` (cool-leaning, slightly green) → `--pc-paper:#fdfaf4` (warm). Bigger
   perceptual shift here than for notes-ui, since cloud's current ground isn't already warm.
4. **Add shadows** — cloud has none. Adopting `--shadow-soft`/`--shadow-lift` (or a scaled-down
   version) on `.card` is the single highest-impact, lowest-risk addition; it currently reads flatter
   than every other surface in the ecosystem.
5. **Pill buttons** — `.card` at 14px radius already sits close to `style.css`'s 12–13px inner-page
   cards (no change needed there), but buttons/inputs at 9px are NOT pills, unlike every other surface
   in the brand family. Converting primary/secondary buttons to `999px` pill radius is the most visible
   single change available and the cheapest to ship.

---

## 5b. Console-minted proposals (2026-07-09, cloud#109)

The cloud console's brand pass (parachute-cloud#109) needed fill-role tokens this doc had no
answer for. Its reviewer verified all of them AA-clean where they carry text, but per this doc's
own discipline they are **PROPOSED** values minted downstream, not observed brand — recorded here
so the design session can ratify, rename, or replace them:

| Console token | Hex | Role |
|---|---|---|
| `--field` | `#fdfbf5` | input background |
| `--fill` | `#f3ecdd` | soft utility fill (chips, copy buttons) |
| `--fill-hover` | `#ece3d1` | fill hover state |
| `--code-bg` | `#f5efe2` | code/snippet background |
| `--accent-strong` | `#a5401f` | button hover (darker coral, 6.26:1 w/ white) |
| `--accent-soft-line` | `#f2ccbc` | border on coral-soft surfaces |
| `--dot-off` | `#cdbfa8` | inactive status dot |
| `--mark-line` | `#d8ccb6` | decorative mark strokes |

**Open question for the design session — link color.** This doc's §1 carries `--pc-link #2f6f96`
(blue) as the link/secondary-interactive token, observed from the landing + inner pages. The
console pass deliberately styled its anchors coral (`#bf4a2a`, AA-clean) for a one-accent surface.
Both are defensible; neither should ratify by default. Decide: blue links everywhere (landing
convention) or coral links on app surfaces (console convention).

## 6. Proposed home

Two real options, one clear near-term pick.

**A — `parachute.computer/design/`** (recommended to start). The site already keeps its architecture
design notes there (per the site's own CLAUDE.md: "Current-era architecture lives in `design/` as
markdown design notes, indexed from `docs.njk`"). Publishing this as `design/brand-tokens.md` — or
later, a real `/design/tokens/` page that renders the actual live CSS custom properties instead of
prose — puts the reference next to the architecture notes it already keeps, versions it alongside the
file that IS the canonical brand artifact, and makes it trivially linkable when Todd or anyone else
asks "is there a design system" again. The tradeoff: it stays markdown/prose, not an importable source
of truth — notes-ui and the cloud console would still hand-copy hex values rather than `import`-ing
them, and a future token change wouldn't auto-propagate anywhere.

**B — a shared `@parachute/design-tokens` package** (CSS custom properties, maybe a Tailwind preset),
consumed via `package.json` by notes-ui, the cloud console, and future surfaces. The tradeoff: real
engineering lift up front (build/publish/version a new package, migrate at least one real consumer
before it's proven), and the cloud console isn't even a bundler-driven app the way notes-ui is — it's a
Workers-side inline `<style>` template string, so it would need its own generation step to consume a
package rather than a drop-in CSS `@import`.

Recommendation: ship **A now** — it costs nothing, matches the "not yet, we're seeding it" framing
exactly, and lives where the site's other design reference material already lives. Treat **B** as the
natural next step once a second real consumer needs to *import* values instead of eyeballing hex codes
off a markdown page — promote the same content into a real published package at that point rather than
maintaining two copies.

---

**Provenance:** extracted 2026-07-09 from `landing-preview.html` + `style.css` at their then-current
state, as Phase-4 groundwork of the onboarding-coherence run (see parachute-surface#180). The `--sky`
naming collision called out in §1 was resolved in `style.css` the same day (the status hue renamed to
`--status-active`); the OBSERVED line references predate that rename.

**Provenance (2026-07-11 update):** §1–§3's shipped values (grounds, inks, the new `--pc-sage` token,
dark theme, typography, radii, shadows) were updated to mirror `parachute-app@0.5.0`'s
`src/styles/index.css` — the "hybrid" pass (`app-w2-1-tokens`, merged app PR #12) — per Aaron's ratified
decision c ("app + site move together"). This is a documentation-only mirror: no CSS in this repo
changed. The site's own `landing-preview.html`/`style.css` still carry the pre-hybrid values recorded
throughout as OBSERVED; bringing the site's actual styles in line with the app is separate, un-started
work.
