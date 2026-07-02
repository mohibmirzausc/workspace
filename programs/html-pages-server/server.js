#!/usr/bin/env node
// html-pages-server — an always-on local gallery for pages produced by the
// `html-page` Claude skill. Zero dependencies (Node stdlib only).
//
// Serves ~/html-pages/ (override with $HTML_PAGES_DIR) on $PORT (default 7777):
//   GET  /                  live gallery: every <dir>/index.html, date-desc,
//                           searchable, with sort/theme controls (localStorage).
//   GET  /pages/<dir>/...   serve a page and its assets (lib/, images).
//   POST /api/comment       persist an LLM comment into a page (Scott's
//                           notes-comments.js read-mode contract).
//   GET  /api/reload-events SSE; emits `reload` on any .html/.css/.js change.
//   GET  /healthz           -> "ok".
//
// The gallery scans the directory LIVE on every request, so it never goes stale
// and does not depend on the skill regenerating a static index.html.

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const ROOT = process.env.HTML_PAGES_DIR
  ? path.resolve(process.env.HTML_PAGES_DIR)
  : path.join(os.homedir(), 'html-pages');
const PORT = parseInt(process.env.PORT || '7777', 10);

// ── Metadata extraction ────────────────────────────────────────────────────
// Pages carry a "stamp" (style name, keywords, recreate prompt). The skill lets
// the stamp's markup harmonize with each page's design, so we extract
// best-effort with several tolerant patterns and degrade to title-only.

function firstMatch(html, patterns) {
  for (const re of patterns) {
    const m = html.match(re);
    if (m && m[1]) return decodeEntities(m[1].replace(/<[^>]+>/g, '').trim());
  }
  return '';
}

function decodeEntities(s) {
  return s
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&middot;/g, '·')
    .replace(/&nbsp;/g, ' ');
}

function extractMeta(html, dirName, mtime) {
  const title =
    firstMatch(html, [/<title[^>]*>([\s\S]*?)<\/title>/i]) ||
    firstMatch(html, [/<h1[^>]*>([\s\S]*?)<\/h1>/i]) ||
    dirName;

  // The stamp carries style/keywords/recreate. It comes in two common shapes:
  //   (a) a definition list:   <dt>Style</dt><dd>…</dd>  (current skill format)
  //   (b) a `.stamp` card:     <h5>Style</h5><.kw>…</.kw><.rp>…</.rp>
  // Scope to the stamp block first when present, so headings/keywords elsewhere
  // on the page can't be mistaken for the stamp. data-* attributes win if set.
  const stampMatch = html.match(/class\s*=\s*["'][^"']*\bstamp\b[^"']*["'][\s\S]*?<\/details>/i);
  const stamp = stampMatch ? stampMatch[0] : '';

  // Style: data-style wins; else <dt>Style</dt> anywhere; else first heading
  // INSIDE the stamp card (only when a stamp exists — avoids grabbing the page's
  // own <h1> on stampless pages).
  const style = firstMatch(html, [/data-style\s*=\s*["']([^"']+)["']/i]) ||
    firstMatch(html, [/<dt[^>]*>\s*style\s*<\/dt>\s*<dd[^>]*>([\s\S]*?)<\/dd>/i]) ||
    firstMatch(stamp, [/<h[1-6][^>]*>([\s\S]*?)<\/h[1-6]>/i]);

  const keywords = firstMatch(html, [/data-keywords\s*=\s*["']([^"']+)["']/i]) ||
    firstMatch(html, [/<dt[^>]*>\s*keywords\s*<\/dt>\s*<dd[^>]*>([\s\S]*?)<\/dd>/i]) ||
    firstMatch(stamp, [/class\s*=\s*["'][^"']*\bkw\b[^"']*["'][^>]*>([\s\S]*?)<\//i]);

  const recreate = firstMatch(html, [/data-recreate\s*=\s*["']([^"']+)["']/i]) ||
    firstMatch(html, [/<dt[^>]*>\s*recreate(?:\s*prompt)?\s*<\/dt>\s*<dd[^>]*>([\s\S]*?)<\/dd>/i]) ||
    firstMatch(stamp, [/class\s*=\s*["'][^"']*\brp\b[^"']*["'][^>]*>([\s\S]*?)<\//i]);

  // Date: leading YYYY-MM-DD in the folder name, else file mtime (YYYY-MM-DD).
  const dm = dirName.match(/^(\d{4}-\d{2}-\d{2})/);
  const date = dm ? dm[1] : mtime.toISOString().slice(0, 10);

  return { title, style, keywords, recreate, date };
}

// Per-page metadata cache, keyed by dir name → { mtimeMs, meta }. Pages are
// only re-read/re-parsed when their index.html mtime changes, so listing stays
// O(pages) on stat() rather than O(pages) on read()+regex every request.
const metaCache = new Map();

// Resolve one page's metadata. Prefers a `meta.json` sidecar (deterministic,
// written by the skill); falls back to regex extraction from the HTML.
function readPageMeta(dirName, indexPath, stat) {
  const cached = metaCache.get(dirName);
  if (cached && cached.mtimeMs === stat.mtimeMs) return cached.meta;

  let meta = null;

  // 1) Sidecar: ~/html-pages/<dir>/meta.json — { style, keywords, recreate, title? }
  try {
    const sidecar = JSON.parse(fs.readFileSync(path.join(ROOT, dirName, 'meta.json'), 'utf8'));
    const dm = dirName.match(/^(\d{4}-\d{2}-\d{2})/);
    // Coerce every field to a string. The client renderer assumes strings; a
    // sidecar that (understandably) writes keywords as an array — or any other
    // non-string — would otherwise blow up esc() and blank the WHOLE gallery.
    const str = (v) => Array.isArray(v) ? v.filter(Boolean).join(' · ')
      : (v == null ? '' : String(v));
    meta = {
      title: str(sidecar.title) || extractTitleOnly(indexPath) || dirName,
      style: str(sidecar.style),
      keywords: str(sidecar.keywords),
      recreate: str(sidecar.recreate) || str(sidecar.recreatePrompt),
      date: str(sidecar.date) || (dm ? dm[1] : stat.mtime.toISOString().slice(0, 10)),
    };
  } catch { /* no/invalid sidecar → fall through to regex */ }

  // 2) Regex fallback: parse the HTML stamp.
  if (!meta) {
    let html = '';
    try { html = fs.readFileSync(indexPath, 'utf8'); } catch { /* ignore */ }
    meta = extractMeta(html, dirName, stat.mtime);
  }

  metaCache.set(dirName, { mtimeMs: stat.mtimeMs, meta });
  return meta;
}

// Cheap title-only read for when a sidecar omits the title.
function extractTitleOnly(indexPath) {
  try {
    const html = fs.readFileSync(indexPath, 'utf8');
    return firstMatch(html, [/<title[^>]*>([\s\S]*?)<\/title>/i, /<h1[^>]*>([\s\S]*?)<\/h1>/i]);
  } catch { return ''; }
}

function listPages() {
  let entries;
  try {
    entries = fs.readdirSync(ROOT, { withFileTypes: true });
  } catch {
    return [];
  }
  const pages = [];
  for (const ent of entries) {
    if (!ent.isDirectory()) continue;
    const indexPath = path.join(ROOT, ent.name, 'index.html');
    let stat;
    try { stat = fs.statSync(indexPath); } catch { continue; }
    const meta = readPageMeta(ent.name, indexPath, stat);
    pages.push({ dir: ent.name, ...meta, mtime: stat.mtimeMs });
  }
  // Default order: date descending, then mtime descending as tiebreak.
  pages.sort((a, b) =>
    b.date.localeCompare(a.date) || (b.mtime - a.mtime));
  return pages;
}

// ── Gallery HTML ─────────────────────────────────────────────────────────────

function esc(s) {
  return String(s || '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function galleryHtml() {
  const pages = listPages();
  const data = JSON.stringify(pages);
  const count = pages.length;
  return `<!doctype html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>HTML Pages</title>
<style>
  :root {
    --bg: #faf8f3; --fg: #221c14; --muted: #6d5f4d; --rule: #e4dcc6;
    --card: #fff; --accent: #af3a03; --chip: #efe8d6;
  }
  [data-theme="dark"] {
    --bg: #16140f; --fg: #ece4d3; --muted: #9b8f78; --rule: #2c281e;
    --card: #1e1b14; --accent: #e07a3c; --chip: #2a2519;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--bg); color: var(--fg);
    font: 16px/1.55 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  header {
    position: sticky; top: 0; z-index: 10; background: var(--bg);
    border-bottom: 1px solid var(--rule);
    padding: 1.1rem clamp(1rem, 4vw, 3rem); display: flex; gap: 1rem;
    align-items: center; flex-wrap: wrap;
  }
  h1 { font-size: 1.15rem; margin: 0; letter-spacing: -0.01em; white-space: nowrap; }
  .count { color: var(--muted); font-size: .85rem; }
  .grow { flex: 1 1 auto; }
  input[type=search], select {
    font: inherit; padding: .5rem .7rem; border: 1px solid var(--rule);
    border-radius: 8px; background: var(--card); color: var(--fg);
  }
  input[type=search] { min-width: min(420px, 60vw); }
  button.ghost, a.ghost {
    font: inherit; padding: .5rem .7rem; border: 1px solid var(--rule);
    border-radius: 8px; background: var(--card); color: var(--fg); cursor: pointer;
    text-decoration: none; display: inline-block;
  }
  a.ghost:hover { border-color: var(--accent); color: var(--accent); }
  main { padding: clamp(1rem, 4vw, 3rem); }
  .grid {
    display: grid; gap: 1rem;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  }
  body.compact .grid { grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); }
  .card {
    display: flex; flex-direction: column; gap: .5rem; text-decoration: none;
    color: inherit; background: var(--card); border: 1px solid var(--rule);
    border-radius: 12px; padding: 1rem 1.1rem; transition: transform .08s, border-color .12s;
  }
  .card:hover { transform: translateY(-2px); border-color: var(--accent); }
  .card h2 { margin: 0; font-size: 1.02rem; line-height: 1.3; }
  .meta { color: var(--muted); font-size: .82rem; display: flex; gap: .6rem; flex-wrap: wrap; }
  .style { display: inline-block; font-size: .78rem; color: var(--accent);
           border: 1px solid var(--accent); border-radius: 999px; padding: .05rem .55rem;
           width: fit-content; cursor: pointer; background: transparent; }
  .style:hover { background: var(--accent); color: var(--bg); }
  .kw { color: var(--muted); font-size: .8rem; }
  .recreate { margin-top: .15rem; font-size: .74rem; color: var(--muted);
              border-left: 2px solid var(--rule); padding-left: .55rem; display: none; }
  body.show-prompts .recreate { display: block; }
  .copy { align-self: flex-start; font-size: .72rem; padding: .15rem .45rem; margin-top: .1rem;
          border: 1px solid var(--rule); border-radius: 6px; background: transparent;
          color: var(--muted); cursor: pointer; display: none; }
  body.show-prompts .copy { display: inline-block; }
  .copy:hover { color: var(--accent); border-color: var(--accent); }
  .empty { color: var(--muted); padding: 3rem 0; text-align: center; }
  code { background: var(--chip); padding: .05rem .3rem; border-radius: 4px; font-size: .85em; }
</style>
</head>
<body>
<header>
  <h1>HTML Pages</h1>
  <span class="count" id="count">${count} page${count === 1 ? '' : 's'}</span>
  <span class="grow"></span>
  <input type="search" id="q" placeholder="Search title, style, keywords, date…" autofocus>
  <select id="sort" title="Sort">
    <option value="date-desc">Newest first</option>
    <option value="date-asc">Oldest first</option>
    <option value="title">Title A–Z</option>
    <option value="style">Style A–Z</option>
  </select>
  <button class="ghost" id="prompts" title="Show recreate prompts">✎ prompts</button>
  <button class="ghost" id="density" title="Toggle density">▦ density</button>
  <button class="ghost" id="theme" title="Toggle theme">◐ theme</button>
  <a class="ghost" href="/styles" title="Browse every style you've seen">✦ styles</a>
</header>
<main>
  <div class="grid" id="grid"></div>
  <div class="empty" id="empty" hidden>No pages yet. Ask Claude to generate one — it lands in <code>${esc(ROOT)}</code>.</div>
</main>
<script>
  const PAGES = ${data};
  const $ = (id) => document.getElementById(id);
  const grid = $('grid'), empty = $('empty');

  // Restore preferences.
  const pref = {
    sort: localStorage.getItem('hp.sort') || 'date-desc',
    theme: localStorage.getItem('hp.theme') || 'dark',
    compact: localStorage.getItem('hp.compact') === '1',
    prompts: localStorage.getItem('hp.prompts') === '1',
  };
  $('sort').value = pref.sort;
  document.documentElement.dataset.theme = pref.theme;
  document.body.classList.toggle('compact', pref.compact);
  document.body.classList.toggle('show-prompts', pref.prompts);

  function sorted(list) {
    const s = $('sort').value;
    const c = [...list];
    if (s === 'date-desc') c.sort((a,b)=> b.date.localeCompare(a.date) || b.mtime-a.mtime);
    else if (s === 'date-asc') c.sort((a,b)=> a.date.localeCompare(b.date) || a.mtime-b.mtime);
    else if (s === 'title') c.sort((a,b)=> (a.title||'').localeCompare(b.title||''));
    else if (s === 'style') c.sort((a,b)=> (a.style||'').localeCompare(b.style||''));
    return c;
  }

  function render() {
    const q = $('q').value.trim().toLowerCase();
    let list = PAGES.filter(p => {
      if (!q) return true;
      return [p.title, p.style, p.keywords, p.date, p.dir]
        .join(' ').toLowerCase().includes(q);
    });
    list = sorted(list);
    $('count').textContent = list.length + (list.length === 1 ? ' page' : ' pages');
    grid.innerHTML = '';
    empty.hidden = PAGES.length !== 0;
    for (const p of list) {
      const a = document.createElement('a');
      a.className = 'card';
      a.href = '/pages/' + encodeURIComponent(p.dir) + '/';
      const esc = (s) => String(s ?? '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
      a.innerHTML =
        '<h2>' + esc(p.title) + '</h2>' +
        '<div class="meta"><span>' + esc(p.date) + '</span></div>' +
        (p.style ? '<span class="style" data-style="' + esc(p.style) + '" title="Filter by this style">' + esc(p.style) + '</span>' : '') +
        (p.keywords ? '<div class="kw">' + esc(p.keywords) + '</div>' : '') +
        (p.recreate ? '<div class="recreate">' + esc(p.recreate) + '</div>' : '') +
        (p.recreate ? '<button class="copy" type="button" data-p="' + esc(p.recreate) + '">⧉ copy prompt</button>' : '');
      grid.appendChild(a);
    }
    // Click a style chip → filter to that style (without opening the card).
    grid.querySelectorAll('.style').forEach(chip => chip.addEventListener('click', e => {
      e.preventDefault(); e.stopPropagation();
      $('q').value = chip.dataset.style; render();
    }));
    // Copy the recreate prompt (without opening the card).
    grid.querySelectorAll('.copy').forEach(btn => btn.addEventListener('click', e => {
      e.preventDefault(); e.stopPropagation();
      navigator.clipboard.writeText(btn.dataset.p);
      const t = btn.textContent; btn.textContent = '✓ copied'; setTimeout(() => btn.textContent = t, 1200);
    }));
  }

  $('q').addEventListener('input', render);
  $('sort').addEventListener('change', () => { localStorage.setItem('hp.sort', $('sort').value); render(); });
  $('theme').addEventListener('click', () => {
    const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    document.documentElement.dataset.theme = next; localStorage.setItem('hp.theme', next);
  });
  $('density').addEventListener('click', () => {
    const on = document.body.classList.toggle('compact');
    localStorage.setItem('hp.compact', on ? '1' : '0');
  });
  $('prompts').addEventListener('click', () => {
    const on = document.body.classList.toggle('show-prompts');
    localStorage.setItem('hp.prompts', on ? '1' : '0');
  });

  render();

  // Live reload: refresh the gallery when any page changes on disk.
  try {
    const es = new EventSource('/api/reload-events');
    es.addEventListener('message', e => { if (e.data === 'reload') location.reload(); });
  } catch {}
</script>
</body>
</html>`;
}

// ── Styles encyclopedia ──────────────────────────────────────────────────────
// Aggregates every page by style → a personal design encyclopedia: each style
// you've ever used, its keywords, how often, when, and links to examples.

function stylesHtml() {
  const pages = listPages();
  const byStyle = new Map();
  for (const p of pages) {
    const name = (p.style || '(unstamped)').trim();
    if (!byStyle.has(name)) {
      byStyle.set(name, { style: name, keywords: p.keywords || '', recreate: p.recreate || '',
                          count: 0, first: p.date, last: p.date, examples: [] });
    }
    const s = byStyle.get(name);
    s.count++;
    if (p.date < s.first) s.first = p.date;
    if (p.date > s.last) s.last = p.date;
    if (!s.keywords && p.keywords) s.keywords = p.keywords;
    if (!s.recreate && p.recreate) s.recreate = p.recreate;
    s.examples.push({ dir: p.dir, title: p.title });
  }
  const styles = [...byStyle.values()].sort((a, b) =>
    b.count - a.count || a.style.localeCompare(b.style));
  const data = JSON.stringify(styles);
  const total = styles.filter(s => s.style !== '(unstamped)').length;

  return `<!doctype html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Styles I've Seen</title>
<style>
  :root { --bg:#faf8f3; --fg:#221c14; --muted:#6d5f4d; --rule:#e4dcc6; --card:#fff; --accent:#af3a03; --chip:#efe8d6; }
  [data-theme="dark"] { --bg:#16140f; --fg:#ece4d3; --muted:#9b8f78; --rule:#2c281e; --card:#1e1b14; --accent:#e07a3c; --chip:#2a2519; }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--fg); font:16px/1.55 ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif; -webkit-font-smoothing:antialiased; }
  header { position:sticky; top:0; z-index:10; background:var(--bg); border-bottom:1px solid var(--rule); padding:1.1rem clamp(1rem,4vw,3rem); display:flex; gap:1rem; align-items:center; flex-wrap:wrap; }
  h1 { font-size:1.15rem; margin:0; letter-spacing:-.01em; }
  .count { color:var(--muted); font-size:.85rem; }
  .grow { flex:1 1 auto; }
  a.nav, button.ghost { font:inherit; padding:.5rem .7rem; border:1px solid var(--rule); border-radius:8px; background:var(--card); color:var(--fg); cursor:pointer; text-decoration:none; }
  input[type=search] { font:inherit; padding:.5rem .7rem; border:1px solid var(--rule); border-radius:8px; background:var(--card); color:var(--fg); min-width:min(360px,55vw); }
  main { padding:clamp(1rem,4vw,3rem); display:grid; gap:1rem; grid-template-columns:repeat(auto-fill,minmax(330px,1fr)); }
  .scard { background:var(--card); border:1px solid var(--rule); border-radius:12px; padding:1.1rem 1.2rem; display:flex; flex-direction:column; gap:.55rem; }
  .scard h2 { margin:0; font-size:1.05rem; display:flex; align-items:baseline; gap:.5rem; }
  .badge { font-size:.72rem; color:var(--bg); background:var(--accent); border-radius:999px; padding:.05rem .5rem; }
  .kw { color:var(--muted); font-size:.85rem; }
  .seen { color:var(--muted); font-size:.76rem; }
  .recreate { font-size:.78rem; color:var(--muted); border-left:2px solid var(--rule); padding-left:.6rem; }
  .ex { display:flex; flex-wrap:wrap; gap:.4rem; }
  .ex a { font-size:.76rem; color:var(--accent); text-decoration:none; border:1px solid var(--rule); border-radius:6px; padding:.1rem .45rem; }
  .ex a:hover { border-color:var(--accent); }
  .copy { align-self:flex-start; font-size:.74rem; padding:.2rem .5rem; border:1px solid var(--rule); border-radius:6px; background:transparent; color:var(--muted); cursor:pointer; }
  .copy:hover { color:var(--accent); border-color:var(--accent); }
  .empty { color:var(--muted); padding:3rem 0; text-align:center; grid-column:1/-1; }
</style>
</head>
<body>
<header>
  <h1>Styles I've Seen</h1>
  <span class="count">${total} distinct style${total === 1 ? '' : 's'}</span>
  <span class="grow"></span>
  <input type="search" id="q" placeholder="Filter styles…">
  <a class="nav" href="/">← gallery</a>
  <button class="ghost" id="theme" title="Toggle theme">◐ theme</button>
</header>
<main id="grid"></main>
<script>
  const STYLES = ${data};
  const $ = (id) => document.getElementById(id);
  const grid = $('grid');
  const esc = (s) => (s||'').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

  document.documentElement.dataset.theme = localStorage.getItem('hp.theme') || 'dark';
  $('theme').onclick = () => {
    const n = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    document.documentElement.dataset.theme = n; localStorage.setItem('hp.theme', n);
  };

  function render() {
    const q = $('q').value.trim().toLowerCase();
    const list = STYLES.filter(s => !q || (s.style + ' ' + s.keywords).toLowerCase().includes(q));
    grid.innerHTML = list.length ? '' : '<div class="empty">No styles yet — generate a page.</div>';
    for (const s of list) {
      const seen = s.first === s.last ? s.first : s.first + ' → ' + s.last;
      const ex = s.examples.slice(0, 6).map(e =>
        '<a href="/pages/' + encodeURIComponent(e.dir) + '/">' + esc(e.title || e.dir) + '</a>').join('');
      const el = document.createElement('div');
      el.className = 'scard';
      el.innerHTML =
        '<h2>' + esc(s.style) + ' <span class="badge">' + s.count + '×</span></h2>' +
        (s.keywords ? '<div class="kw">' + esc(s.keywords) + '</div>' : '') +
        '<div class="seen">seen ' + esc(seen) + '</div>' +
        (s.recreate ? '<div class="recreate">' + esc(s.recreate) + '</div>' : '') +
        (s.recreate ? '<button class="copy" data-p="' + esc(s.recreate) + '">⧉ copy recreate prompt</button>' : '') +
        '<div class="ex">' + ex + '</div>';
      grid.appendChild(el);
    }
    grid.querySelectorAll('.copy').forEach(b => b.onclick = () => {
      navigator.clipboard.writeText(b.dataset.p);
      const t = b.textContent; b.textContent = '✓ copied'; setTimeout(() => b.textContent = t, 1200);
    });
  }
  $('q').addEventListener('input', render);
  render();
  try { const es = new EventSource('/api/reload-events'); es.onmessage = e => { if (e.data === 'reload') location.reload(); }; } catch {}
</script>
</body>
</html>`;
}

// ── File serving ─────────────────────────────────────────────────────────────

const MIME = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif',
  '.webp': 'image/webp', '.ico': 'image/x-icon', '.woff': 'font/woff',
  '.woff2': 'font/woff2', '.txt': 'text/plain; charset=utf-8',
};

function serveFile(res, absPath) {
  // Containment check: never serve outside ROOT.
  const resolved = path.resolve(absPath);
  if (resolved !== ROOT && !resolved.startsWith(ROOT + path.sep)) {
    res.writeHead(403); res.end('forbidden'); return;
  }
  let stat;
  try { stat = fs.statSync(resolved); } catch { res.writeHead(404); res.end('not found'); return; }
  let file = resolved;
  if (stat.isDirectory()) file = path.join(resolved, 'index.html');
  fs.readFile(file, (err, buf) => {
    if (err) { res.writeHead(404); res.end('not found'); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream' });
    res.end(buf);
  });
}

// ── Comment persistence (notes-comments.js read-mode contract) ───────────────
// Body: { file, signature: {tag, text}, comment }. We insert an HTML comment
// `<!-- LLM: comment -->` immediately before the first element whose opening tag
// matches `tag` and whose text starts with signature.text — so on reload the
// client renders the ✎ marker against that element.

function saveComment(body, cb) {
  let payload;
  try { payload = JSON.parse(body); } catch { return cb(new Error('bad json')); }
  const { file, signature, comment } = payload || {};
  if (!file || !signature || !comment) return cb(new Error('missing fields'));

  // `file` is the page's request path, e.g. /pages/<dir>/ or /pages/<dir>/index.html
  const rel = decodeURIComponent(file).replace(/^\/pages\//, '');
  let abs = path.resolve(ROOT, rel);
  if (abs !== ROOT && !abs.startsWith(ROOT + path.sep)) return cb(new Error('forbidden'));
  if (abs.endsWith('/') || (fs.existsSync(abs) && fs.statSync(abs).isDirectory())) {
    abs = path.join(abs, 'index.html');
  }

  let html;
  try { html = fs.readFileSync(abs, 'utf8'); } catch { return cb(new Error('page not found')); }

  const tag = String(signature.tag || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  const sigText = String(signature.text || '').replace(/\s+/g, ' ').trim().slice(0, 40);
  if (!tag) return cb(new Error('bad signature'));

  // Find the opening tag of `tag` whose following text contains the signature.
  const openRe = new RegExp('<' + tag + '(\\s[^>]*)?>', 'gi');
  let m, insertAt = -1;
  while ((m = openRe.exec(html)) !== null) {
    const after = html.slice(m.index, m.index + 400).replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
    if (!sigText || after.includes(sigText.slice(0, 24))) { insertAt = m.index; break; }
  }
  if (insertAt === -1) return cb(new Error('element not found for signature'));

  const safe = comment.replace(/--+/g, '–'); // keep HTML comments well-formed
  const marker = '<!-- LLM: ' + safe + ' -->\n';
  const out = html.slice(0, insertAt) + marker + html.slice(insertAt);
  fs.writeFile(abs, out, (err) => err ? cb(err) : cb(null));
}

// ── SSE live reload ──────────────────────────────────────────────────────────

const sseClients = new Set();
function broadcastReload() {
  for (const res of sseClients) { try { res.write('data: reload\n\n'); } catch {} }
}
let watchTimer = null;
try {
  fs.watch(ROOT, { recursive: true }, (_evt, filename) => {
    if (filename && !/\.(html|css|js|mjs|json)$/i.test(filename)) return;
    metaCache.clear();                 // drop stale/deleted entries; pages re-parse lazily
    clearTimeout(watchTimer);
    watchTimer = setTimeout(broadcastReload, 120); // debounce bursts
  });
} catch (e) {
  console.error('fs.watch failed (live reload disabled):', e.message);
}

// ── HTTP server ──────────────────────────────────────────────────────────────

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const pathname = decodeURIComponent(url.pathname);

  if (pathname === '/healthz') { res.writeHead(200); res.end('ok'); return; }

  if (pathname === '/api/reload-events') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
    });
    res.write('retry: 2000\n\n');
    sseClients.add(res);
    req.on('close', () => sseClients.delete(res));
    return;
  }

  if (pathname === '/api/comment' && req.method === 'POST') {
    let body = '';
    req.on('data', c => { body += c; if (body.length > 1e6) req.destroy(); });
    req.on('end', () => saveComment(body, (err) => {
      if (err) { res.writeHead(400); res.end(err.message); }
      else { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end('{"ok":true}'); }
    }));
    return;
  }

  if (pathname === '/' || pathname === '/index.html') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(galleryHtml());
    return;
  }

  if (pathname === '/styles') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(stylesHtml());
    return;
  }

  if (pathname.startsWith('/pages/')) {
    const rel = pathname.slice('/pages/'.length);
    serveFile(res, path.join(ROOT, rel));
    return;
  }

  res.writeHead(404); res.end('not found');
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`html-pages-server: serving ${ROOT} at http://localhost:${PORT}`);
});
