# Adding or refreshing a competitor (and its ads)

A competitor is a `product` node, linked `is-a` to the `alternative` (kind) it represents. See
`<lens>/README.md` › Products for the schema; `build.mjs` enforces it. Work in this order; each step
writes only where it says, so a half-finished run never breaks the lens.

The scripts read the lens folder from `$LENS_DIR` (relative to the repo root), else `docs/lens`.
`$SKILL` is this skill's folder (`.claude/skills/lens` or `~/.claude/skills/lens`).

## 0. What the product is

Compare against the lens, never the product's marketing page: `model.json`'s `purpose`, the
`focus` hypotheses, the surfaces and ideas. Every "vs us" line is a `hypothesis` claim (Untested).

## 1. Research (one agent per product, in parallel when there are several)

Write `tmp/competitors/<id>.json`:

```json
{ "id": "<slug>", "name": "…", "url": "<homepage>",
  "pitch": { "quote": "<verbatim homepage line>", "source": "<url>" },
  "summary": "<2 plain sentences>",
  "pricing": { "text": "<tiers>", "source": "<pricing url>", "checked": "YYYY-MM-DD" },
  "revenue": { "text": "<self/press-reported only, 'as reported by X, date'; funding counts; third-party = estimate; else exactly 'Not public'>", "sources": ["<url>"] },
  "metaAds": { "status": "active | none | blocked | not-covered", "text": "…", "ads": [], "source": "<library url>" },
  "tiktokAds": { "status": "…", "text": "…", "ads": [], "source": "<library url>" },
  "vsUs": "<1-2 sentences against the lens's purpose>",
  "notable": [{ "text": "…", "source": "<url>" }] }
```

Record each research batch as a dated `Market research` source and point `research` at it.

Rules: never invent a number, quote or ad copy; every fact has a URL; "Not public" and "No active
… ads found" are findings. Re-check older research on the live site rather than copying it.

**Ad libraries render with JavaScript.** Check them in a real browser (Chrome DevTools MCP,
Playwright driving real Chrome with `chromium.launch({ channel: 'chrome' })` and its own profile
dir, or agent-browser). A plain fetch that returns empty or 403 is not a finding. Record `blocked`
only for a CAPTCHA, login wall or bot check seen in that browser, and never evade one (no
fingerprint/user-agent rotation, proxies or stealth plugins).
- Meta Ad Library: `https://www.facebook.com/ads/library/?active_status=active&ad_type=all&country=ALL&media_type=all&search_type=page&view_all_page_id=<page id>&sort_data[mode]=total_impressions&sort_data[direction]=desc`
  (find the page id from a keyword search first).
- TikTok Commercial Content Library: `https://library.tiktok.com/ads?region=all&adv_name=<brand>&query_type=1`.
  It only holds ads shown in the EU/EEA, the UK, CH and TR in the past year — say so with "none".

**Close every browser you start, even on failure.** Playwright: `try { … } finally { await browser.close() }`
(and `context.close()` for a persistent context). agent-browser: use your own session
(`export AGENT_BROWSER_SESSION=lens-<id>`) and end with `agent-browser close`. Chrome DevTools MCP:
close every page you opened. Never kill a browser you didn't start.

## 2. Add the product

```bash
python3 "$SKILL/scripts/add-product.py" tmp/competitors/<id>.json \
  --alternative <alternative-id> --source <source-id> \
  --entry "<short entry price>" --headline "<short revenue headline>"
```

It adds (or replaces) `pr-<id>`, links it `is-a` the named alternative, and needs an existing
`Market research` source node to cite (`--source`); add one first for a new research batch.

## 3. Capture ads (only for `active` advertisers) — staged, never in place

Capture the top 5 DISTINCT active ads in the library's highest-impressions-first order into
`tmp/competitors/ads-staging/<id>/` and `tmp/competitors/ads-staging/<id>.json`. Never write into
the lens folder during capture.

Per ad: `id` (Library ID), `url` = `https://www.facebook.com/ads/library/?id=<id>`, `started`
(YYYY-MM-DD), `rank` (1..n among kept ads), `libraryPosition`, `impressions` only if the library
shows a figure (copy exactly), `text` (verbatim, "See more" expanded), `headline` / `cta` if shown,
`image` (element screenshot of the card, saved as `<id>.png`, recorded as
`assets/ads/<product-id>/<id>.png`), `video` if a video (download that card's `<video>` src, check
with ffprobe, record `assets/ads/<product-id>/<id>.mp4`), and `analysis`:
`{ hook, themes (1-4 of: social proof, founder story, pain agitation, aspiration, urgency, free trial,
comparison, authority, humor, demo), framing, avatar (an avatar id from the model), why }`.
The staged JSON: `{ product, page, sort: "total_impressions desc", checked, summary, ads: [...] }`.

## 4. Apply, in one checked step

```bash
DRY=1 python3 "$SKILL/scripts/apply-staged-ads.py"   # checks only
python3 "$SKILL/scripts/apply-staged-ads.py"         # copies media, updates model.json,
                                                     # removes unreferenced files by exact path
```

It refuses to change anything if any staged ad fails a check. Keep videos out of git (local
playback); commit the stills.

## 5. Verify, then commit

```bash
node docs/lens/build.mjs && node --test docs/lens/tests/*.test.mjs
node "$SKILL/scripts/smoke-ads.mjs"     # needs Playwright + Chrome; serve the repo root on 127.0.0.1:8767 first
```

The smoke test opens every advertiser in real Chrome and fails unless every ad still renders, every
video loads with a duration, and cards run #1..#N by impressions. Commit `model.json`, `index.html`,
`ids.lock.json` and the stills — never `.mp4`.
