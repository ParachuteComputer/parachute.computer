---
title: "Make it feel good"
summary: "Build from the kit's parts and the applet feels like the rest of the app: calm, quick, nothing jumping. The short rules, for you and your AI."
door: build
order: 4.5
checked: "parachute docs/DESIGN-RULES.md, docs/THEME.md (motion), docs/WRITE-AN-APPLET.md (Drawer, toast), src/kit/conformance.ts (motion, layout)"
---

An applet built from the kit's parts (`Page`, `List`, `Field`, `Button`, `Drawer`, `toast` and the rest) already feels
like the rest of Parachute. A page and what it reads arrive once, quickly; a button gives under a press; a drawer rises
from the foot of the screen and follows the finger; a toast rises and can be swiped away. Nothing jumps as content
loads, and with the device set to reduce motion, nothing moves at all. You write none of that.

The full list is [the design rules](https://github.com/ParachuteComputer/parachute/blob/next/docs/DESIGN-RULES.md):
short rules an AI can check its work against. Give it that page with the applet guide. The short version:

- **Use the parts.** Reach for `Loading`, `Empty` and `Problem` for a screen's states, `toast` after an action,
  `Drawer` for a choice or a short form over the page.
- **Colours, type and space from the theme:** `var(--accent)`, `var(--fs-body)`, `var(--gap)` and the rest
  ([Change the look](/docs/build/change-the-look/)). Never a colour or a size of your own.
- **Most things don't move.** What is used all day (a tab, a row, typing) changes at once. Only what arrives moves.
- **If you move something,** move only `transform` and `opacity`, on the theme's curves and times: `--ease-out`,
  `--ease-in-out`, `--ease-drawer`; `--t-press` (160 ms), `--t-state` (200 ms), `--t-sheet` (300 ms), `--t-step`
  (40 ms). They are 0 when the person asks for stillness, so your applet is still with the rest.
- **Keep the page still under the reader:** an image gets `width` and `height`; what is read lands below what is
  there.
- **Every state has words,** and plain ones: "Saved", "Not sent: offline", "No books yet. Add one above."

A person who wants nothing to move sets **Settings → Look → Motion → Still** (or `"motion": "still"` in their theme
record), and every applet built this way follows.
