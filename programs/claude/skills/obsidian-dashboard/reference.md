# Obsidian Dashboard — technical reference

The playbook for building multi-column, widget-based Obsidian dashboards. Every
item here was learned by hitting the wall; follow it and skip the wall.

## The core technique

A dashboard is **`dataviewjs` blocks that build inline-styled HTML strings**,
arranged by the **Columns plugin**. Not markdown + a stylesheet.

Why: widgets styled with inline CSS render identically regardless of theme, and
you get full control over layout. `dv.el()`/`dv.table()` + external CSS is
fragile — selectors miss, themes override, and you spend hours chasing it.

Minimal widget:
```js
const T = dv.container;
let html = '<div class="widget"><h1>TITLE</h1>';
// ...build rows as inline-styled divs...
html += '</div>';
T.innerHTML = '<div style="display:flex;flex-direction:column;gap:8px;">' + html + '</div>';
// attach listeners AFTER setting innerHTML:
T.querySelectorAll('input').forEach(cb => cb.addEventListener('click', handler));
```

## Column layout (Columns plugin)

```
`````col            ← wrapper, 5 backticks
````col-md          ← each column, 4 backticks
```dataviewjs       ← widget code, 3 backticks
...
```
````
````col-md
...
````
`````
```

**Backtick-nesting rule (critical):** the outer fence must have MORE backticks
than anything inside it. `col` = 5, `col-md` = 4, code blocks = 3. Get this wrong
and columns render as raw text or collapse.

**One dataviewjs block per column.** Put every widget for that column inside the
single block's `innerHTML`, wrapped in a flex-gap container. This is the #1 fix
for spacing (see Gotchas).

The plugin's DOM: `.columnParent` > `.columnChild` (widgets live directly inside
`.columnChild`). Confirmed from the plugin source. Style/space via `.columnChild`.

## The three failure modes and their fixes

### 1. Gaps missing between widgets / cards touching
Cause: two separate markdown blocks (e.g. a dataviewjs widget + a raw `<div>`,
or two dataviewjs blocks) don't get a gap between them — `.columnChild` gap
doesn't reliably reach across block boundaries.

Fix: **merge everything in a column into ONE dataviewjs block**, build all
widgets as HTML, and wrap them together:
```js
T.innerHTML = '<div style="display:flex;flex-direction:column;gap:8px;">'
  + widgetA + widgetB + widgetC + '</div>';
```
Also set on the column child in CSS:
```css
.YOURCLASS .columnParent .columnChild { display:flex; flex-direction:column; gap:8px; }
```

### 2. Dashboard not full-width (narrow, centered)
Cause: Obsidian's "Readable line length" caps width.

Fix (belt + suspenders):
- Frontmatter `custom-width: 90` (Custom Note Width plugin; its `data.json`
  needs `enablePerNoteWidth:true` and `yamlKey:"custom-width"`).
- CSS override, high specificity + `!important`, targeting every width element,
  including a `:has()` selector so it works whatever element the cssclass lands on:
```css
.YOURCLASS .markdown-preview-sizer,
.markdown-reading-view:has(.YOURCLASS) .markdown-preview-sizer,
.YOURCLASS .cm-sizer,
.YOURCLASS .markdown-source-view.mod-cm6 .cm-content {
  max-width: none !important; width: 100% !important; margin: 0 !important;
  padding-left: 12px !important; padding-right: 12px !important;
}
```

### 3. Fonts not loading (ERR_FILE_NOT_FOUND)
Cause: `@font-face` with relative `../../path` doesn't resolve in Obsidian's CSS
sandbox (especially with `_`-folders or spaces in the path).

Fix: put the `.ttf`/`.woff` files **IN `.obsidian/snippets/`** and reference by
bare filename:
```css
@font-face { font-family:"MyFont"; src:url("MyFont.ttf") format("truetype"); }
```
Confirm in DevTools console — a red `ERR_FILE_NOT_FOUND: Font.ttf` means the path
is wrong. Fonts fail silently to the default, so you can't tell by eye.

## Other widget gotchas

- **Lists (`<ul>`/`<li>`) don't fill width** like `<div>` widgets — Obsidian adds
  list inset. Force `width:100%` on the container, `ul`, AND `li`, and kill the
  marker: `li::marker{content:""}` + `list-style:none`. Prefer building rows as
  `<div>`s over `<ul>` to avoid this entirely.
- **Clean task text**: `t.text` includes `[[links]]`, `#tags`, and priority/date
  emoji. Strip for display:
  `.replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g,"$2").replace(/\[\[([^\]]+)\]\]/g,"$1").replace(/#[\w/-]+/g,"").replace(/[🔺⏫🔼🔽🔁]/g,"").replace(/[📅⏳🛫✅]\s?\d{4}-\d{2}-\d{2}/g,"").replace(/\s+/g," ").trim()`
- **Click-to-open** from a widget: `onclick="app.workspace.openLinkText('PATH','',false)"`
  (escape single quotes in PATH). For write-back on a checkbox, read the file,
  splice the line, `app.vault.modify(...)`.
- **Interactive habit/toggle widget**: store state in a per-day note's frontmatter
  (`Habit: true/false`), read with a regex, write back on click. Auto-create the
  day-note if missing.
- **Scope every query** to exclude noise: keep a `NOISE = ["_Templates","_Scripts",
  "_Experiments",".obsidian", ...]` array and `.where(p => !NOISE.some(x =>
  p.file.path.includes(x)))`. Otherwise templates/experiments pollute counts.
- **Dataview `dv.pages(source)` string exclusion is unreliable** — a bad source
  expression silently returns ALL pages. Do exclusion in JS `.where()`, not in the
  source string.
- **Lazy-load is inherent**: Dataview renders blocks async, so widgets pop in
  after page load. Can't eliminate (short of static content); reduce by using
  in-memory lookups (`getAbstractFileByPath`) over file reads where possible.
- **No `Date.now()` issues here** (that's a workflow-script constraint) — regular
  `new Date()` is fine inside dataviewjs.

## Applying changes — the reload workflow (biggest time-sink if forgotten)

Obsidian caches these; edits do NOT hot-reload. After changing:
- **A CSS snippet** → Settings → Appearance → CSS snippets → toggle the snippet
  OFF then ON. (Or the reload-snippets button.) Editing the `.css` alone does nothing visible.
- **A plugin's `data.json`** (e.g. Custom Note Width config) → toggle the plugin
  OFF/ON in Community plugins, or restart Obsidian. It reads config at load only.
- **A dataviewjs block in the note** → just reopen/reload the note (no toggle needed).
- **Fonts / `@font-face`** → reload the snippet (see fonts gotcha).

When a fix "doesn't work," 80% of the time it's actually applied but not reloaded.
Tell the user the exact toggle every time you change CSS or plugin config.

## Custom Note Width — full setup (it ships DISABLED)

The plugin (0skater0) ships with per-note width OFF and often no `data.json` at
all, so `custom-width:` frontmatter is ignored until you configure it. Write
`.obsidian/plugins/custom-note-width/data.json` with at least:
```json
{ "yamlKey": "custom-width", "enablePerNoteWidth": true, "defaultWidth": 50, "defaultWidthUnit": "%" }
```
then toggle the plugin off/on. Because the CSS snippet ALSO forces full width,
treat this plugin as optional polish — if the CSS override is present, width
works even without it.

## Dataview data reference (the `p.file.*` and `t.*` properties you'll reach for)

Page (`p` from `dv.pages()`):
- `p.file.name` `p.file.path` `p.file.folder` `p.file.link`
- `p.file.mtime` `p.file.ctime` (luxon DateTimes; `.ts` for epoch ms)
- `p.file.size` (bytes) · `p.file.tags` (incl. nested) · `p.file.etags` (exact tags)
- `p.file.inlinks` / `p.file.outlinks` (link arrays — use for orphan detection:
  `inlinks.length===0 && outlinks.length===0`)
- `p.file.tasks` · `p.file.lists` · any frontmatter key as `p.<key>`

Task (`t` from `.file.tasks`):
- `t.text` (raw, includes links/tags/emoji — clean before display) · `t.completed`
- `t.path` `t.line` (for jump/write-back) · `t.due` `t.scheduled` (if Tasks plugin
  metadata present) · `t.tags` · `t.section`

DataArray methods: `.where(fn)` `.map(fn)` `.sort(fn,"asc"|"desc")` `.slice(a,b)`
`.length` `.array()` (to plain JS array) `.filter(fn)`. Chain freely.

Useful widget computations: counts (`.length`), rollups (`.array().reduce`),
progress % (done/(open+done)), top-N folders (tally `p.file.folder`), stale notes
(sort by `mtime` asc), orphans (in/outlinks empty), tag frequency (`etags` tally).

## Meta-lesson: don't guess — inspect

When layout/CSS is wrong, DON'T iterate blindly on selectors from a screenshot.
- **Read the plugin's `main.js`** for real class names: `grep -oE 'cls:"[a-zA-Z]+"'
  .obsidian/plugins/<id>/main.js`. (That's how we confirmed `.columnParent`/`.columnChild`.)
- **Use DevTools** (Cmd+Opt+I): console shows font/query errors; Elements shows the
  real DOM nesting and which rule wins. One inspection beats five guesses.
- Ask the user to paste `[...document.querySelectorAll('.YOURCLASS .columnChild')][0].outerHTML`
  if you need the exact structure. (Note: `copy()` in console returns `undefined` —
  that's normal, it still copies to clipboard.)

## Make it PROFESSIONAL, not just correct (do this by default)

Plain label/number rows render as bare, ugly boxes. A functional dashboard is not
a finished one. Apply these polish patterns unless the user wants minimal:

- **Big-number stat tiles**, not text rows: icon + large bold number (accent
  color) + small uppercase label, in a 2×2 grid, each with a colored left border.
- **Hover states on everything interactive**: rows lift/slide (`transform:
  translateX(3px)` or `translateY(-2px)`) and change background; reveal a `→`
  arrow on hover. Makes it feel alive and clickable.
- **Visual data, not just numbers**: completion ring (conic-gradient donut),
  labeled progress bars (gradient fill), sparkline/chart for trends. A ring or bar
  reads instantly; a raw number doesn't.
- **Hierarchy**: emoji/icon in each `<h1>` heading, a small muted `.sub` caption
  under headings, count `.badge` pills next to titles, `.empty` states with a
  friendly message + emoji instead of blank.
- **Color system**: define `--color-blue/green/purple/orange/red` vars (with hex
  fallbacks) and assign per widget so it's not monochrome. Pass via inline
  `style="--a:var(--color-green)"` and consume in CSS.
- **A hero element**: lead a column with one large focal widget (the ring, a
  headline metric) so the eye has an anchor.
- **Banner/image** (optional): a header image with `border-radius` gives instant
  polish. Images go somewhere excluded from publishing.
- **Consistent spacing**: 10px gap between widgets, 8–12px padding inside, 12–16px
  border-radius. Tiles/rows on `--background-primary` inside `--code-background`
  cards for layered depth.

Copy-paste CSS for these (tile-grid, ring, hover row, badge, sub, bar) lives in
`lib/widgets.md` → "Professional polish CSS". The Vault Health dashboard in
`~/src/notes/_Experiments/Vault Health.md` is the worked example.

## Style Settings integration (optional)

Add a `/* @settings */` YAML comment block to the snippet to expose color/radius
sliders in the Style Settings plugin UI. Lets the user retune without editing CSS.

## Publishing / sandbox note

In a default-private published vault, `_`-prefixed folders with no `publish`
frontmatter stay private — good for experimental dashboards. Fonts/images used
only by the dashboard should live somewhere excluded from publishing.

## Reference implementation

A full worked example lives in the user's vault at `~/src/notes/_Experiments/`
(`Launchpad.md` + `.obsidian/snippets/launchpad-exp.css`), cloned/adapted from
github.com/Nighty3098/OBSIDIAN_SECOND_BRAIN. That repo is the canonical source
for the inline-HTML-widget + Columns technique.
