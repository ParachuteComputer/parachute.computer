---
title: "Start from a pack"
summary: "Add people, projects, meetings and tasks to a vault with one tap; new records start from a template, and any record can become one."
door: use
order: 3.5
checked: "parachute applets/vault.tsx (Packs, New from the template, Make this a template), docs/PACKS.md, e2e/packs.spec.ts"
---

A **pack** adds a set of kinds of record to a vault, each with its fields and a template. A **template** is how a new record starts.

## Add a pack

In the app, open **Vault**, then your vault, then **Add a pack**. **Core types** adds people, projects, meetings and tasks, a template for each, and a view of open tasks. It lists what it adds before you tap **Add Core types**, and says afterwards what it added and what it left as you had it. **Installed packs** shows what a vault has. Adding a pack again changes nothing.

Or ask your AI: "Set me up with the core types." It reads [the same pack](/docs/build/packs/core-types/) and adds the same things.

## Start from a template

**New meeting** starts from the meeting template: its headings are there for you to fill in. The template is an ordinary record in `Templates/meeting/`: change it, and new meetings start from your version. Records you made before keep what they have.

## Make your own

On any record, **Make this a template** keeps its headings and makes a template of them. The first template for a kind of record is the one **New** uses.
