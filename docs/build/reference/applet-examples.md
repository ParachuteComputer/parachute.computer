---
title: "Applet reference: worked examples"
summary: "Three whole applets: recipe cards, a home applet, and an area with its room."
door: "build"
order: 23
nav: "Reference: worked examples"
checked: "copied by scripts/docs-sync.mjs from ParachuteComputer/parachute docs/WRITE-AN-APPLET.md at 0c1f0af"
---
*Copied as it is from the app's own guide, [docs/WRITE-AN-APPLET.md](https://github.com/ParachuteComputer/parachute/blob/0c1f0af2ff5575e22a8aa34669474f8c88c8e663/docs/WRITE-AN-APPLET.md) at 0c1f0af; a bundle is still called an "app" there. Before: [the kit](/docs/build/reference/kit/).*

## A worked example

These are the exact arguments for the MCP tool `create-record` (the same body works for `POST /api/records`). A hub
before 0.9 has only `create-note` and `/api/notes`, with the older words: `content` for `body`, `metadata` for
`fields`. If the vault holds `applet` as a type (it has fields of its own), the hub asks for it in `types`
rather than `tags`: `"types": ["applet"]`. The note-named calls in the kit (`queryNotes`, `getNote`, `createNote`, `updateNote`) work too.

```json
{
  "path": "Applets/Recipe cards",
  "extension": "tsx",
  "tags": [
    "applet"
  ],
  "fields": {
    "applet": {
      "contract": 2,
      "id": "recipe-cards",
      "name": "Recipe cards",
      "glyph": "❀",
      "note": "the recipes, to read and add to",
      "access": [
        {
          "vault": "here",
          "allow": [
            {
              "path": "Recipes/",
              "verbs": [
                "read",
                "create"
              ]
            }
          ]
        }
      ]
    },
    "opens": [
      {
        "type": "recipe",
        "path": "Recipes/"
      }
    ]
  },
  "body": "import { useEffect, useRef, useState } from \"react\";\nimport { Button, Days, Empty, Field, List, Loading, Note, onOpen, Page, ready, vault, when } from \"parachute\";\n\ntype Recipe = { id: string; path: string; updatedAt: string | null; tags?: string[]; body?: string };\nconst nameOf = (r: Recipe) => r.path.replace(\"Recipes/\", \"\");\n\nconst CSS = `\n.cols { display: grid; gap: calc(var(--gap) * 2); }\n@media (min-width: 900px) { .cols { grid-template-columns: 2fr 3fr; gap: 64px; } }\n`;\n\nexport default function RecipeCards() {\n  const [recipes, setRecipes] = useState<Recipe[] | null>(null);\n  const [open, setOpen] = useState<Recipe | null>(null);\n  const shown = useRef<HTMLElement>(null);\n  const load = () => vault.queryRecords({ pathPrefix: \"Recipes/\", tag: \"recipe\", includeBody: true }).then((rows: Recipe[]) => setRecipes(rows));\n  useEffect(() => {\n    ready().then(load);\n    return onOpen((o: { note: { id: string } }) => vault.getRecord(o.note.id).then(setOpen));\n  }, []);\n  // a recipe opened (or followed from a link) comes into view: below the list on a phone\n  useEffect(() => { if (open) shown.current?.scrollIntoView({ block: \"start\" }); }, [open]);\n  const add = async (name: string) => {\n    const made: Recipe = await vault.createRecord({ path: `Recipes/${name}`, body: `# ${name}\\n\\n## Ingredients\\n\\n## Steps\\n` });\n    await load();\n    setOpen(await vault.getRecord(made.id));\n  };\n  const follow = (target: string) => { const r = recipes?.find((x) => nameOf(x) === target || x.path === target); if (r) setOpen(r); };\n  return (\n    <Page title=\"Recipe cards\" wide onRefresh={load}>\n      <style>{CSS}</style>\n      <div className=\"cols\">\n        <section>\n          <Days times={(recipes ?? []).map((r) => r.updatedAt)} label=\"changed, the last four weeks\" />\n          <Field label=\"New recipe\" placeholder=\"A name\" action=\"Add\" onAction={add} />\n          {recipes === null ? <Loading /> : recipes.length\n            ? <List label=\"Recipes\" rows={recipes.map((r) => ({ key: r.id, title: nameOf(r), aside: when.short(r.updatedAt), onPress: () => setOpen(r) }))} />\n            : <Empty>No recipes yet. Add one above, or ask your AI to.</Empty>}\n        </section>\n        {open && (\n          <section aria-label=\"Recipe\" ref={shown}>\n            <Button kind=\"quiet\" onClick={() => setOpen(null)}>Close</Button>\n            <Note body={open.body ?? \"\"} path={open.path} tags={open.tags} onLink={follow} />\n          </section>\n        )}\n      </div>\n    </Page>\n  );\n}\n"
}
```

The code in `body`, laid out:

```tsx
import { useEffect, useRef, useState } from "react";
import { Button, Days, Empty, Field, List, Loading, Note, onOpen, Page, ready, vault, when } from "parachute";

type Recipe = { id: string; path: string; updatedAt: string | null; tags?: string[]; body?: string };
const nameOf = (r: Recipe) => r.path.replace("Recipes/", "");

const CSS = `
.cols { display: grid; gap: calc(var(--gap) * 2); }
@media (min-width: 900px) { .cols { grid-template-columns: 2fr 3fr; gap: 64px; } }
`;

export default function RecipeCards() {
  const [recipes, setRecipes] = useState<Recipe[] | null>(null);
  const [open, setOpen] = useState<Recipe | null>(null);
  const shown = useRef<HTMLElement>(null);
  const load = () => vault.queryRecords({ pathPrefix: "Recipes/", tag: "recipe", includeBody: true }).then((rows: Recipe[]) => setRecipes(rows));
  useEffect(() => {
    ready().then(load);
    return onOpen((o: { note: { id: string } }) => vault.getRecord(o.note.id).then(setOpen));
  }, []);
  // a recipe opened (or followed from a link) comes into view: below the list on a phone
  useEffect(() => { if (open) shown.current?.scrollIntoView({ block: "start" }); }, [open]);
  const add = async (name: string) => {
    const made: Recipe = await vault.createRecord({ path: `Recipes/${name}`, body: `# ${name}\n\n## Ingredients\n\n## Steps\n` });
    await load();
    setOpen(await vault.getRecord(made.id));
  };
  const follow = (target: string) => { const r = recipes?.find((x) => nameOf(x) === target || x.path === target); if (r) setOpen(r); };
  return (
    <Page title="Recipe cards" wide onRefresh={load}>
      <style>{CSS}</style>
      <div className="cols">
        <section>
          <Days times={(recipes ?? []).map((r) => r.updatedAt)} label="changed, the last four weeks" />
          <Field label="New recipe" placeholder="A name" action="Add" onAction={add} />
          {recipes === null ? <Loading /> : recipes.length
            ? <List label="Recipes" rows={recipes.map((r) => ({ key: r.id, title: nameOf(r), aside: when.short(r.updatedAt), onPress: () => setOpen(r) }))} />
            : <Empty>No recipes yet. Add one above, or ask your AI to.</Empty>}
        </section>
        {open && (
          <section aria-label="Recipe" ref={shown}>
            <Button kind="quiet" onClick={() => setOpen(null)}>Close</Button>
            <Note body={open.body ?? ""} path={open.path} tags={open.tags} onLink={follow} />
          </section>
        )}
      </div>
    </Page>
  );
}
```

## A home applet

The applet the app opens on start, which the person or their agent chooses ([NAVIGATION.md](https://github.com/ParachuteComputer/parachute/blob/0c1f0af2ff5575e22a8aa34669474f8c88c8e663/docs/NAVIGATION.md)). Any
applet can be one; this one shows what changed lately across all the person's vaults, a day at a time, and their
pinned applets. It reads no folder of its own vault, so it has no `access`; it asks the app for the three things in
`fields.app`, and its card says so. Create it with `create-record`:

```json
{
  "path": "Applets/Home",
  "extension": "tsx",
  "tags": [
    "applet"
  ],
  "fields": {
    "applet": {
      "contract": 2,
      "id": "home",
      "name": "Home",
      "glyph": "◠",
      "note": "what changed lately, and your pins"
    },
    "app": [
      "recent",
      "pins",
      "open"
    ]
  },
  "body": "import { useEffect, useState } from \"react\";\nimport { app, Days, Empty, List, Loading, Page, ready, when } from \"parachute\";\n\ntype Recent = { vaultName: string; title: string; updatedAt: string | null; href: string };\ntype Place = { name: string; glyph: string; href: string; home: boolean };\n\nconst CSS = `\n.head { display: grid; gap: 12px 32px; align-items: end; padding-bottom: var(--gap); border-bottom: 1px solid var(--text); }\n@media (min-width: 900px) { .head { grid-template-columns: 1fr minmax(240px, 380px); } .cols { grid-template-columns: 3fr 2fr; gap: 64px; } }\n.sum { margin: 0; font: var(--fs-lead)/1.5 var(--serif); }\n.cols { display: grid; gap: calc(var(--gap) * 1.5); padding-top: var(--gap); }\n.river { border-left: 2px solid var(--text); padding-left: 20px; }\n`;\n\nexport default function Home() {\n  const [recent, setRecent] = useState<Recent[] | null>(null);\n  const [pins, setPins] = useState<Place[]>([]);\n  const load = () => Promise.all([app.recent({ limit: 40 }), app.pins()])\n    .then(([r, p]: [Recent[], Place[]]) => { setRecent(r); setPins(p.filter((x) => !x.home)); }, () => setRecent([]));\n  useEffect(() => { ready().then(load); }, []);\n  const days: { label: string; notes: Recent[] }[] = [];\n  for (const n of (recent ?? []).slice(0, 12)) {\n    const label = when.day(n.updatedAt) || \"Earlier\";\n    if (days.at(-1)?.label !== label) days.push({ label, notes: [] });\n    days.at(-1)!.notes.push(n);\n  }\n  const vaults = new Set((recent ?? []).map((n) => n.vaultName)).size;\n  return (\n    <Page kicker={when.date(new Date())} title=\"Lately\" wide onRefresh={load}>\n      <style>{CSS}</style>\n      <header className=\"head\">\n        {recent === null ? <Loading /> : <p className=\"sum\">{`${recent.length} notes lately, in ${vaults} ${vaults === 1 ? \"vault\" : \"vaults\"}.`}</p>}\n        <Days times={(recent ?? []).map((n) => n.updatedAt)} days={14} label=\"the last two weeks\" />\n      </header>\n      <div className=\"cols\">\n        <section className=\"river\" aria-label=\"Lately\">\n          {days.map((d) => <List key={d.label} label={d.label} rows={d.notes.map((n) => ({ key: n.href, title: n.title, meta: n.vaultName, aside: when.time(n.updatedAt), onPress: () => app.open(n.href) }))} />)}\n          {recent !== null && !recent.length && <Empty>Nothing written yet.</Empty>}\n        </section>\n        {pins.length > 0 && <List label=\"Pinned\" rows={pins.map((p) => ({ key: p.href, title: p.name, glyph: p.glyph, onPress: () => app.open(p.href) }))} />}\n      </div>\n    </Page>\n  );\n}\n"
}
```

Then make it the home: write the settings note in the home vault (`Parachute/Settings`, tagged `parachute-settings`):

```json
{ "fields": { "parachute": { "start": { "vault": "<the vault's name>", "applet": "Applets/Home" } } } }
```

The next time the app starts, it opens on Home and shows its card; once the person taps Allow, it opens there by itself.
They can also long-press it in the list and tap **Open on start**, and pin it first on the bar.

Two home applets ship with the app, in `applets/`: `home` (Parachute Simplified's starter: a line into `Inbox/`, the
newest notes, the pins) and `today` (for a person with rooms and a journal: what wants you in your rooms, the latest
from one key, today's journal and a line for it; `--set relay=… --set uni=<hex key>`). `app.open` also takes an applet
at a room, `/v/<vault>/a/<applet>?room=<id>[&event=<id>]`: the applet hears it as its launch (`onLaunch`), as from a
notification's tap. The installer fills a quoted `"{{name}}"` in an applet's code from `--set` (`applets/record.ts`), so
such a value is part of the code the person approves.

The code in `body`, laid out:

```tsx
import { useEffect, useState } from "react";
import { app, Days, Empty, List, Loading, Page, ready, when } from "parachute";

type Recent = { vaultName: string; title: string; updatedAt: string | null; href: string };
type Place = { name: string; glyph: string; href: string; home: boolean };

const CSS = `
.head { display: grid; gap: 12px 32px; align-items: end; padding-bottom: var(--gap); border-bottom: 1px solid var(--text); }
@media (min-width: 900px) { .head { grid-template-columns: 1fr minmax(240px, 380px); } .cols { grid-template-columns: 3fr 2fr; gap: 64px; } }
.sum { margin: 0; font: var(--fs-lead)/1.5 var(--serif); }
.cols { display: grid; gap: calc(var(--gap) * 1.5); padding-top: var(--gap); }
.river { border-left: 2px solid var(--text); padding-left: 20px; }
`;

export default function Home() {
  const [recent, setRecent] = useState<Recent[] | null>(null);
  const [pins, setPins] = useState<Place[]>([]);
  const load = () => Promise.all([app.recent({ limit: 40 }), app.pins()])
    .then(([r, p]: [Recent[], Place[]]) => { setRecent(r); setPins(p.filter((x) => !x.home)); }, () => setRecent([]));
  useEffect(() => { ready().then(load); }, []);
  const days: { label: string; notes: Recent[] }[] = [];
  for (const n of (recent ?? []).slice(0, 12)) {
    const label = when.day(n.updatedAt) || "Earlier";
    if (days.at(-1)?.label !== label) days.push({ label, notes: [] });
    days.at(-1)!.notes.push(n);
  }
  const vaults = new Set((recent ?? []).map((n) => n.vaultName)).size;
  return (
    <Page kicker={when.date(new Date())} title="Lately" wide onRefresh={load}>
      <style>{CSS}</style>
      <header className="head">
        {recent === null ? <Loading /> : <p className="sum">{`${recent.length} notes lately, in ${vaults} ${vaults === 1 ? "vault" : "vaults"}.`}</p>}
        <Days times={(recent ?? []).map((n) => n.updatedAt)} days={14} label="the last two weeks" />
      </header>
      <div className="cols">
        <section className="river" aria-label="Lately">
          {days.map((d) => <List key={d.label} label={d.label} rows={d.notes.map((n) => ({ key: n.href, title: n.title, meta: n.vaultName, aside: when.time(n.updatedAt), onPress: () => app.open(n.href) }))} />)}
          {recent !== null && !recent.length && <Empty>Nothing written yet.</Empty>}
        </section>
        {pins.length > 0 && <List label="Pinned" rows={pins.map((p) => ({ key: p.href, title: p.name, glyph: p.glyph, onPress: () => app.open(p.href) }))} />}
      </div>
    </Page>
  );
}
```

## An applet for an area

A page for one area of your life (the garden, a client, a class) where you talk with Uni about it beside its notes:
the area's room on the relay, and its folder in the vault. Two columns on a wide screen, the room kept in view; one
column on a phone (the area's note, the room, then the other notes). `applets/area.tsx` and `applets/area.json` in this
repository are the worked example; `e2e/area.spec.ts` runs it against a real relay.

### What it declares

The record for the area Garden. `<…>` are the values for this person: the relay, Garden's room (its NIP-29 id) and
Uni's key (hex). The body is `applets/area.tsx`, unchanged for every area.

```json
{
  "path": "Applets/Garden",
  "extension": "tsx",
  "tags": ["applet"],
  "fields": {
    "applet": {
      "contract": 2, "id": "garden", "name": "Garden", "glyph": "❦",
      "note": "the Garden room, to talk with Uni there, beside the area's notes",
      "access": [{ "vault": "here", "allow": [{ "path": "Areas/Garden/", "verbs": ["read"] }] }],
      "reach": ["voice"]
    },
    "app": ["links", "save", "attach", "storage"],
    "services": [{
      "id": "rooms", "kind": "nostr-relay", "url": "<wss://relay.example>",
      "publish": [9, 7, 5, 40003, 20002], "media": true,
      "rooms": [{ "id": "<Garden's room>", "name": "Garden" }],
      "approvals": { "from": ["<Uni's key>"] },
      "notify": { "mentions": true, "from": ["<Uni's key>"] }
    }]
  }
}
```

- **One folder, to read.** The notes are `Areas/Garden/`; the area's own note, shown first, is the one in it named for
  the area (`Areas/Garden/Garden`). A rule is a folder, so a note at `Areas/Garden` beside the folder isn't in it.
- **One room.** `rooms` keeps every post, read and reaction to Garden's room: a filter without its `#h` is refused, and
  so is an event for another room. Media on the relay's server and private notes aren't limited to it, and the card
  says so.
- **Uni.** `approvals` lets Uni's cards in that room be answered here (high risk: the card says so); `notify` tells you
  of a mention, and of every message from Uni, while Parachute is closed. The room reads which key is Uni's from these.
- **What the room uses.** `links`, `save`, `attach`, `storage` (drafts) and `reach: [voice]` are what the Room
  component asks of the app. Leave one out and only that one thing stops working.

### The room is a component

```tsx
import Room from "component:room";
// …
<Room service="rooms" room={roomId} name="Garden" />
```

`Components/Room` (`applets/room.json`, tagged `component`, id `room`) must be in the same vault; it runs inside the
applet's own frame, with its services and nothing more, so the scope above holds for it. The Rooms applet imports the
same component, so a room looks and works the same in both. Its props: `service` (the relay service's id), `room`,
`name` (shown until the relay's own name comes), `at` (a message to open at, marked), and, for a list like Rooms,
`readAt`, `onRead` and `onBack`. `applets/area.tsx` reads the room and the folder from `ready()` (`services`, `access`):
the page keeps nothing of its own that could drift from its card.

### What the card says

The card's face says it short, by what it means to a person (one line per server, the approval key on its own line,
the small asks on one "Also" line: [design/PERMISSIONS.md](https://github.com/ParachuteComputer/parachute/blob/0c1f0af2ff5575e22a8aa34669474f8c88c8e663/docs/design/PERMISSIONS.md)). Under **Show details**, each line
in the app's own words, from the declaration:

> Read notes outside its own folder, in Areas/Garden/ ·
> With your everyday key: post as you only in «Garden» (3f2a1b…), named by the applet there: messages, reactions, edits
> of your messages and typing · It reads only those rooms there; files and private notes there aren't limited to them ·
> **High risk.** With your approval key: answer approval cards and secret requests there from Uni … ·
> Tell you about messages only in «Garden» (3f2a1b…), named by the applet there that name you, and every message from
> Uni, even when Parachute is closed · Includes «Room», a component from this vault: its code runs inside this applet

with the lines for links, files, drafts and the microphone. «Garden» is the applet's word for the room; the id beside
it is what is enforced.

### Another area

Each area is its own applet record, with its own card: the same code, other values. With the installer:

```sh
node scripts/install-applets.ts --hub https://hub.example --vault home --token-file ~/token --applet area \
  --set relay=wss://relay.example --set uni=<Uni's key, hex> \
  --set area=Kitchen --set area_id=kitchen --set area_room=<the Kitchen room's id> [--apply]
```

It puts `Components/Room` in first if the vault doesn't have it, then `Applets/Kitchen`. When `area.tsx` or `room.tsx`
changes, run it again once per area; each area's card asks again. By an agent, it is two `create-record` calls: the component once per vault
(`applets/room.json`'s fields, `applets/room.tsx` as the body), then the applet (the record above with the Kitchen's
values, `applets/area.tsx` as the body). The room must exist on the relay with the person in it; the folder may be
empty, and the page says what to write first.

## What the person sees

1. The applet shows in the vault, beside its name and glyph.
2. The first time they open it, a card says what it asks for ("Read and add notes in Recipes/", "Open recipe notes in
   Recipes/ when you tap one"). Nothing runs until they tap **Allow**.
3. The app turns the TSX into JavaScript the first time that version is opened (before the card), and keeps it.
4. When you change the code or what it asks for, the card shows again before the new version runs.

If the code doesn't compile, the app says so, with the reason, and runs nothing. If it imports something the app doesn't
provide, or throws while starting, the applet shows one line saying why.

To change the screens around the notes instead (the list, a vault, a note), see
[CHANGE-YOUR-FRAME.md](https://github.com/ParachuteComputer/parachute/blob/0c1f0af2ff5575e22a8aa34669474f8c88c8e663/docs/CHANGE-YOUR-FRAME.md).
