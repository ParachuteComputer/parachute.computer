const fs = require("node:fs");

/** A docs page as an agent reads it: the page's own markdown, its title and summary on top, no front matter. */
function mdTwin(doc) {
  const raw = fs.readFileSync(doc.inputPath, "utf8").replace(/^---\n[\s\S]*?\n---\n/, "").trim()
    // links to other docs pages point at their markdown, with the host, so an agent can follow them (or ask the docs
    // tool for the same name); other site links get the host
    // (a page is a door and a name, `build/make-a-type`; a door alone, `/docs/build/`, has no twin and stays a page)
    .replace(/\]\(\/docs\/([a-z0-9-]+\/[a-z0-9/-]+?)\/?(#[^)]*)?\)/g, (_m, p, h = "") => `](https://parachute.computer/docs/${p}.md${h})`)
    .replace(/\]\(\/(?!\/)([^)]*)\)/g, "](https://parachute.computer/$1)");
  const d = doc.data;
  const head = [`# ${d.title}`, "", `> ${d.summary}`, ""];
  if (d.status && d.status !== "current") head.push(`**${d.status === "next" ? "Next release" : "Coming"}:** ${d.status_note || ""}`, "");
  const foot = ["", "---", "", `For people: https://parachute.computer/docs/${d.slug}/ · All pages: https://parachute.computer/llms.txt`];
  if (d.checked) foot.push(`Checked against the code: ${d.checked}`);
  return [...head, raw, ...foot].join("\n") + "\n";
}

module.exports = function (eleventyConfig) {
  eleventyConfig.addFilter("mdTwin", mdTwin);
  // A summary is a line of markdown: its `code` drawn as code on the page, and plain in a meta description.
  const esc = (t) => String(t ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  // Inline code never breaks inside a name; a long one (an address, a call with its arguments) may break after a slash
  // or at a space, and nowhere else.
  const codeTag = (raw) => raw.length > 28
    ? `<code class="long">${esc(raw).replace(/\//g, "/<wbr>")}</code>`
    : `<code>${esc(raw)}</code>`;
  eleventyConfig.addFilter("inlineCode", (t) => String(t ?? "").split(/(`[^`]+`)/).map((part) => /^`[^`]+`$/.test(part) ? codeTag(part.slice(1, -1)) : esc(part)).join(""));
  eleventyConfig.addFilter("plainText", (t) => String(t ?? "").replace(/`([^`]+)`/g, "$1"));
  // The docs, in reading order: by door (use, build, run), then `order`.
  const DOORS = ["use", "build", "run"];
  eleventyConfig.addCollection("docs", (api) =>
    api
      .getFilteredByGlob("docs/**/*.md")
      .sort((a, b) => DOORS.indexOf(a.data.door) - DOORS.indexOf(b.data.door) || (a.data.order ?? 99) - (b.data.order ?? 99)));
  eleventyConfig.addFilter("door", (docs, door) => docs.filter((d) => d.data.door === door));
  // One door's labels (_data/doorPages.json) by its name.
  eleventyConfig.addFilter("doorOf", (doorPages, door) => doorPages.find((d) => d.door === door));
  // A reference page's name under the "Reference" heading, without saying "Reference: " again.
  eleventyConfig.addFilter("refName", (t) => { const n = String(t ?? "").replace(/^Reference: /, ""); return n.charAt(0).toUpperCase() + n.slice(1); });
  // A door's pages in two groups: the guides, then the reference (docs/<door>/reference/, generated).
  eleventyConfig.addFilter("guides", (docs) => docs.filter((d) => !d.url.includes("/reference/")));
  eleventyConfig.addFilter("refs", (docs) => docs.filter((d) => d.url.includes("/reference/")));
  // The pages before and after this one, in reading order (all the doors in a row).
  eleventyConfig.addFilter("pager", (docs, url) => {
    const i = docs.findIndex((d) => d.url === url);
    return { prev: i > 0 ? docs[i - 1] : null, next: i >= 0 && i < docs.length - 1 ? docs[i + 1] : null };
  });
  // A page's sections, for "On this page": its h2s, with the ids given below.
  eleventyConfig.addFilter("sections", (html) =>
    [...String(html ?? "").matchAll(/<h2\b[^>]*\sid="([^"]+)"[^>]*>([\s\S]*?)<\/h2>/g)].map((m) => ({ id: m[1], text: m[2].replace(/<[^>]+>/g, "") })));
  // Rendered markdown only (the .md twins are the files as written): every h2 and h3 gets an id from its text, as
  // GitHub makes them, so `#saved-state` links work and sections can be linked; a table sits in a box that scrolls
  // sideways on a narrow screen rather than squeezing its columns.
  eleventyConfig.amendLibrary("md", (md) => {
    const slug = (t) => t.toLowerCase().trim().replace(/[^\p{L}\p{M}\p{N}_\s-]/gu, "").replace(/\s/g, "-");
    md.core.ruler.push("heading_ids", (state) => {
      const seen = new Map();
      state.tokens.forEach((t, i) => {
        if (t.type !== "heading_open" || !["h2", "h3"].includes(t.tag) || t.attrGet("id")) return;
        const text = state.tokens[i + 1].children.filter((c) => c.type === "text" || c.type === "code_inline").map((c) => c.content).join("");
        let id = slug(text) || "section";
        const n = seen.get(id) ?? 0;
        seen.set(id, n + 1);
        if (n) id += `-${n}`;
        t.attrSet("id", id);
      });
    });
    md.renderer.rules.code_inline = (tokens, i) => codeTag(tokens[i].content);
    md.renderer.rules.table_open = () => '<div class="table-wrap"><table>\n';
    md.renderer.rules.table_close = () => "</table></div>\n";
  });
  // Pass through static assets (not processed as templates)
  eleventyConfig.addPassthroughCopy("style.css");
  eleventyConfig.addPassthroughCopy("CNAME");
  eleventyConfig.addPassthroughCopy("assets/**/*");
  eleventyConfig.addPassthroughCopy("archive/**/*");
  // Curl-able install scripts (served verbatim, e.g. /install/digitalocean.sh).
  // NB: /install/index.html is a redirect (_data/redirects.json, redirects.njk)
  // — passthrough files and that page land in the same dir without colliding.
  eleventyConfig.addPassthroughCopy("install/**/*");
  // Provider-neutral alias: /install/server.sh is the SAME source file as
  // digitalocean.sh, copied to a second name at build time (single source of
  // truth, byte-identical, never drifts). /start presents server.sh as the
  // one-liner; digitalocean.sh stays served so circulated links don't break.
  eleventyConfig.addPassthroughCopy({ "install/digitalocean.sh": "install/server.sh" });
  // Machine-readable site index (llmstxt.org convention). Since T-476
  // (llms.txt and llms-full.txt are generated from the docs: llms.njk, llms-full.njk.)
  // The agent-facing install runbook, emitted TWICE from ONE source file:
  //   • raw markdown at /install.md — the pasteable URL you hand an agent
  //     (this passthrough copies the file byte-for-byte), and
  //   • rendered HTML at /install/runbook/ — so a human opening it in a
  //     browser gets the site's typography rather than a plain-text dump.
  // 11ty templates the same .md through the normal pipeline; its frontmatter
  // lives in the sibling install-runbook.11tydata.json so the RAW copy carries
  // no YAML noise. Passthrough and template processing are independent, so the
  // two outputs coexist and can never drift — there is only one source.
  eleventyConfig.addPassthroughCopy({ "install-runbook.md": "install.md" });
  // Favicon + webclip + PWA icons at site root
  eleventyConfig.addPassthroughCopy("*.png");
  eleventyConfig.addPassthroughCopy("site.webmanifest");
  // The homepage. ONE self-contained file (all CSS/JS/SVG inlined) — a
  // repo-root artifact you can open directly AND the deployed homepage.
  // Not templated (templateFormats is njk/md only) — copied verbatim.
  // Promoted from the /v2/ candidate route 2026-07-02; /v2/ is now a
  // redirect (v2-redirect.njk) because the preview link circulated.
  // The old homepage is archived at /archive/home-v1/ (rendered snapshot
  // + source), per the archive convention.
  // Since T-476 the homepage is index.njk on the shared layout; the self-contained landing of 2026-07 is archived
  // at /archive/home-v2/.

  // Unlisted business plan. Self-contained HTML (all CSS inlined), copied
  // verbatim to /business-plan/ — not templated, not in any nav, and carries
  // <meta robots noindex> in its own <head>. Shared by direct link only
  // (friends-and-family round), same passthrough pattern as the homepage.
  eleventyConfig.addPassthroughCopy({ "business-plan.html": "business-plan/index.html" });

  // Ignore non-content files
  eleventyConfig.ignores.add("CLAUDE.md");
  eleventyConfig.ignores.add("DEPLOY-subscribe.md");
  eleventyConfig.ignores.add("blog/drafts/**");
  eleventyConfig.ignores.add("node_modules/**");
  eleventyConfig.ignores.add("archive/**");
  // Subscribe Worker backend assets — not part of the static site output.
  // The Worker deploys via `wrangler deploy` (a separate Cloudflare
  // origin); `migrations/` + `wrangler.toml` are its config, not content.
  eleventyConfig.ignores.add("worker/**");
  eleventyConfig.ignores.add("migrations/**");
  eleventyConfig.ignores.add("wrangler.toml");

  // Date formatting filter (uses UTC to avoid timezone offset issues)
  eleventyConfig.addFilter("dateDisplay", (dateObj) => {
    const d = new Date(dateObj);
    return d.toLocaleDateString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
      timeZone: "UTC",
    });
  });

  // Blog collection: all markdown files in blog/ (not drafts)
  eleventyConfig.addCollection("posts", (collectionApi) => {
    return collectionApi
      .getFilteredByGlob("blog/*.md")
      .sort((a, b) => b.date - a.date);
  });

  return {
    dir: {
      input: ".",
      output: "_site",
      includes: "_includes",
      data: "_data",
    },
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk",
    templateFormats: ["njk", "md"],
  };
};
