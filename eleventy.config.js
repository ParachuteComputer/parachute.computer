module.exports = function (eleventyConfig) {
  // Pass through static assets (not processed as templates)
  eleventyConfig.addPassthroughCopy("style.css");
  eleventyConfig.addPassthroughCopy("CNAME");
  eleventyConfig.addPassthroughCopy("assets/**/*");
  eleventyConfig.addPassthroughCopy("archive/**/*");
  // Curl-able install scripts (served verbatim, e.g. /install/digitalocean.sh).
  // NB: /install/index.html is a separate redirect template (install-redirect.njk)
  // — passthrough files and that template land in the same dir without colliding.
  eleventyConfig.addPassthroughCopy("install/**/*");
  // Provider-neutral alias: /install/server.sh is the SAME source file as
  // digitalocean.sh, copied to a second name at build time (single source of
  // truth, byte-identical, never drifts). /start presents server.sh as the
  // one-liner; digitalocean.sh stays served so circulated links don't break.
  eleventyConfig.addPassthroughCopy({ "install/digitalocean.sh": "install/server.sh" });
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
  eleventyConfig.addPassthroughCopy({ "landing-preview.html": "index.html" });

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

  // Guides collection: the five starter guides that ship in every vault,
  // in reading order (frontmatter `order`, 1–5).
  eleventyConfig.addCollection("guides", (api) =>
    api
      .getFilteredByGlob("guides/*.md")
      .sort((a, b) => (a.data.order ?? 99) - (b.data.order ?? 99)));

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
