// Every docs page: markdown only (its examples hold `{{` and must not be read as templates), on the docs layout, at
// /docs/<folder>/<name>/, with its markdown twin at /docs/<folder>/<name>.md (docs-md.njk).
const slugOf = (d) => d.page.filePathStem.replace(/^\/docs\//, "");
module.exports = {
  templateEngineOverride: "md",
  layout: "doc.njk",
  eleventyComputed: {
    slug: slugOf,
    permalink: (d) => `/docs/${slugOf(d)}/`,
    mdTwin: (d) => `/docs/${slugOf(d)}.md`,
  },
};
