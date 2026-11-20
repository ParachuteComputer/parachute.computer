---
title: "Change the look"
summary: "One theme record sets the colours, fonts and density of the whole app and every applet."
door: build
order: 6
checked: "parachute docs/THEME.md, docs/CHANGE-YOUR-FRAME.md, docs/WRITE-AN-APPLET.md (theme.get, CSS variables)"
---

The whole app (its own screens, the list, every applet) takes its look from one record: `Parachute/Theme` in the home vault, tagged `parachute-theme`, with the theme in `fields.theme`. With none, the built-in theme: paper, ink, a moss accent, a book serif and a quiet sans.

## The record

```json
create-record {
  "path": "Parachute/Theme",
  "tags": ["parachute-theme"],
  "fields": { "theme": {
    "colors": { "accent": "#2f5470" },
    "density": "roomy",
    "scheme": "system"
  } }
}
```

| Key | What it sets |
|---|---|
| `colors` | The light palette: `bg` (the page), `surface` (raised parts), `text`, `muted`, `line`, `accent`, `danger`. |
| `dark` | The same seven, for dark mode. |
| `fonts` | `serif`, `sans`, `mono`: lists of font names the device has, ending in `serif`, `sans-serif` or `monospace`. The app loads no fonts. |
| `density` | `compact`, `regular` or `roomy`. |
| `scheme` | `system`, `light` or `dark`. |

Every key is optional. Anything left out, or written in a form the app doesn't read, stays the built-in value. A colour is hex, or `rgb()`, `hsl()`, `oklch()`, `oklab()` with plain numbers. Nothing else is read, so a theme can't load anything from the network.

If the record already exists, change it with `update-record` (`fields` merges). In the app: Settings → **Look**.

## In an applet

Use the theme's CSS variables, never your own colours or fonts: `--bg`, `--surface`, `--text`, `--muted`, `--line`, `--accent`, `--danger`, `--serif`, `--sans`, `--mono`, `--pad`, `--gap`, `--radius`, and the type scale `--fs-title` … `--fs-label`. The kit's parts already do.

## The screens around the notes

The list, a vault and a note are drawn by the **frame**, which is itself code the person can own: a record tagged `parachute-frame` in the home vault runs in place of the built-in one, after they allow it, as an applet is allowed. Settings → Frame → **Make this mine** copies the built-in frame into the vault to start from. The bar stays the app's.
