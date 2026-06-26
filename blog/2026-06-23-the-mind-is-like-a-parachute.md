---
layout: post.njk
title: "The mind is like a parachute"
subtitle: "A year in: where Parachute came from, and why it's never been easier to run your own."
date: 2026-06-23T12:00:00
author: "Aaron G Neyer"
permalink: /blog/the-mind-is-like-a-parachute/
description: "A year ago today I wrote 'started work on the parachute mvp.' Where Parachute came from — and where it is now: a resilient, modular, self-hosted home for your knowledge that any AI can read and write, and that's never been easier to run."
---

It was one year ago today that I wrote in my journal: *"started work on the parachute mvp."* A week earlier I'd copied down a line from Frank Zappa — *"The mind is like a parachute, it doesn't work if it's not open"* — and dropped it into [an article I was writing](https://unforced.org/writing/cognition-computation-and-connection/). It was somewhere in that piece that I knew Parachute was the name for the thing I was chasing.

![A figure drifting down beneath a warm-canopied parachute, working on a laptop mid-air.](/assets/blog/parachute-laptop.png)

I knew it had to do with memory, and with knowledge graphs. I had a strong conviction that there was a way to blend LLMs and knowledge graphs that nobody was quite doing yet — the closest things were Claude Code and Obsidian, and the "LLM wikis" Andrej Karpathy had started tweeting about.

This had been a long time coming. One of my first real projects, back in college, was an app I called [QuantifiedLife](https://github.com/unforced/QuantifiedLife) — a place to track and *notice* the texture of my days. I lost the thread of it for years; my dad passed away around the time I graduated, and I spent a long stretch traveling rather than building. But the core of it never quite let go of me. By the time I landed back at Google in 2021 — working under data-privacy rules that pushed me toward tools which respect your data — I was circling the same idea again, and it rekindled a lifelong pull toward open source.

Those two threads — *own your data*, and *keep it open* — are exactly where my daily tools kept falling short. I'd been journaling consistently since 2022, dancing between Tana and Obsidian, loving each and frustrated by each. They pointed at the same networked way of holding knowledge, and neither quite got it right. Tana wasn't self-hosted. Obsidian wasn't open source. And neither gave me both the power and the flexibility I needed to truly build a system that worked for me. Eventually it was clear: this one was mine to build.

I tried a lot of directions over the year — querying my journals into a graph, connectors to use Claude Code inside Obsidian, a full Claude Code wrapper sitting on a graph database. Then I threw it all out and went back to first principles: a simple, flexible knowledge graph that works *beautifully* with Claude Code and other AI. Notes with metadata and tags that link to each other (the thing Obsidian nails), and tags that act as types (Tana's supertags). That became the **vault** — our first core module, which we [launched](/blog/parachute-is-here/) two months ago today.

## Where it is now

Since then it's grown into a real hub-and-spoke system: one hub that routes to the other modules, with the vault at the core. We've made the whole thing far more resilient, worked out a thousand little kinks our early beta users found, and — the big one — made it genuinely easy to run your own. Getting started is one command:

```
bun add -g @openparachute/hub && parachute init
```

That brings up your hub, installs your vault, and walks you through a short setup wizard; then you [connect any AI](/start/) — Claude, ChatGPT, your own agents — by pointing it at a single URL, and your memory persists across every tool and session. The ideal home for it is a machine you own that stays awake — a small [VPS](/start/) (Hetzner or DigitalOcean run about $5–12/month) or a Mac you leave on — rather than a laptop that sleeps. The [full walkthrough lives at parachute.computer/start](/start/).

It's still early and still rough in places, but it's solid enough that I now run my own unified, fully self-hosted interface for nearly all of my digital thinking on top of it — and I'm not alone in that. We'll be sharing more soon about how some of our core users are opening their parachutes.

## Make it yours

That's possible because the vault is simply an open knowledge graph that any AI — and any UI — can read and write. So the way *you* see your vault doesn't have to be the way I see mine. A **surface** is a custom interface over your vault, shaped to how you actually think: a daily-capture inbox, a project dashboard, a weekly-review board, a quiet reading garden. Your AI can build one *for* you, right in your editor — it's a few lines on our surface SDK (`@openparachute/surface-client` for auth + the vault API, `@openparachute/surface-render` for rendering), so it can spend its effort on the parts that are actually yours rather than re-plumbing OAuth and markdown.

And you run a surface however suits you: a small static app on your own machine, hosted free on GitHub Pages, or served from your hub by the **surface** module. The vault doesn't care which one is asking — they all read and write the same graph. Our default, [notes.parachute.computer](https://notes.parachute.computer), is one such surface; increasingly it's a *reference implementation* to build your own on top of rather than the only way in. That's been one of the most exciting parts of this stretch — watching people stand up surfaces I'd never have thought to make, each fitting a mind I'll never fully see.

There's something even newer taking shape underneath all this, too — vault-native agents you define from inside the vault itself — but that's a story for another post.

## Come along for the ride

Parachute is still in its early days, and it'll stay rough around some edges for a while yet — but I'm incredibly confident about where it's going, and I hope you'll come along.

It's significantly easier to start now. Run it on a box you own, or [email me](mailto:aaron@parachute.computer) and I'll set you up an account on our internal testing server for friends. And a more solid cloud offering is coming, so you'll be able to use this without standing up any infrastructure of your own.

[Get started →](/start/)
