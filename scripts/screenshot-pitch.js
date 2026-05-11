#!/usr/bin/env node
// Screenshot every pitch slide at desktop viewport sizes.
//
// Prerequisite: Playwright's chromium binary must be installed:
//   npx playwright install chromium
// (The `npm run screenshots` script handles this for you.)
//
// Also expects the eleventy dev server running at http://localhost:8080:
//   npx @11ty/eleventy --serve --port 8080
//
// Usage: node scripts/screenshot-pitch.js [outDir]
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const OUT_DIR = process.argv[2] || '/tmp/pitch-shots';
const BASE = 'http://localhost:8080/pitch/';

const VIEWPORTS = [
  { name: '1440', width: 1440, height: 900 },
  { name: '1920', width: 1920, height: 1080 },
];

(async () => {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const browser = await chromium.launch();
  for (const vp of VIEWPORTS) {
    const ctx = await browser.newContext({ viewport: { width: vp.width, height: vp.height }, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    for (let i = 1; i <= 10; i++) {
      await page.goto(`${BASE}?s=${i}`, { waitUntil: 'networkidle' });
      // Let fade-up animation settle and any images load.
      await page.waitForTimeout(400);
      const out = path.join(OUT_DIR, `slide-${String(i).padStart(2,'0')}-${vp.name}.png`);
      await page.screenshot({ path: out, fullPage: false });
      // Also probe document scroll height vs viewport to flag overflow.
      const overflow = await page.evaluate(() => ({
        scrollH: document.documentElement.scrollHeight,
        innerH: window.innerHeight,
        slideH: document.querySelector('.pi-slide.is-active')?.getBoundingClientRect().height || 0,
      }));
      console.log(`${vp.name}  slide ${i}  scrollH=${overflow.scrollH}  innerH=${overflow.innerH}  slideH=${overflow.slideH.toFixed(0)}  overflow=${overflow.scrollH - overflow.innerH}`);
    }
    await ctx.close();
  }
  await browser.close();
  console.log(`\nScreenshots written to ${OUT_DIR}`);
})();
