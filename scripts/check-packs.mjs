// Each pack page's block is the pack the app ships (parachute src/kit/packs/<id>.json): the app applies one with a tap,
// an AI applies the other, and they must be the same pack. Run: node scripts/check-packs.mjs [path to the app's
// src/kit/packs] (default: the app's `next` on GitHub). Exits 1 on any difference.
import { readdirSync, readFileSync } from "node:fs";
import { isDeepStrictEqual } from "node:util";

const appDir = process.argv[2];
const pages = readdirSync(new URL("../docs/build/packs/", import.meta.url)).filter((f) => f.endsWith(".md"));
let bad = 0;
for (const f of pages) {
  const id = f.replace(/\.md$/, "");
  const md = readFileSync(new URL(`../docs/build/packs/${f}`, import.meta.url), "utf8");
  const blocks = [...md.matchAll(/```json\n([\s\S]*?)\n```/g)].map((m) => m[1]).filter((b) => b.includes('"parachute_pack"'));
  if (blocks.length !== 1) { console.error(`${f}: ${blocks.length} pack blocks, not 1`); bad++; continue; }
  const page = JSON.parse(blocks[0]);
  const text = appDir ? readFileSync(`${appDir}/${id}.json`, "utf8")
    : await (await fetch(`https://raw.githubusercontent.com/ParachuteComputer/parachute/next/src/kit/packs/${id}.json`)).text();
  const app = JSON.parse(text);
  if (!isDeepStrictEqual(page, app)) { console.error(`${f}: differs from the app's ${id}.json`); bad++; }
  else console.log(`${f}: the same pack as the app's ${id}.json (version ${app.version})`);
}
process.exit(bad ? 1 : 0);
