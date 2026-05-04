module.exports = function (eleventyConfig) {
  // Pass through static assets (not processed as templates)
  eleventyConfig.addPassthroughCopy("style.css");
  eleventyConfig.addPassthroughCopy("CNAME");
  eleventyConfig.addPassthroughCopy("assets/**/*");
  eleventyConfig.addPassthroughCopy("archive/**/*");
  // Favicon + webclip + PWA icons at site root
  eleventyConfig.addPassthroughCopy("*.png");
  eleventyConfig.addPassthroughCopy("site.webmanifest");

  // Ignore non-content files
  eleventyConfig.ignores.add("CLAUDE.md");
  eleventyConfig.ignores.add("INFRASTRUCTURE.md");
  eleventyConfig.ignores.add("blog/drafts/**");
  eleventyConfig.ignores.add("node_modules/**");
  eleventyConfig.ignores.add("archive/**");
  // Cloudflare Pages backend assets — not part of the static site output.
  // Pages picks up `functions/` directly; `migrations/` + `wrangler.toml`
  // are config, not content.
  eleventyConfig.ignores.add("functions/**");
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
