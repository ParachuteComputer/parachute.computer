---
title: "Applet reference: the kit"
summary: "Every call and part an applet imports from \"parachute\", saved state, and links."
door: "build"
order: 22
nav: "Reference: the kit"
checked: "copied by scripts/docs-sync.mjs from ParachuteComputer/parachute docs/WRITE-AN-APPLET.md at 0c1f0af"
---
*Copied as it is from the app's own guide, [docs/WRITE-AN-APPLET.md](https://github.com/ParachuteComputer/parachute/blob/0c1f0af2ff5575e22a8aa34669474f8c88c8e663/docs/WRITE-AN-APPLET.md) at 0c1f0af; a bundle is still called an "app" there. Before: [the record](/docs/build/reference/applet/). Next: [worked examples](/docs/build/reference/applet-examples/).*

## The code

For `tsx` or `jsx`: one module. Its **default export is a React component** (a function, or what `memo` returns), and
the app renders it. It may `await` at its top level. It may import only these:

| Import | What it is |
|---|---|
| `react` | React 19 (`useState`, `useEffect`, …) |
| `react-dom`, `react-dom/client` | ReactDOM, if you need it (the app already renders your default export) |
| `parachute` | The app's kit, below |

Nothing else: no npm packages, no other files, no network, no storage. Put CSS in a `<style>` element inside your
component, or in `style={…}`. Write plain, working code: types are stripped, not checked.

For `html`: a page, run as written, with the same kit on `window.parachute`.

### Something for the person (`fields.signals`)

What counts as something for the person: the count is the badge on the bar while the applet is closed, and on a phone
the same count is the notification while Parachute is closed ([design/APP-RECORD.md](https://github.com/ParachuteComputer/parachute/blob/0c1f0af2ff5575e22a8aa34669474f8c88c8e663/docs/design/APP-RECORD.md), "Signals").
Up to four, each a line on the card:

```yaml
signals:
  - id: for-you                     # lower-case words joined by -
    name: mentions and messages from Uni   # the notification's words: "Rooms · 3 new"
    from: { service: rooms }        # a relay service with notify: its gateway counts what it would tell you about
  - id: unread
    name: unread mail
    from: { service: mail, feed: unread }   # an http service's number: the applet sets it while it runs
    via: https://push.example/      # the gateway the count goes to, for your other devices and your closed phone
  - id: new
    name: new ideas from others
    from: { vault: here, path: Ideas/, others: true }   # notes in a folder it may read, made since you last opened it
    via: https://push.example/
```

Nothing of the applet runs to count. Notes in its vault are counted by the app, live, from the vault (`others`: only
notes someone else made); a relay's by its push gateway; a feed by the applet itself, with `signal(id, count)` while
it runs (its own number wins: Mail knows what is unread). Opening the applet makes its counts 0. A gateway gets your
public key, the applet as a number it can't read back, the signal's id and the count: never what was counted. An
applet in someone else's vault may count only its notes, and the count goes nowhere.

### Write it on the kit

The kit is the standard library: for each thing an applet needs, there is one part, and every applet uses it, so they
all look and behave as one app and follow the person's theme. Reach for the part before writing your own:

| To | Use |
|---|---|
| lay out the screen: its width, title, a way back, pull to refresh | `Page` |
| say a date or a time | `when` (`when.short(t)`, `when.day`, `when.time`, …): never `Intl`, `toLocale…` or `getHours` |
| show rows of things, short or long | `List` (a long one draws only what is on screen; `more` for the next page) |
| say it is reading, there is nothing yet, or it failed | `Loading`, `Empty`, `Problem` (with Try again) |
| say what an action did ("Saved", "Not sent: …") | `toast` |
| take words: a line, a box, a chat's composer | `Field`, `Write` |
| search | `Search` |
| switch between places in one screen | `Tabs` |
| a button | `Button` (`kind="primary"` for the one main action) |
| record a voice note | `Record`, then `voiceNote` and `useTranscripts` for one the hub transcribes |
| link to a note, or open one | `Link`, `Linked`, `Note`, `link.open` |
| keep a draft, or where it was | `useSaved` |
| colour and size | the theme's CSS variables and the type scale (`--fs-title` … `--fs-label`, [THEME.md](https://github.com/ParachuteComputer/parachute/blob/0c1f0af2ff5575e22a8aa34669474f8c88c8e663/docs/THEME.md)) |

Your own CSS is for layout (columns, a card of your own) on those variables. The applets this repo ships are held to
this: `src/kit/conformance.ts` fails one that formats a date itself, draws its own list, input, button, error or status
line, or picks its own colour, font or text size, and says which part to use (`npm test`). Write yours the same way:
an agent can read that file for the exact rules (they run in this repo's tests, not in the app: an applet in a vault is
asked to follow them, not checked). A shipped applet with a real reason to keep something of its own names the reason
there (`EXCEPTIONS` in `conformance.test.ts`). The guide's own examples below are checked too.

### The kit's calls (`import { … } from "parachute"`)

| Call | What it does |
|---|---|
| `ready()` | Resolves when the app has started it: `{ applet: { id, name }, access, services, theme, open?, launch? }`. `access` is the folders it was allowed (`[{ path, verbs }]`) and `services` its servers as its card allowed them (a relay's `rooms`, `approvals`, `notify`): read your room, or which key is Uni's, from here rather than keeping a copy in the code. |
| `launch()`, `onLaunch(cb)` | What the app opened it for from a notification's tap: `{ room, event? }` (or null), and each later one. |
| `shown()`, `onShown(cb)` | Whether it is on screen, and each change. The app keeps an applet running while the person is elsewhere, so going back to it is instant; hidden, it gets no tap, and anything only a person looking should do (marking a message read) waits for `true`. |
| `onOpen(cb)` | `cb({ note: { id, path }, screen })` when the person opened a note in it (now, and each time after). |
| `vault.queryRecords({ pathPrefix, tag, search, limit, includeBody, includeFields })` | Records in folders it may read: `{ id, path, updatedAt }`, and with `tag`, `includeBody` or `includeFields` also `tags` and `fields` (and with `includeBody` the `body`). |
| `vault.getRecord(idOrPath)` | One record it may read, with its body. |
| `vault.createRecord({ path, body })` | A new record, in a folder it may `create` in: `{ id, path, tags, fields, updatedAt }` (`getRecord` for its body). |
| `vault.updateRecord(id, { body, if_updated_at })` | A new body for a record it may `update`. |
| `app.recent({ limit })` | With `recent`: the newest notes across every vault on this device, newest first: `{ vaultName, title, updatedAt, href }`. Titles only: no folder, never content. `limit` up to 40. |
| `app.pins()` | With `pins`: what is on the person's bar: `{ name, glyph, href, home }`. |
| `app.open(href)` | With `open`: take the person to a note or an applet (an `href` from the two calls above; an applet at a room with `?room=<id>[&event=<id>]`, which it hears as its launch), while they tap inside the applet. Resolves to whether it went. |
| `app.links(links, from)`, `app.follow(link, { from, choose })`, `app.address(noteId)` | With `open`: the calls under the kit's note links. Use `Link`, `Linked`, `Note` and `link` (see [Links](#links)) rather than these. |
| `app.openLink(url)` | With `links`: an `http`, `https` or `mailto` address in the person's browser, while they tap, at most one a second. Resolves to whether it went. |
| `app.save(name, bytes, type)` | With `save`: a file (an `ArrayBuffer`, 25 MB at most) into the person's Downloads, while they tap. The name is made bare (no folder, no leading dot, 100 characters at most) and the app picks a free one. Resolves `{ saved: name }`. |
| `app.pick({ accept, multiple })` | With `attach`: the app's own picker, while they tap (`accept`: like `"image/*,.pdf"`). Resolves the files chosen, `[{ name, type, bytes }]` (25 MB each, 10 at most), or `[]`. |
| `voice.record({ max_s })` | With `reach: [voice]`: the app's own recorder sheet over the applet, while they tap (Record, Stop, Send, Cancel; 10 minutes unless `max_s` is less). Resolves `{ bytes, type: "audio/webm", duration }` on Send, `null` on Cancel. The applet never touches the microphone. |
| `saved.get(key)`, `saved.set(key, value)`, `saved.all()`, `saved.flush()` | What the app keeps for this applet on this device as it goes ([Saved state](#saved-state)): handed back with `ready`, so `get` answers at once after it; `set` reaches the app within 250 ms. |
| `storage.get(key)`, `storage.set(key, value)`, `storage.keys()` | With `storage`: JSON kept by the app on this device for this applet (drafts; what it last showed, so its next open paints at once), 256 KB in all with what it saved, keys up to 100 characters. A value may be any size within the 256 KB: the kit sends it as JSON text in bytes, past the 8 KB a call's parameters may be. `set(key, null)` removes it. Never synced. |
| `vault.attach(id, bytes, type, { transcribe })` | A file (25 MB at most) onto a record it may `update`, through the hub. `transcribe: true` asks the hub to transcribe audio: write the record with `_Transcript pending._` and the hub puts the words in its place. Resolves `{ id, path, type, transcribe }`. |
| `props()`, `onProps(cb)` | In a component a page embeds: the plain data the page hands it (also its React props), and each change after. Empty in an applet. |
| `services.fetch(id, path, { method, headers, body, as })` | With `services`: a request to that server, under its url. `as`: `text`, `json` or `bytes`. Resolves `{ status, headers, body }`. |
| `services.relay(id)` | With `services`: the relay. `.subscribe(filters, onEvents, onEose?)` (returns a function that stops it; one room per subscription on a Buzz relay), `.query(filters)`, `.publish({ kind, content, tags })` (resolves `{ ok, id, message, event }`), `.loadPrivate(prefix)`, `.savePrivate(d, text)`, `.onStatus(cb)`. |
| `services.upload(id, bytes, type)`, `services.media(id, sha256, ext)` | With `media`: a file up (the server's descriptor) or down (`{ bytes, type }`, for a `blob:` address an `<img>`, `<audio>` or `<video>` plays). |
| `services.me()` | Who the app signs as: `{ pubkey }`. |
| `services.card(id, event)` | With `approvals`: Uni's card in that signed message, as the app checked it: `{ kind, refused, rows: [{ rid, credential, action, class, scope, ttl_s, uses, expires, always_unlock, answer, … }] }`. Never a key. |
| `services.answer(id, event, "approve" \| "deny", rids)` | On a tap: the app asks for the unlock when it must, seals the answer with the approval key and sends it. Resolves `{ view, sent, failed? }`. A tap answers once. |
| `services.secret(id, event)`, `services.forgetSecret(id, event)` | On a tap: the app's own sheet takes the secret (`{ sent }`); or asks the requester to forget it. |
| `signal(id, count)` | Its own number for a signal its record declares (0 to 9999): the bar's count, and through the signal's gateway, the person's other devices'. Fails with `out_of_scope` for a signal it doesn't declare. |
| `theme.get()`, `theme.now()`, `theme.on(cb)` | The app's look, which the person can change ([THEME.md](https://github.com/ParachuteComputer/parachute/blob/0c1f0af2ff5575e22a8aa34669474f8c88c8e663/docs/THEME.md)): `get` asks for it, `now` gives the last one sent (or null), `on` calls back now and at each change and returns a function that stops it. Beside the values below, it says `scheme` (`light` or `dark`) and `density`. Every value is also a CSS variable: `--bg`, `--surface`, `--text`, `--muted`, `--line`, `--accent`, `--danger`, `--serif`, `--sans`, `--mono`, `--pad`, `--gap`, `--radius`, `--size`, `--leading`. |

A call outside what it was allowed fails with `out_of_scope` or `not_granted`. It never reaches anything else.

### Components, embeds and imports

A **component** is a record like an applet, tagged `component`, that a page shows rather than one that has a screen.
Its own frame, its own card, its own vault; or, from a vault you trust, imported into your code with
`import Events from "component:events"`. All of it, with a worked example, is in
[OTHER-PARACHUTES.md](https://github.com/ParachuteComputer/parachute/blob/0c1f0af2ff5575e22a8aa34669474f8c88c8e663/docs/OTHER-PARACHUTES.md). Three things for an applet's author:

- **A page with embeds scrolls as a whole.** An applet whose record has `fields.embeds` is drawn as tall as its content,
  with its embeds under it; `position: fixed` and its own inner scrolling scroll with the page. A page that grows by the
  same amount three times running is held at its height (that is how a layout sized to the screen stops growing for
  ever), so one that adds rows on a tap should page them rather than grow without end.
- **Check who a message is from.** The kit only reads messages from the app. An HTML applet that listens for
  `message` events itself must check `event.source === parent`: on a page with embeds, other frames can post to it.
- **Never ask for a key or a password.** Parachute never does inside a page, and the person is told so.
- **No `<form>` submits.** The sealed frame has no `allow-forms`, so a submit does nothing: use a button's `onClick`.

### The parts (`import { … } from "parachute"`, TSX and JSX only)

The pieces to build a screen from, drawn in the app's look: they follow the person's theme, as the rest of the app
does. Each takes plain props; a newer prop is only ever added, never changed.

| Part | What it draws |
|---|---|
| `<Note body path? tags? fields? onLink? />` | A note's text as the app's note view draws it: markdown, and rich notes (a recipe with servings and timers, tasks, logs, callouts, charts from tables); give the record's `tags` and `fields` so a typed note (tagged `recipe`) draws as its type, and its `path`, which tells one note from the next. Its links are the kit's ([Links](#links)): a `[[wikilink]]`, a `<vault>:<ULID>` and a note's address open the note in the app, a web address the browser. With `onLink(target)` a tap goes there instead, with a wikilink's target as written (`[[Green herb rice]]` gives `Green herb rice`), the `<vault>:<ULID>` or the address: open it yourself, or hand it to `link.follow`. The renderer is large, so the app loads it only for an applet that imports `Note`. |
| `<Link to from? >…</Link>` | One link: a note's address, `<vault>:<ULID>`, `[[target]]` (with `from`, the path of the note it is in) or a web address. See [Links](#links). |
| `<Linked text web? />` | Plain text with its note links drawn as `Link`s: a message, a mail. With `web`, its other web addresses too (they open only with `links`). |
| `link (.to, .follow, .open, .parse, .find)` | The links as calls: `await link.to(record)` is the address to write for a note of the applet's vault; `link.follow(target, { from })` opens one on a tap; `link.open(record)` opens a note of its own vault on a tap (a row's `onPress`); `link.parse(text)` says what a link names (or null); `link.find(text)` gives the links in plain text. |
| `<Days times? counts? days? label? inline? />` | What changed, a day at a time: a column of ink marks per day, weeks set apart, today marked. Give `times` (ISO times, counted by day) or `counts` (oldest first). `days` defaults to 28; `inline` draws it inside a line (a row, a link). |
| `<List label? hideLabel? rows more? />` | Rows under a label. A row is `{ key?, title, meta?, aside?, glyph?, onPress?, badge?, strong?, current?, under?, label?, data? }`; one with `onPress` is a button. A long list costs little (a row off screen isn't drawn); `more: { label, onPress }` asks for the next page; `hideLabel` says the label to a screen reader only. |
| `<Card title?>…</Card>` | A raised block with a title. |
| `<Field label placeholder? action? onAction? value? onChange? clearOnAction? />` | A line to write on, and one action (its button, or Enter). It keeps its own text unless `value` is given, and clears after the action unless `clearOnAction` is false. `onAction` should catch its own errors and show them: a failed action leaves the text as it was. |
| `<Empty>…</Empty>` | What shows when there is nothing yet: a sprig and a line. |
| `<Page title? kicker? aside? back? onRefresh? wide? className? >…</Page>` | The applet's screen: one width and margin for every applet, its title on the type scale (a small `kicker` above, `aside` at its right, `back: { label, onPress }` a way back above it), with `onRefresh` pull down at the top to read again, and `wide` for two columns on a computer. |
| `<Tabs label tabs current onChange />` | Places to switch between in one screen (Inbox, Later, Sent): `tabs` is `[{ key, label, count? }]`, the one shown is marked. |
| `<Loading>…</Loading>` | The quiet line while something is read ("Reading…" unless you say). |
| `<Problem error? onRetry? >…</Problem>` | What went wrong, said once: your words, then the error's, and Try again with `onRetry`. |
| `<Button kind? small? busy? onClick >…</Button>` | A button in the app's look: `primary` (the one main action), `plain` (the default) or `quiet`. |
| `<Search label placeholder? value? onChange? onSearch live? />` | A search box: Enter searches (each pause in typing, with `live` ms); emptying it searches for "". |
| `<Write label labelled? value onChange onSend? send? sendLabel? canSend? busy? enter? line? maxLength? inputRef? onKeyDown? >…</Write>` | A box to write in and its action (Ctrl or ⌘ Enter; with `enter="send"`, Enter alone on a computer, as in a chat). `labelled` shows the label above it, as a Field's. Your own buttons (`Record`) sit beside the action; `line` makes it one line that grows; `sendLabel` names the action for a screen reader, `canSend` says there is something to send without words (a file). |
| `<Record onRecorded label? max_s? disabled? kind? small? >…</Record>` | The microphone button: the app's own recorder sheet (needs `reach: [voice]`); `onRecorded({ bytes, type, duration })` on Send. |
| `toast(text, { error? })` | A short word after an action ("Saved"), at the foot of the screen, gone by itself. |
| `voiceNote(recording, create)` | A recording made a note: `create(body)` makes the record (its path is yours), the recording is attached with transcription asked, and the hub writes the words in. |
| `useTranscripts(bodies, reload)` | While a voice note waits for its words: reads again a few times; `say(body)` is the line to show, `strip(body)` the text without the hub's marker, `again()` after a new recording. |
| `when (.time, .day, .date, .short, .full, .ago, .stamp, .path, .parse)` | Dates and times, one way in every applet, in the person's language: `when.short(t)` is "9:41 AM" today, "Yesterday", "Mon", "Nov 17". `t` is a Date, an ISO string, milliseconds or seconds. |
| `useTheme()` | The look as values (`accent`, `bg`, …, `scheme`, `density`), or null until the app has sent it. Most applets need only the CSS variables. |
| `useSaved(key, initial)` | `useState` that the app keeps on this device: a draft, the box it was on, the item open. See [Saved state](#saved-state). |

An HTML applet has no parts: it has the kit's calls and the CSS variables.

**Older apps.** An applet lives in the vault, and each device's app updates on its own time, so an applet meets older
apps. A part an older app doesn't have arrives as `undefined`, and an applet that draws it stops there with one line
saying why. The kit of 11-20 (T-476: everything in the parts table above, with every prop it lists) is the floor the
shipped applets are written on: they need a build with all of it, the first release after 11-20, so their records go to
a vault once the person's devices have that build. A newer prop counts as a newer part: an older app ignores it. A part added after that is imported under another name
with a fallback (`src/kit/olderApp.test.ts` checks the shipped applets do):

```tsx
import { Newer as KitNewer } from "parachute";
const Newer = KitNewer ?? (({ children }: { children?: unknown }) => <>{children}</>);
```

### Saved state

An applet can stop at any moment and lose nothing. The app may unload it to make room (it keeps 6 running on a phone,
12 on a computer), the person may close the app, the phone may restart. What the applet gives the kit to save comes
back when it starts again, before its first paint:

```tsx
const [draft, setDraft] = useSaved("draft", "");      // what is being written
const [tab, setTab] = useSaved("tab", "inbox");        // where it was
<Write label="Your note" value={draft} onChange={setDraft} />
```

- **Saved as it changes.** The kit sends what changed 250 ms after the last change (at most a second while the person
  keeps typing; at once when the applet is hidden), and the app writes it to the device's disk then: a file of the
  applet's own in the app, localStorage in a browser. Nothing waits for a way out, so a force-stop or leaving the
  applet loses at most that last moment. A write that fails is tried again; keys are 1 to 100 plain characters.
- **Setting it back to `initial` forgets it.** Clear a draft when it is sent.
- **Where the page was scrolled** is kept by itself and put back once the page is tall enough again.
- **On this device only**, never synced and never in a vault. A draft that should follow the person to another device
  is a note, written by the applet in its own folder.
- **Gone with Revoke.** When the person revokes the applet (its menu, Settings, or on another device with their key) or
  signs out of its vault, what it saved here is removed: a draft isn't left on the device for whatever is allowed there
  next. A new version the person allows keeps it.
- **256 KB per applet**, the same store as `storage` (`storage.get/set` and `useSaved` see each other's keys). Every
  applet that runs has it, someone else's too; no word in `fields.app` is needed.
- A plain `useState` is lost when the applet stops, as before. In an HTML applet, the calls are
  `parachute.saved.get(key)` (after `ready()`), `parachute.saved.set(key, value)` and `parachute.saved.flush()`.

### Links

A link to a note is written one way, and stored that way: **the note's address on its hub**,

```
https://<hub>/vault/<vault>/view/<id>
```

the page the hub itself serves for the note (to anyone when the note is published, and to someone with a key for that
vault otherwise). So the link works outside Parachute too, and inside the app it opens the note. Get it with
`await link.to(record)` (a note of the applet's own vault) and put it in the text you write; never build it by hand.

The kit also reads two short forms, which applets read but never write:

- `<vault>:<ULID>`, a vault by its name and a note's id: `uni:01KA3Z9V6B2W8XQJ4M7N5P0R1S`, as Uni writes in chat.
- `[[Path or Title]]` inside a note: a note in the same vault, by its path, or beside the note it is in, and only in the
  folders the applet may read (a path can be guessed: the app won't say what is there to an applet that can't read it).

And the address Parachute's web app shows for a note (`https://<hub>/surface/parachute/v/<vault>/n/<id>`).

Draw links only with the kit: `Linked` for text you show as it is (a message, a mail), `Link` for one link you place,
and `Note` for a note's text. Each asks the app what a note link leads to, and the app answers from the vaults the
person has, without telling the applet which those are:

| The link | What the person sees | A tap |
|---|---|---|
| a note in a vault they have | a link | opens the note in the app: in the applet whose `opens` takes its kind, else the plain note view |
| an address of a vault they haven't added | a link | the app's link screen, which says so and offers to add that Parachute |
| an address in a vault they have whose note part isn't an id, or whose note isn't there | a link | the app's link screen, which opens what the vault has at that address, or says it isn't there |
| a `<vault>:<ULID>` of a vault they don't have, or of a note that isn't there; a `[[wikilink]]` to nothing | plain text | nothing: no guess |
| any other web address | a link | the browser (with `links`) |

The app looks a note up by its id only: an address or short form that names a path or a title is never asked for, and
a note found some other way doesn't count, so an applet can't learn which notes exist outside what it may read.

A long-press (a right-click on a computer) on a note link asks with **Open with…** instead. Note links need `open` in
`fields.app`; without it they are drawn as text (an address as a web address). The shipped applets link only through
the kit (`src/kit/links.test.ts` checks it): no `<a>` of their own, no `app.openLink` of their own, and no `app.open` but in a home applet (one that asks for `pins` or `recent`), for the app's own places.
