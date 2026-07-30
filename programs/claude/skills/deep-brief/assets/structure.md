# Structural devices for deep briefs

These are the **structural** patterns that produce depth. They are deliberately
style-agnostic: `html-page`'s recency rules require a *different* aesthetic on every
page, so re-skin these each time. Copying one palette across briefs is convergence —
the thing `html-page` explicitly warns against.

What matters is that each device **forces detail**. Roughly measured on the reference
brief: these devices about double word count versus plain prose over the same source,
because each one has slots that must be filled with actual content.

---

## 1. Numbered parts

```html
<section class="part" id="p7">
  <div class="part-num">07</div>
  <h2>Option 3 — the build contract</h2>
  ...
</section>
```

An oversized, low-contrast numeral (often `-webkit-text-stroke` on a paper-toned fill)
above each heading. **Why it matters:** it makes 25 sections feel navigable instead of
endless, which is what lets you *write* 25 sections without worrying the page is
punishing. Pair with `id="pN"` anchors and a full TOC.

## 2. Speaker cards — one per comment

```html
<div class="speaker">            <!-- add .re for the driver/author -->
  <div class="av">TG</div>       <!-- initials avatar -->
  <div><span class="who">Tim Goodwin</span> <span class="when">· 14 Jul, 16:30</span></div>
  <div class="said"><p>"verbatim quote, exactly as written"</p></div>
</div>
```

Grid: `auto 1fr`, avatar spanning both rows, quote in row 2 column 2. A left border
color-coded by role (author vs. commenter) reads instantly.

**Why it matters:** this is the single highest-value device. It forces you to quote
verbatim *before* analyzing, which is what lets the reader distinguish what the source
said from what you concluded. Never merge multiple speakers into one card.

## 3. Semantic callout types

Five distinct meanings, each visually distinguishable:

| Class | Means | Use for |
|-------|-------|---------|
| `.why` | explains significance | "why this matters for your read" |
| `.risk` | a danger or failure mode | consequences, things that will go wrong |
| `.aha` | the key insight | the crux; the one line to remember |
| `.gap` | nobody has addressed this | unaddressed findings, your proposals |
| `.jargon` | reading aid | glossary notes, conventions, meta |

Each carries an uppercase label (`<span class="lbl">`). **Why it matters:** typed
callouts make epistemic status visible at a glance — the reader always knows whether
they're reading the source, a commenter, or you.

## 4. Decode tables

Every "the source lists N things" becomes an N-row table with a **"what this means"**
or **"what goes wrong"** column.

```html
<table>
  <thead><tr><th>Pressure</th><th>What it is</th><th>Why it pushes on X</th></tr></thead>
  ...
</table>
```

**Why it matters:** the mechanical way to defeat glossing. A source bullet list is
compressed by its author; the table's third column forces decompression. You cannot
fill a "what this means" cell with a summary.

On mobile: `display:block; overflow-x:auto` on the table so wide tables scroll inside
their own box rather than breaking the page.

## 5. Collapsible glossary

```html
<details>
  <summary>FIPS — and why it's a <em>build-time</em> constraint</summary>
  <div class="body"><p>...</p></div>
</details>
```

**Why it matters:** solves the "explain everything without making experts scroll past
it" problem. One line collapsed, full explanation expanded. Crucially, the summary
should state **why the term is load-bearing in this document**, not just what it means —
`"FIPS — and why it's a build-time constraint"` beats `"FIPS"`.

## 6. Status chips

```html
<span class="chip settled">Settled</span>
<span class="chip open">Open</span>
<span class="chip gap">Gap</span>
<span class="chip info">Note</span>
```

Inline, `border:1.5px solid currentColor`, uppercase, tiny. Put them **in headings**
so thread status is visible from the TOC and while skimming.

## 7. Reading-progress bar + jump-to-top

```js
addEventListener("scroll",()=>{
  const h=document.documentElement;
  prog.style.width=(h.scrollTop/(h.scrollHeight-h.clientHeight||1)*100)+"%";
  topL.classList.toggle("on", h.scrollTop>900);
},{passive:true});
```

A 3px fixed bar plus a jump-to-top link that appears after ~900px.
**Why it matters:** orientation. A 15k-word page without a progress indicator feels
bottomless.

## 8. Full TOC, two columns

Every section listed, `columns:2` collapsing to 1 under ~640px.
**Why it matters:** it's the honest signal of how much is here, and it's the main
navigation for a document too long to scroll.

---

## Quality floor (non-negotiable, within any aesthetic)

Inherited from `html-page` + `intake-form`'s Fillability Floor:

- Readable contrast; long-form body text wants ~17–18px and `line-height` ~1.7
- Constrain prose to `min(74ch, 100%)` — full-width text at 1400px is unreadable
- **375px reflow with zero horizontal page overflow** (wide tables/`pre` scroll
  internally via `overflow-x:auto`)
- Tap targets ≥44px on form rows; the `<input>` dot itself may be smaller if its
  clickable parent row is ≥44px
- `@media (prefers-reduced-motion: reduce)` disabling transitions and smooth scroll
- `@media print` hiding fixed chrome and force-opening `<details>`
- The `html-page` stamp (`<dl><dt>Style/Keywords/Recreate prompt</dt>`) + `meta.json`

## Assembly reminder

Write these into separate `parts/NN-*.html` files and concatenate explicitly:

```bash
cat parts/00-head.html parts/01-orient.html ... parts/NN-form-js.html > index.html
```

`parts/00-head.html` opens `<html><head><style>…</style></head><body>` and the wrapper
divs; the final part closes `</body></html>`. Verify tag balance after concatenating —
unbalanced tags are the characteristic failure of this method.
