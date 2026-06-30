---
layout: guide.njk
title: "Build a surface over your vault"
tagline: "A surface is a custom UI over your Parachute vault — a dashboard, a notes app, a single-purpose tool. Two published packages do the OAuth, the API client, and the rendering, so your code just describes the app."
description: "How to build a custom Parachute surface: a browser UI over your vault. Use @openparachute/surface-client for sign-in + a typed vault API, and @openparachute/surface-render to render notes natively. Includes a minimal end-to-end React example."
permalink: /surfaces/
templateEngineOverride: md
---

A **surface** is a custom UI over a Parachute vault — a dashboard, a notes app, a single-purpose tool. Your vault is a queryable knowledge graph behind an HTTP API + OAuth; a surface is just a web app that signs in and reads/writes it. The bundled **Notes** app is one surface; this guide is for building your own.

*(Newer vaults ship this same guide as a `Surface Starter` note inside the vault — ask your connected AI to read it. This page is the public copy, for any vault.)*

## Build a surface in your editor, not from a chat session

A surface runs **in a browser**: it needs a real OAuth round-trip (a redirect to your hub's consent screen and back), a dev server to serve the app, and a CORS origin the hub trusts. An MCP/chat session has none of that — no browser, no redirect, no dev server. So **don't try to "run" a surface from a vault chat session.** Build it in your editor (or Claude Code) against a local dev server (`vite` / `bun dev`), sign in through the browser there, and iterate. From a vault session you design the structure the surface will consume and write the code; you exercise the OAuth/render loop in the browser.

## Don't hand-roll the plumbing

Two published packages do the heavy lifting — import them instead of writing OAuth, the vault API client, or note rendering by hand:

- **`@openparachute/surface-client`** — `createVaultSurface(...)` wires up Parachute OAuth (sign-in on first connect) and a typed vault API client (query/create/update notes, tags, links) so your app code just calls methods.
- **`@openparachute/surface-render`** — `<NoteRenderer>` and friends render note content (Markdown, wikilinks, embeds) the way the rest of the ecosystem does, so your surface looks native without re-implementing the renderer.

## Minimal end-to-end (config → sign-in → query → render)

A React sketch wiring all four steps. `createVaultSurface` is the only required config (its `clientName` is the sole required option; `hubUrl` defaults to the page origin, `vaultName` to `"default"`, `scope` to `"vault:read vault:write"`). `getClient()` returns a `VaultClient` (or `null` until signed in) whose `queryNotes()` takes the same query grammar you use over MCP. Your vault's name + hub origin come from `vault-info` (or the Getting Started note in the vault).

```tsx
import { useEffect, useState } from "react";
import { createVaultSurface, type Note } from "@openparachute/surface-client";
import { NoteRenderer } from "@openparachute/surface-render";

// One surface per (hub, vault) config. clientName shows on the consent screen.
const surface = createVaultSurface({
  clientName: "My Vault Surface",
  hubUrl: "https://your-hub.example",   // omit to default to window.location.origin
  vaultName: "default",                 // this vault's name (see vault-info)
});

export function App() {
  const [notes, setNotes] = useState<Note[] | null>(null);

  useEffect(() => {
    (async () => {
      // OAuth: finish a redirect callback if we're on it, else send the browser
      // off to sign in. handleCallback() needs BOTH code + state, so guard on
      // both. (Real apps route /oauth/callback to its own component.)
      const q = new URLSearchParams(location.search);
      if (q.get("code") && q.get("state")) await surface.handleCallback();
      // getClient() builds a FRESH VaultClient on each call — fine here (one-shot
      // effect); in a real component keep it in state/ref, don't call it per render.
      const client = surface.getClient(); // VaultClient | null (null = not signed in)
      if (!client) return void surface.login();
      setNotes(await client.queryNotes({ tag: "note", limit: 20 }));
    })();
  }, []);

  if (!notes) return <p>Connecting…</p>;
  return (
    <>
      {notes.map((n) => (
        // resolve maps a [[wikilink]] target → { href, exists } (or null = inert).
        // You own this href's trust boundary — keep it a fragment (or validate the
        // target). Don't build a raw passthrough href: a vault note could carry a
        // javascript: target.
        <NoteRenderer
          key={n.id}
          note={n}
          resolve={(target) => ({ href: `#/n/${encodeURIComponent(target)}`, exists: true })}
        />
      ))}
    </>
  );
}
```

That's the whole spine. `<NoteRenderer>` also takes `linkComponent` (your router's `<Link>`) and `fetchBlob` (`(url) => Promise<Blob>`, for auth'd image/audio embeds) when you need them — both optional.

## Build order

1. **Auth + data first.** Stand up `createVaultSurface` pointed at your vault; confirm you can sign in and `queryNotes` round-trips before any UI polish.
2. **Render next.** Drop in `<NoteRenderer>` to display note content; wire wikilink/embed resolution through the package, not by hand.
3. **UX last.** Layout, navigation, and the surface's actual purpose — now that auth, data, and rendering are solid.

## Design it around your vault's structure

A good surface is shaped by the vault's tags + schemas. Query by the tags that matter; surface the indexed fields you filter on. If the vault doesn't yet have the structure a surface wants, that's a signal to design tags + schemas first — see [Scripting your vault](/scripting/) for the tags-vs-paths-vs-schemas vocabulary (and the HTTP API, if you're scripting rather than building a UI).

## Keep a record in the vault

When you build a surface, drop a note in the vault recording it — what it's for, the stack, how to run it, the queries it depends on — so the next session (yours or an AI's) can pick it up. Newer vaults seed a `Surface Starter` note for exactly this.
