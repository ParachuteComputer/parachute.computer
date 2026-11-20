---
title: "Your home, your pins, your applets"
summary: "What the app shows is a bundle, one record in your home vault, which you and your AI can change."
door: use
order: 3
checked: "parachute docs/NAVIGATION.md (The four rules, Apps, Home, A way back), docs/design/APP-RECORD.md (What an unsigned record can change), src/shell/apps.ts appOf"
---

The Parachute app is thin. It holds your key and your sign-ins, and shows what your vault tells it to: which applets you have, which are pinned on the bar, and which one opens first. That choice is a **bundle**: one record in your home vault.

## What you see

- **The home**: the applet the app opens on. Any applet can be your home.
- **The bar**: your pins along the bottom, in order, then **Applets**.
- **The list** (**Applets** on the bar): every applet the bundle offers, in one plain list. Settings is there too.
- **A note** opens in the applet that opens its kind (a `book` record in your reading applet), else as plain text. Long-press for **Open with…**.
- **Back** goes where you came from.

## Change it by hand

- Long-press an applet in the list: **Pin to the bar**, **Unpin**, **Open on start**.
- Long-press a pin on the bar: **Move left**, **Move right**, **Unpin**.
- Settings → **Your app** picks the bundle this device opens: **Simple**, **Everything**, or one of yours.

## Change it with your AI

Ask: "Pin my journal and reading list, and open on the journal." Your AI writes the bundle record; the app reads it the next time it starts or shows the list. The record's format is in [Make a bundle](/docs/build/make-a-bundle/).

## What a bundle can't do

Anyone who can write your vault can change a bundle, so the app takes only three things from it: the home, the pins and the list. None of them runs code. An applet still shows its card the first time you open it, and again when its code changes. A home only opens by itself once you have allowed its code *and* chosen it as home on that device. A bundle can make the app stricter (an idle lock, a passcode), never looser.

If a bundle is broken or missing, the app opens the plain list and says *Your app record didn't load*, with Settings. You are never locked out.

*In the app and its code a bundle is still called an "app" (Settings → Your app, `Parachute/Apps/<id>`); the rename to "bundle" is under way.*
