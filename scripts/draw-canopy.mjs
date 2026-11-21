// The homepage drawing: a parachute canopy in fine engraved lines, its rigging running down to the edge of the
// drawing, where the "Connect your AI" card hangs from it. Writes _includes/canopy.svg (inlined by index.njk, so its
// lines take the theme's colours, light or dark). Run: node scripts/draw-canopy.mjs
import { writeFileSync } from "node:fs";

const W = 600, H = 320;           // the drawing's box
const cx = 300, rimY = 160;       // the canopy's centre and the height of its rim
const a = 250, b = 140, tilt = 26; // half-width, height, and how far we see it from below
const r = (n) => Math.round(n * 10) / 10;
const rad = (d) => (d * Math.PI) / 180;
// A point on the canopy: phi from the apex (0) to the rim (90), theta around it (-90 left … 90 right).
const pt = (phi, theta) => [cx + a * Math.sin(rad(phi)) * Math.sin(rad(theta)), rimY - b * Math.cos(rad(phi)) + tilt * Math.sin(rad(phi)) * Math.cos(rad(theta))];
const line = (pts) => "M" + pts.map(([x, y]) => `${r(x)} ${r(y)}`).join(" L");

const GORES = 10;
const seamsAt = Array.from({ length: GORES + 1 }, (_, i) => -90 + (180 * i) / GORES);

// the outline: the left and right meridians, then the scalloped rim (each gore's hem dips between two seams)
const left = Array.from({ length: 31 }, (_, i) => pt(90 - 3 * i, -90));
const right = Array.from({ length: 31 }, (_, i) => pt(3 * i, 90));
let rim = "";
for (let i = GORES - 1; i >= 0; i--) {   // right to left, back to where the outline began
  const [x1, y1] = pt(90, seamsAt[i]);
  const [xm, ym] = pt(90, (seamsAt[i] + seamsAt[i + 1]) / 2);
  rim += ` Q${r(xm)} ${r(ym + 13)} ${r(x1)} ${r(y1)}`;
}
const outline = line([...left, ...right]) + rim;

// the seams: meridians from the apex to the rim
const seams = seamsAt.slice(1, -1).map((t) => line(Array.from({ length: 31 }, (_, i) => pt(3 * i, t))));

// the hatching: lines of latitude across each gore, closer together towards the right (the shaded side)
const hatch = [];
for (let g = 0; g < GORES; g++) {
  const t0 = seamsAt[g], t1 = seamsAt[g + 1];
  const shade = (g + 1) / GORES;                       // 0.1 on the left … 1 on the right
  const step = 7 - 4 * shade;                           // degrees between lines
  for (let phi = 22 + (g % 2) * 2; phi < 86; phi += step) {
    hatch.push(line(Array.from({ length: 7 }, (_, i) => pt(phi, t0 + ((t1 - t0) * (i + 0.5)) / 7.4))));
  }
}

// the rigging: from every seam on the rim down to two risers at the foot of the drawing
const risers = [[W * 0.36, H], [W * 0.64, H]];
const rigging = seamsAt.map((t, i) => {
  const [x, y] = pt(90, t);
  const [rx, ry] = risers[i < GORES / 2 ? 0 : i > GORES / 2 ? 1 : (t < 0 ? 0 : 1)];
  return line([[x, y], [rx, ry]]);
});

const svg = `<svg class="canopy" viewBox="0 0 ${W} ${H}" aria-hidden="true" focusable="false">
<path class="cn-fill" d="${outline} Z"/>
<g class="cn-hatch">${hatch.map((d) => `<path d="${d}"/>`).join("")}</g>
<g class="cn-seam">${seams.map((d) => `<path d="${d}"/>`).join("")}</g>
<path class="cn-edge" d="${outline}"/>
<g class="cn-line">${rigging.map((d) => `<path d="${d}"/>`).join("")}</g>
</svg>
`;
writeFileSync(new URL("../_includes/canopy.svg", import.meta.url), svg);
console.log("wrote _includes/canopy.svg", svg.length, "bytes");
