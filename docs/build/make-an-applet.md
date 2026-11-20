---
title: "Make an applet and get it approved"
summary: "An applet is one record: a manifest in its fields, TSX in its body. Write it, and the person allows it on its card."
door: build
order: 4
checked: "parachute docs/WRITE-AN-APPLET.md, src/applet/manifest.ts, src/applet/modules/vault.ts, src/kit/conformance.ts; the example below passes the app's manifest check, its kit conformance check and its TSX transpile (examples/check-reading.ts)"
---

An **applet** is a small screen in the Parachute app, and it is **one record** in a vault. You make one with `create-record` and change it with `update-record`. There is no build step: the app reads the record, shows the person what it asks for, and runs it after they allow it.

## The record

| Part | What goes in it |
|---|---|
| `path` | `Applets/<Name>`. Keep applets in `Applets/`. |
| `extension` | `tsx` (or `jsx`, or `html`). |
| `tags` | `["applet"]`: that tag makes it an applet. |
| `fields.applet` | The manifest: its id, name and what it may do. |
| `fields.opens` | Optional: which kind of record opens in it when the person taps one. |
| `fields.app` | Optional: what it asks of the app: `recent`, `pins`, `open`, `links`, `save`, `attach`, `storage`. |
| `body` | The code: one TSX module whose default export is a React component. |

## A whole one

The reading tracker from [How it works](/docs/build/how-it-works/). Make the `book` type first ([Make a type](/docs/build/make-a-type/)), then:

```json
create-record {
  "path": "Applets/Reading",
  "extension": "tsx",
  "tags": ["applet"],
  "fields": {
    "applet": {
      "contract": 2, "id": "reading", "name": "Reading", "glyph": "❧", "note": "your books, by shelf",
      "access": [{ "vault": "here", "allow": [{ "path": "Books/", "verbs": ["read", "create"] }] }]
    },
    "opens": [{ "type": "book", "path": "Books/" }]
  },
  "body": "import { useEffect, useState } from \"react\";\nimport { Empty, Field, List, Loading, Page, ready, vault } from \"parachute\";\n\ntype Book = { id: string; path: string; fields?: { author?: string; status?: string } };\nconst SHELVES = [[\"reading\", \"Reading\"], [\"want\", \"Want to read\"], [\"done\", \"Read\"]];\n\nexport default function Reading() {\n  const [books, setBooks] = useState<Book[] | null>(null);\n  const load = () => vault.queryRecords({ pathPrefix: \"Books/\", tag: \"book\", includeFields: true }).then(setBooks);\n  useEffect(() => { ready().then(load); }, []);\n  const add = async (title: string) => {\n    await vault.createRecord({ path: `Books/${title}`, body: \"\" });\n    await load();\n  };\n  const title = (b: Book) => b.path.replace(\"Books/\", \"\");\n  return (\n    <Page title=\"Reading\" onRefresh={load}>\n      <Field label=\"Add a book\" placeholder=\"A title\" action=\"Add\" onAction={add} />\n      {books === null ? <Loading /> : books.length === 0 ? <Empty>No books yet. Add one above, or ask your AI.</Empty>\n        : SHELVES.map(([status, label]) => {\n            const shelf = books.filter((b) => (b.fields?.status ?? \"want\") === status);\n            return shelf.length ? <List key={status} label={label} rows={shelf.map((b) => ({ key: b.id, title: title(b), meta: b.fields?.author }))} /> : null;\n          })}\n    </Page>\n  );\n}\n"
}
```

The code in `body`, laid out:

```tsx
import { useEffect, useState } from "react";
import { Empty, Field, List, Loading, Page, ready, vault } from "parachute";

type Book = { id: string; path: string; fields?: { author?: string; status?: string } };
const SHELVES = [["reading", "Reading"], ["want", "Want to read"], ["done", "Read"]];

export default function Reading() {
  const [books, setBooks] = useState<Book[] | null>(null);
  const load = () => vault.queryRecords({ pathPrefix: "Books/", tag: "book", includeFields: true }).then(setBooks);
  useEffect(() => { ready().then(load); }, []);
  const add = async (title: string) => {
    await vault.createRecord({ path: `Books/${title}`, body: "" });
    await load();
  };
  const title = (b: Book) => b.path.replace("Books/", "");
  return (
    <Page title="Reading" onRefresh={load}>
      <Field label="Add a book" placeholder="A title" action="Add" onAction={add} />
      {books === null ? <Loading /> : books.length === 0 ? <Empty>No books yet. Add one above, or ask your AI.</Empty>
        : SHELVES.map(([status, label]) => {
            const shelf = books.filter((b) => (b.fields?.status ?? "want") === status);
            return shelf.length ? <List key={status} label={label} rows={shelf.map((b) => ({ key: b.id, title: title(b), meta: b.fields?.author }))} /> : null;
          })}
    </Page>
  );
}
```

## The manifest, in short

- `contract` is always `2`. `id` is short kebab-case, unique in the vault. `name` is one short line (40 characters at most).
- `access` says what it may do, by folder, in its own vault: `vault` is always `"here"`; `verbs` are any of `read`, `create`, `update`. Never `delete`. Ask for the least that works.
- An unknown key, a hidden character or an over-long value refuses the **whole** applet. It is not repaired. Check your keys against the [applet reference](/docs/build/reference/applet/).

## The code

- Import only `react`, `react-dom` and `parachute` (the app's kit). No npm packages, no network, no storage of your own.
- Build the screen from the kit's parts: `Page`, `List`, `Field`, `Empty`, `Loading`, `Problem`, `Button`, `Note`, `when` for dates. They follow the person's theme, so your applet looks like the rest of the app.
- Read with `vault.queryRecords`, `vault.getRecord`; write with `vault.createRecord({ path, body })` and `vault.updateRecord(id, { body, if_updated_at })`.
- **An applet writes bodies only.** It can't set fields, types or tags, and it never deletes. A record it adds in a folder it `opens` gets that type (and the type's defaults). Fields are for the person's AI to set over MCP, or keep the state in the body.
- **Opening a record on a tap** takes `"app": ["open"]` in the record's fields and `onPress: () => link.open(book)` on the row (`link` from `"parachute"`). The record opens in the applet that opens its kind (here, this one: it hears it through `onOpen`), else in the plain view. Without `open`, a row with no `onPress` is just text. Say only what your code does.
- No `<form>` submits (the frame doesn't allow them): use a button's `onClick`.

## Get it approved

You can't approve it yourself, and you shouldn't try: tell the person what you made and what it asks for.

1. The applet shows in the app's list (in **Everything**, or in a [bundle](/docs/build/make-a-bundle/) that lists its vault).
2. The first time they open it, a card says what it asks: *Read and add notes in Books/*, *Open book notes in Books/ when you tap one*. Nothing runs until they tap **Allow**.
3. If the code doesn't compile, the app says why and runs nothing. If it imports something the kit doesn't have, or throws while starting, the applet shows one line saying why.
4. Change the code or what it asks for, and the card shows again before the new version runs.

To put it on the bar or make it the home, write the [bundle](/docs/build/make-a-bundle/).

## More

The full manifest (search, screens, servers, signals, components), every kit call and part, and two more worked examples: the [applet reference](/docs/build/reference/applet/).
