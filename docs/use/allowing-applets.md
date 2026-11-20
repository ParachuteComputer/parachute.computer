---
title: "What Allow means"
summary: "Nothing an AI writes runs until you allow it, on a card that says what it asks for."
door: use
order: 4
checked: "parachute docs/WRITE-AN-APPLET.md (What the person sees), docs/design/APP-RECORD.md (Running needs a signed approval, Security levels), docs/design/PERMISSIONS.md"
---

An applet is code your AI (or anyone who can write your vault) put there. So the first time you open one, the app shows its **card** and runs nothing until you tap **Allow**.

## The card

It says, in plain words, what the applet asks for: which folders it may read or add to ("Read and add notes in Books/"), which kinds of note it opens, any server it talks to and what the app will sign there as you, web links on their own line (what it reads could leave that way), and the small things (files, the microphone, drafts) on one **Also** line. **Show details** lists every line.

An applet never gets your key or a password, and has no network of its own. (On Android it could still send what it reads to the internet, so there only code you allowed runs, and the card says so.) It sees only the folders on its card, in its own vault; it can't change its own code or anyone else's, and it can't delete.

## Changed code asks again

When the code or what it asks for changes, the card shows again before the new version runs, on every device.

## One Allow, every device

On a device that holds your key, **Allow** signs an approval of that exact code with your key and keeps it in your home vault (`Parachute/Approvals/`). Your other devices check the signature and the code's hash and run it too. Someone who can write your vault can't forge one: changed code, a widened ask, or an approval signed by another key doesn't run.

**Revoke** (the applet's ⋯ menu, or Settings → Applets) takes it back everywhere, and removes what it saved on the device.

## How careful the app is

Settings → **Security** sets, per action, what a tap needs: nothing more, the device unlock, or a **passcode** of your own. Approving code always needs at least the unlock. You can also set an **idle lock**: untouched for so many minutes, Parachute is covered until the device unlock. A bundle can raise these, never lower them.
