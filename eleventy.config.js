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
  // Favicon + webclip + PWA icons at site root
  eleventyConfig.addPassthroughCopy("*.png");
  eleventyConfig.addPassthroughCopy("site.webmanifest");

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
