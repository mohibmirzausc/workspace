---
name: obsidian-dashboard
description: Use when building a rich, multi-column Obsidian dashboard/launchpad/homepage — an at-a-glance view that pulls live data (tasks, notes, habits, metrics, observability, quick-access links) into styled widget cards. Covers the Columns-plugin layout, the inline-styled-HTML dataviewjs widget technique, fonts/width setup, and the specific rendering gotchas that otherwise cost hours of trial-and-error.
---

# obsidian-dashboard

## Overview

Build a polished, multi-column Obsidian dashboard: a single note that renders
live **widget cards** (tasks due, recent notes, habit trackers, counts/stats,
tag clouds, quick-access nav, charts, embedded Bases) laid out in columns.

Useful for: a daily homepage/launchpad, an observability panel (metrics/health
rolled up from note frontmatter), a quick-access hub (links + recent + search),
a project cockpit — any "at a glance" surface.

**The hard-won core lesson:** a great Obsidian dashboard is NOT external CSS
styling a bunch of markdown. It's **`dataviewjs` blocks that build inline-styled
HTML strings**, laid out with the **Columns plugin**, with a thin external
snippet for the shared classes. This technique is theme-independent and reliable;
the "just write markdown + a stylesheet" approach fights the renderer and loses.
Read `reference.md` before building — it encodes every gotcha.

## When to use

- User asks for an Obsidian dashboard / launchpad / homepage / "at a glance" view.
- User wants live rollups (tasks, counts, recent activity, metrics) in one place.
- User wants a quick-access hub or an observability/status panel inside Obsidian.

Not for: a single simple query (just use one ```dataview``` block), or styling
that isn't a dashboard.

## Required plugins

Confirm these are installed (you can prep configs but the USER installs plugins):
- **Dataview** (with "Enable JavaScript queries" ON) — the engine for every widget.
- **Columns** (by Trevor Nichols, id `obsidian-columns`) — the multi-column layout. Search the browser by display name **"Columns"**, not the id.
- **Custom Note Width** (by 0skater0) — optional; full-width via `custom-width:` frontmatter. Needs `enablePerNoteWidth:true` + `yamlKey:"custom-width"` in its `data.json`. The CSS snippet also forces full width, so this is a nicety, not a hard dep.
- Optional: **Charts** (`obsidian-charts`) for graphs, **Tasks** if pulling task metadata.

## Workflow

1. **Clarify the dashboard's purpose and widgets** (ask, don't assume): what
   data sources? which widgets? how many columns? Scale ambition to the ask.
2. **Confirm plugins** are installed (Dataview + Columns minimum). If missing,
   give exact install steps and stop until confirmed.
3. **Read `reference.md`** — the technique + every gotcha. Do not skip.
4. **Build the note SELF-STYLING** (the default — see reference.md "DEFAULT TO
   SELF-STYLING"): a dataviewjs block at the top injects a `<style>` tag holding
   ALL the dashboard CSS, so it renders commercial-grade instantly with no snippet
   to enable and no reload. Use `lib/dashboard.css` as the rule set to copy INTO
   that injector. This is what makes it look professional out of the box —
   external snippets render as an ugly unstyled page until manually reloaded.
   (Fonts, if used, still need `.obsidian/snippets/` + bare filename.)
5. **Lay out the note**: `cssclasses: [<your-class>]` frontmatter (just a selector
   hook, needs no snippet), optional banner, the style-injector block, then
   `` `````col `` wrapping `` ````col-md `` columns, ONE dataviewjs block per column
   (backtick-nesting rule in reference). Use `lib/widgets.md` for widgets.
6. **Scope every query** to exclude noise folders (templates, scripts,
   experiments, `.obsidian`) so counts/lists stay accurate.
6b. **Polish it — don't ship bare.** Correct-but-plain looks terrible. Use
   big-number stat tiles, a hero ring/bar, hover states, icons, color vars, and
   `.sub`/`.badge`/`.empty` touches. See reference.md → "Make it PROFESSIONAL" and
   the "Professional polish CSS" + pretty-widget snippets in `lib/widgets.md`.
7. **Sandbox first** if experimental — build under a `_`-prefixed folder so it's
   excluded from other dashboards and (in a published vault) from publishing.
8. **Tell the user to reload** after every CSS/plugin change — snippet or plugin
   edits do NOT hot-reload (toggle off/on). This is the #1 source of "it didn't
   work" confusion. See reference.md → "Applying changes".
9. **Verify with the user** by screenshot AND the DevTools console (it surfaces
   font/query errors directly). Fix using reference.md — and when layout is wrong,
   INSPECT the DOM / read plugin source rather than guessing at selectors (see
   reference.md → "Meta-lesson: don't guess").

## The three failure modes (from reference.md — check these first)

1. **Gaps between widgets** → put ALL widgets for a column in ONE dataviewjs
   block, wrapped in `<div style="display:flex;flex-direction:column;gap:8px">`.
   Separate markdown blocks don't reliably get gaps between them.
2. **Not full width** → `custom-width:` frontmatter (Custom Note Width plugin)
   AND a strong CSS override on the sizer; also disable "Readable line length".
3. **Fonts not loading** → keep font files IN `.obsidian/snippets/`, reference
   by bare filename. Check DevTools console for `ERR_FILE_NOT_FOUND`.

## Verifying

Ask the user to open DevTools console (Cmd+Opt+I) — it surfaces font-load errors
and Dataview issues directly, which is far faster than guessing from screenshots.
