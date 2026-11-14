// Smoke-test every competitor ad card in real Chrome: stills render, videos load with a duration,
// cards run #1..#N by impressions. Serve the repo root on 127.0.0.1:8767 first.
// Needs Playwright (`npm i -D playwright`) and Google Chrome. Lens folder: $LENS_DIR, else docs/lens.
//   node .claude/skills/lens/scripts/smoke-ads.mjs
import { chromium } from 'playwright';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
const root = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
const LENS = process.env.LENS_DIR || 'docs/lens';
const model = JSON.parse(fs.readFileSync(`${root}/${LENS}/model.json`, 'utf8'));
const ps = model.nodes.filter((n) => n.kind === 'product' && n.metaAds.ads.length);
const browser = await chromium.launch({ channel: 'chrome', headless: true });
let ok = true;
// try/finally: the browser must close even when a page or assertion throws, or Chrome lingers.
try {
const page = await browser.newPage({ viewport: { width: 1500, height: 1000 } });
for (const p of ps) {
  await page.goto(`http://127.0.0.1:8767/${LENS}/index.html?n=${Date.now()}#view=alternatives&item=${p.id}`);
  await page.waitForSelector('.ad-card');
  const r = await page.evaluate(async () => {
    const bad = [];
    for (const img of document.querySelectorAll('.ad-card img')) { img.loading = 'eager'; if (!img.complete) await new Promise((res) => { img.onload = img.onerror = res; setTimeout(res, 8000); }); if (!(img.naturalWidth > 0)) bad.push(`still ${img.getAttribute('src')}`); }
    for (const v of document.querySelectorAll('.ad-card video')) {
      v.preload = 'auto'; v.load();
      await new Promise((res) => { if (v.readyState >= 2) return res(); v.oncanplay = v.onloadeddata = v.onerror = res; setTimeout(res, 15000); });
      if (!(v.readyState >= 2 && v.duration > 0)) bad.push(`video ${v.getAttribute('src')}`);
    }
    const ranks = [...document.querySelectorAll('.ad-card .ad-rank')].map((e) => e.textContent);
    return { cards: document.querySelectorAll('.ad-card').length, bad, ranks };
  });
  const ranked = r.ranks.length === 0 || r.ranks.every((t, i) => t.startsWith(`#${i + 1} by impressions`));
  if (r.bad.length || !ranked) ok = false;
  console.log(p.id, r.cards, 'cards', r.bad.length ? `BROKEN: ${r.bad.join(', ')}` : 'ok', ranked ? '' : 'OUT OF ORDER');
}
} finally {
  await browser.close();
}
console.log(ok ? 'ALL PASS' : 'FAILURES'); process.exit(ok ? 0 : 1);
