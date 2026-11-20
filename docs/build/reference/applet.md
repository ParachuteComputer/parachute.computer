---
title: "Applet reference: the record"
summary: "The applet record in full: the manifest, what it opens, its servers, its signals."
door: "build"
order: 21
nav: "Reference: the applet record"
checked: "copied by scripts/docs-sync.mjs from ParachuteComputer/parachute docs/WRITE-AN-APPLET.md at 0c1f0af"
---
*Copied as it is from the app's own guide, [docs/WRITE-AN-APPLET.md](https://github.com/ParachuteComputer/parachute/blob/0c1f0af2ff5575e22a8aa34669474f8c88c8e663/docs/WRITE-AN-APPLET.md) at 0c1f0af; a bundle is still called an "app" there. The short version: [Make an applet](/docs/build/make-an-applet/). Next: [the kit](/docs/build/reference/kit/).*

For a chat AI with the Parachute MCP (Claude, ChatGPT or any other), and for people. An applet is **one record** in a
Parachute vault. You make one by creating that record, and change it by updating it. There is no build step on your side:
the Parachute app reads the record, shows the person what it asks for, and runs it after they allow it.

## The record

| Part | What goes in it |
|---|---|
| `path` | Where it lives, e.g. `Applets/Recipe cards`. Keep applets in `Applets/`. |
| `extension` | `tsx` (TypeScript with JSX), `jsx`, or `html`. It says what the content is. |
| `tags` | `["applet"]`. That tag is what makes it an applet. |
| `fields.applet` | The manifest: what it is and what it may do (below). |
| `fields.opens` | Optional: which kind of note opens in it when the person taps one. |
| `fields.app` | Optional: what it asks of the app beyond its vault: any of `recent`, `pins`, `open`, `links`, `save`, `attach`, `storage` (below). Anything else is ignored, and the applet then asks nothing of the app. |
| `fields.services` | Optional: the servers it talks to, through the app (below). |
| `body` | The code: one self-contained file. |

### The manifest (`fields.applet`)

```yaml
contract: 2                  # always 2
id: recipe-cards             # short kebab-case: a-z, 0-9, -  (unique in the vault; "vault" is taken)
name: Recipe cards           # one short line, 40 characters at most
glyph: "❀"                   # optional: one character, shown beside the name
note: the recipes as cards   # optional: one short line, 120 characters at most
access:                      # what it may do, by folder, in the vault the note lives in
  - vault: here              # always "here": an applet reaches only its own vault
    allow:
      - path: Recipes/       # a folder, ending in /
        verbs: [read, create, update]   # any of read, create, update. Never delete.
search:                      # optional: what it offers to search
  - { what: recipes, vault: here, path: Recipes/ }
screens:                     # optional: its screens; the first is the one that opens
  - { id: home, name: Recipe cards }
reach: [voice]               # optional: the microphone, through the app's own recorder (voice.record below)
```

What the person's hub is asked for follows from `access` ([design/SCOPES.md](https://github.com/ParachuteComputer/parachute/blob/0c1f0af2ff5575e22a8aa34669474f8c88c8e663/docs/design/SCOPES.md)): an applet whose
verbs are all `read` needs the app to read its vault; any `create` or `update` needs it to change notes there. When the
person allows the applet and the app doesn't hold that yet, the hub asks them for that one vault, after the card. Ask
for the least that works: an applet that only reads never brings that second page. The hub can't narrow to a folder;
the folders here are the app's rule, enforced on every call.

Rules the app holds to. An unknown key, a hidden character or an over-long value refuses the whole applet: it is not
repaired. A rule can't reach `.parachute/`. No applet can change a code note (HTML, TSX, JSX) or a note tagged
`applet`, `component` or `parachute-pointer`, whatever its rules say. `reach` takes only `voice`: a room in it
(`{room: …}`) is refused, since rooms are named on a relay service. An applet in someone else's vault gets no
microphone.

### What it opens (`fields.opens`)

```yaml
- type: recipe     # a tag: notes with it (or a tag beneath it, recipe/…)…
  path: Recipes/   # …in this folder open in this applet when the person taps one. Notes it adds here get the tag.
  screen: home     # optional: one of its screens
```

The folder must be one it may read, and not `Applets/` or `.parachute/`. `applet`, `view`, `capture`, `component` and
anything starting with `parachute` can't be claimed.

### Its servers (`fields.services`)

An applet has no network of its own. It can still talk to a server (rooms on a Nostr relay, mail behind a gateway) by
naming it here: the app talks to it for the applet, and signs as the person where the server asks for it. The applet
never holds the person's key or a password. The card says each server, what the app will sign there, and that what the
applet reads could reach it; a new server, a changed address or a new kind asks again.

```yaml
services:
  - id: rooms                       # what the code calls it
    kind: nostr-relay
    url: wss://relay.example
    publish: [9, 7, 40003, 5, 20002]   # messages, reactions, edits, deletions of your own, typing: nothing else
    media: true                     # files on the relay's media server
    private: [{ kind: 30078, d: "read-state:", t: read-state }]   # notes sealed to your key, under that prefix
  - id: mail
    kind: http
    url: https://mail.example/mail/ # an https origin and a path prefix; requests stay under it
    auth: nip98                     # none | nip98 (each request signed as you) | token (one you give the app)
```

A Parachute hub is never a server here (the app refuses it), and an applet in someone else's vault reaches none. The
rules, and why, are in [design/SERVICES.md](https://github.com/ParachuteComputer/parachute/blob/0c1f0af2ff5575e22a8aa34669474f8c88c8e663/docs/design/SERVICES.md). Applets that do it: `applets/rooms.tsx`,
`applets/area.tsx` and `applets/mail.tsx` in this repository.

A relay service may also name (all optional, each a line on the card; [design/KEYRING.md](https://github.com/ParachuteComputer/parachute/blob/0c1f0af2ff5575e22a8aa34669474f8c88c8e663/docs/design/KEYRING.md)):

```yaml
    rooms: [{ id: <room id>, name: Garden }]   # only these rooms: posts, reads and reactions stay in them
    approvals: { from: [<Uni's key, hex>] }    # high risk: answer Uni's cards and secret requests, with your approval key
    notify: { mentions: true, from: [<hex>], gateway: https://push.example/ }  # pushed through that gateway while Parachute is closed
```

`approvals` counts only for keys the person trusts on this device (Settings → Approvals). The applet hands a card's
signed message to the app (`services.card`), draws it, and on a tap answers (`services.answer`); the app checks the
card, asks for the device unlock for powerful ones, seals the answer and sends it. A secret is typed on the app's own
sheet (`services.secret`): the applet never sees it. An http service may name `approve: { field: op, ops: [...] }`:
those requests are signed with the approval key. It may name `join: { field: op, ops: [...] }` for asking to join a
private network: those requests are signed as the person only after a tap and this device's join level (the passcode
and the unlock, by default; docs/design/KEYRING.md "Joining a network"). What an answer or a join asks (a tap, the
unlock, the passcode) is the person's choice in Settings → Security, never the applet's; when it is the passcode, the
app asks it on its own sheet.
