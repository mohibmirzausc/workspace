---
name: html-page
description: Use when the user asks to generate, build, render, or design an HTML page — turning notes, LLM output, plans, or content into a standalone .html file. Each page explores a different real-world design style (pulled from the whole world of design, not a fixed list) and stamps the style + interactivity vocabulary visibly on the page so the user learns webpage customization over time.
---

# html-page

## Overview

Turn any content (LLM output, notes, a plan, a doc) into a standalone HTML page
that ALSO teaches the user the visual vocabulary of the web. Two jobs at once:

1. **Render the content well** as a real, openable `.html` file.
2. **Explore one real-world design style per page** and **stamp its identity
   visibly on the page** — so the user sees which styles they like and can ask
   for them again. No style is bad; each is an avenue to learn something new.

**Core principle:** every page is a labeled experiment. Pull a style from
*anywhere in the world's design history* (not a fixed list), pair it with a
*fitting* interactivity pattern, make both choices **visible on the page**, and
file the page into a browsable gallery so the user can find it later.

## Workflow

1. **Read the content** the user wants rendered. Understand what it is (review
   doc? plan? reference? landing page?).
2. **Pick a style — from the whole world, not a list.** If the user named one,
   use it. Otherwise: **first do the MANDATORY recency check in `styles.md`** —
   run the one-liner that lists the last 8 pages' styles and read it BEFORE
   choosing. Do not pick from memory; you converge when you do. Then reach into
   your *entire* knowledge of design styles (movements, eras, regional traditions,
   subcultures, mediums, invented hybrids) and pick one that obeys the two hard
   rules in `styles.md`: **no repeat (or near-synonym) in the last 8 pages**, and
   **if the technical-utility family (blueprint/schematic/dossier/terminal/CI/
   transit-map) appeared in the last 5 pages, that whole family is banned.** The
   content does not dictate the aesthetic — dry content in an unexpected style is
   the point. Light/dark, serif/mono, famous/obscure — all fair.
3. **Pick an interactivity pattern** from `styles.md` that *fits the content* —
   this is a content-fit decision, NOT a random roll. Static text is a fully
   valid choice when interaction would be noise. (Across many pages you'll
   naturally rotate patterns because content varies; don't force one in.)
4. **Build the page** committing fully to the chosen style (see Building below).
5. **Stamp both choices on the page** (see The Stamp — this is non-negotiable).
6. **File it** into a dated folder under `~/html-pages/` (see Gallery): write
   `index.html` plus a small `meta.json` sidecar. The live server picks it up
   automatically — no index to maintain.
7. **Tell the user** the style name, the one thing that makes it memorable, and
   that it's browsable at http://localhost:7777 (plus the file path). Mention they
   can name any style they like next time — anything in the world, not just a list.

## The Stamp (REQUIRED on every page)

The whole point is that the user can *see* what was tried. Every page MUST carry
a small, unobtrusive stamp — bottom corner, footer, or a fixed badge — containing:

- **Style:** the style name (e.g. "Neo-brutalism")
- **Keywords:** 3–5 words that define it (e.g. "thick borders · hard shadows · clashing brights")
- **Recreate prompt:** a one-line prompt the user can copy to ask for this style
  again, e.g. `"Make it neo-brutalist: thick black borders, 8px hard offset
  shadows, clashing saturated blocks, chunky sans."`
- **Interactivity:** the interaction pattern used (e.g. "details accordions") and
  a one-line prompt to recreate that too, or "static — interaction would be noise."

Style the stamp to harmonize with the page's aesthetic (don't break the design to
show it). A `<details>` badge that opens to reveal the prompts works well. The
stamp is how the user learns — never omit it.

## Building

Commit fully to ONE aesthetic direction. Borrow the design-quality bar from
Anthropic's frontend-design skill:

- **Typography:** distinctive fonts that match the style. Avoid generic defaults
  (Inter/Roboto/Arial/system) UNLESS the style demands them (Brutalism, Swiss).
- **Color & theme:** cohesive palette via CSS variables. Dominant color + sharp
  accent beats timid even palettes.
- **Composition:** let the style drive layout — grid, asymmetry, columns, density.
- **Detail:** backgrounds with atmosphere (gradients, noise, patterns, shadows)
  when the style calls for it; restraint and precise spacing when it calls for that.
- **Match complexity to vision:** maximalist styles = elaborate code; minimal
  styles = restraint executed precisely.

**Quality floor (a page that teaches must teach good craft):** whatever the
style, every page should clear a basic bar — readable text contrast against its
background; a layout that doesn't break on a phone (≈375px); `alt` text on
meaningful images; and any motion wrapped in `@media (prefers-reduced-motion:
reduce)` so it can be stilled. These are part of the craft, not a tax on it —
honor them *within* the aesthetic (a brutalist page is still legible; a
maximalist page still reflows).

Pages are **standalone**: inline the CSS (and any JS) in the `.html` file, OR use
the bundled `lib/` (notes theme only). Prefer self-contained so a page works when
opened directly with `file://`. Use CDN links for fonts/libraries as needed.

### Notes theme (one style among many)

`styles.md` lists "Notes (earth-tone)" as a rotation option. When that style is
picked (at random or by name), use the bundled `lib/` assets instead of inline CSS:

- Copy this skill's `lib/` into the page's folder.
- Base the page on `lib/_template.html`: link `lib/notes-style.css`; add the
  `notes-toc.js` / `notes-highlight.js` / `notes-comments.js` scripts; uncomment
  `notes-mermaid.js` only if the page has `<pre class="mermaid">` diagrams.
- Use its classes: `.section`, `.callout(-info/-warning/-success/-error)`,
  `.chip(-done/-todo/-blocked/-info/-open)`, `.notes-table`, `.notes-details`,
  `.eyebrow`, `.subtitle`, `.tldr`, `.note(.aha/.warn)`, `.legend`.
- This theme is skim-first for reviewing LLM output/plans. The stamp still applies.

## Gallery (findability)

Pages live under `~/html-pages/`, **one dated folder per page**:

```
~/html-pages/
  2026-06-11-auth-plan/           ← one dated folder per page
    index.html
    lib/                          ← only if notes theme was used
  2026-06-11-launch-copy/
    index.html
```

- **Folder per page:** `~/html-pages/<YYYY-MM-DD>-<short-slug>/index.html`. Use
  today's date (it's in your environment context; run `date +%F` only if unsure).
  Slug from the content's topic.
- **The gallery is a live server, not a file you maintain.** An always-on local
  server (`html-pages-server`, a launchd agent on macOS) scans `~/html-pages/`
  on every request and renders a browsable catalog — date-descending, with search
  and sort/theme controls. The user opens **http://localhost:7777** to browse and
  find past pages. You do NOT need to generate or update any `index.html` catalog;
  the server builds it live. (If the server isn't running:
  `html-pages-server &`, or just open a page with `open <file>`.)
- **So the gallery shows rich metadata, keep the stamp machine-readable.** The
  server extracts each page's style/keywords/recreate-prompt from the stamp. Use a
  definition list with these exact `<dt>` labels so extraction is reliable:

  ```html
  <dl>
    <dt>Style</dt><dd>Neo-brutalism</dd>
    <dt>Keywords</dt><dd>thick borders · hard shadows · clashing brights</dd>
    <dt>Recreate prompt</dt><dd>Make it neo-brutalist: …</dd>
  </dl>
  ```

  (Style the surrounding stamp however the page's aesthetic wants — only the
  `<dt>` labels matter for extraction. As a fallback the server also reads
  `data-style` / `data-keywords` / `data-recreate` attributes on any element.)

- **Also drop a `meta.json` sidecar** next to `index.html` — the most reliable
  way for the gallery to read metadata (it prefers the sidecar, falling back to
  parsing the stamp). One small file per page:

  ```json
  {
    "title": "Auth migration plan",
    "style": "Neo-brutalism",
    "keywords": "thick borders · hard shadows · clashing brights",
    "recreate": "Make it neo-brutalist: thick black borders, 8px hard offset shadows, clashing saturated blocks, chunky sans."
  }
  ```

  The visible on-page stamp is still REQUIRED (it's how the *user* learns); the
  sidecar just makes the *gallery's* extraction deterministic. Keep them in sync.

## Quick reference

| Step | Action |
|------|--------|
| Style | ANY style in the world (not just `styles.md` seeds), or user-named. Vary genuinely — avoid recent repeats. |
| Interactivity | Fit the content; static is valid. From `styles.md`. |
| Stamp | Style name + keywords + recreate prompt + interactivity prompt. Always. |
| Output | `~/html-pages/<date>-<slug>/` → `index.html` (standalone) + `meta.json` sidecar. |
| Gallery | Live server at http://localhost:7777 (auto-scans). No index file to maintain. |
| Stamp markup | `<dl><dt>Style/Keywords/Recreate prompt</dt><dd>…</dd></dl>` so the gallery extracts metadata. |
| Notes theme | Use bundled `lib/` + `_template.html` only when that style is chosen. |
| New style | Discovered/invented one? Add a row to `styles.md`. |

## Common mistakes

- **Omitting the stamp.** Then the user can't learn what was tried — defeats the
  whole purpose. Always stamp.
- **Converging on a handful of styles.** The style space is the whole world, not
  the `styles.md` seeds and not your three favorites. Genuinely vary across
  pages — reach for styles you haven't touched, including obscure ones.
- **Letting technical content pull you to technical styles.** The #1 real-world
  failure: technical docs (CVEs, pipelines, merge queues) keep coming out as
  blueprints / schematics / dossiers / terminals. That is convergence, not
  variety. Run the recency check and honor the family ban in `styles.md` — the
  content must NOT dictate the aesthetic.
- **Treating `styles.md` as a menu.** It's seeds to escape from. Picking only from
  that list defeats the point; the best page is often a style not listed there.
- **Hand-maintaining a gallery index.** Don't — the live server builds it. Just
  drop the page in its dated folder with a machine-readable stamp.
- **Half-committing to a style.** A timid brutalist page teaches nothing. Go all
  in on the chosen aesthetic.
- **Forcing interactivity.** A static reference page doesn't need a form. Stamp
  it as a deliberate static choice instead.
- **Breaking the design to show the stamp.** Harmonize it; a `<details>` badge in
  a corner is unobtrusive.
