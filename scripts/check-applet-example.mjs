#!/usr/bin/env node
// Does the applet on "Make an applet" pass what the Parachute app checks before it runs one? Its manifest
// (parseManifest), what it opens (parseOpens), the TSX transpile (transpile), the kit conformance rules the shipped
// applets are held to (check), and its imports. Reads the example from the page itself, so the page can't drift.
//
//   npm run docs:check-applet -- <a checkout of ParachuteComputer/parachute>   (Node 22.18+: it imports the app's .ts)
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const app = resolve(process.argv[2] ?? "../parachute");
const page = readFileSync(join(import.meta.dirname, "..", "docs", "build", "make-an-applet.md"), "utf8");
const block = page.match(/```json\ncreate-record (\{[\s\S]*?\n\})\n```/);
if (!block) throw new Error("no create-record example on make-an-applet.md");
const rec = JSON.parse(block[1]);
const { parseManifest } = await import(join(app, "src/applet/manifest.ts"));
const { parseOpens } = await import(join(app, "src/applet/opens.ts"));
const { transpile } = await import(join(app, "src/applet/code.ts"));
const { check } = await import(join(app, "src/kit/conformance.ts"));
const problems = [];
const m = parseManifest(rec.fields.applet);
if (!m.ok) problems.push(`manifest refused: ${m.error}`);
else if (rec.fields.opens !== undefined) {
  const o = parseOpens(rec.fields.opens, m.manifest);
  if (!o.ok) problems.push(`opens refused: ${o.error}`);
}
if (rec.extension !== "tsx") problems.push(`extension is ${rec.extension}, not tsx`);
const t = await transpile(rec.body, "tsx");
if (!t.ok) problems.push(`doesn't transpile: ${t.error}`);
for (const f of check(rec.body)) problems.push(`kit conformance, line ${f.line}: ${f.what} (use ${f.use})`);
for (const [, i] of rec.body.matchAll(/from\s+"([^"]+)"/g)) if (!["react", "react-dom", "react-dom/client", "parachute"].includes(i)) problems.push(`imports ${i}, which the app doesn't provide`);
// the laid-out code on the page is the same code
if (!page.includes(rec.body.trimEnd())) problems.push("the laid-out code on the page differs from the record's body");
if (problems.length) {
  console.error(problems.map((p) => `✗ ${p}`).join("\n"));
  process.exit(1);
}
console.log(`✓ the applet on make-an-applet.md passes the app's manifest, opens, transpile and kit checks (${app})`);
