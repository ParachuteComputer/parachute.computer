#!/usr/bin/env node
// Export the /pitch deck to a multi-page landscape PDF (one slide per page).
//
// The deck is an HTML click-through (only the active slide is shown), so we
// step through each slide via the ?s=N deep-link, screenshot the slide card,
// and assemble the shots into a single PDF — one slide per page, uniform size.
//
// Prereqs: Playwright chromium installed, and the eleventy dev server running:
//   npx @11ty/eleventy --serve --port 8080
// Usage: node scripts/export-pitch-pdf.js [outPath] [slideCount] [baseUrl]
const { chromium } = require('playwright');
const path = require('path');

const OUT = process.argv[2] || 'assets/pitch/parachute-pitch-deck.pdf';
const COUNT = parseInt(process.argv[3] || '9', 10);
const BASE = process.argv[4] || 'http://localhost:8080/pitch/';

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 880 }, deviceScaleFactor: 2 });
  const page = await ctx.newPage();

  const shots = [];
  let box = null;
  for (let n = 1; n <= COUNT; n++) {
    await page.goto(`${BASE}?s=${n}`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(450);
    const el = await page.$('.pi-slide.is-active');
    if (!el) throw new Error(`no active slide for s=${n}`);
    if (!box) box = await el.boundingBox();
    const buf = await el.screenshot({ type: 'png' });
    shots.push('data:image/png;base64,' + buf.toString('base64'));
    process.stdout.write(`  slide ${n} captured\n`);
  }

  // Assemble: one image per landscape page, sized to the (uniform) slide card.
  const W = Math.round(box.width);
  const H = Math.round(box.height);
  const pages = shots
    .map((src) => `<div class="pg"><img src="${src}"></div>`)
    .join('\n');
  const html = `<!doctype html><html><head><meta charset="utf-8"><style>
    @page { size: ${W}px ${H}px; margin: 0; }
    html,body { margin:0; padding:0; }
    .pg { width:${W}px; height:${H}px; page-break-after:always; overflow:hidden; }
    .pg:last-child { page-break-after:auto; }
    img { width:100%; height:100%; display:block; object-fit:contain; background:#f7f4ed; }
  </style></head><body>${pages}</body></html>`;

  const pdfPage = await ctx.newPage();
  await pdfPage.setContent(html, { waitUntil: 'networkidle' });
  await pdfPage.pdf({
    path: OUT,
    width: `${W}px`,
    height: `${H}px`,
    printBackground: true,
    preferCSSPageSize: true,
  });
  process.stdout.write(`\nWrote ${OUT}  (${COUNT} pages, ${W}x${H})\n`);
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
