---
name: deep-brief
description: Use when the user wants to fully understand a document, thread, PR, spec, or decision they have little context on — "break this down wholly", "explain all the contents", "extract all the details", "I want to understand everything here". Produces an exhaustive HTML brief (8k-20k words) that preserves ALL source detail rather than summarizing it, with an embedded intake form for the gaps only the user can fill. Use instead of html-page when completeness matters more than brevity.
---

# deep-brief

## Overview

`html-page` optimizes for **style variety**. `intake-form` optimizes for **brevity**
("too many questions get abandoned"). Neither optimizes for **completeness** — so
when a user says "explain this whole document to me," the output glosses.

This skill exists for the opposite objective: **lose nothing**. The user has little
context and wants all of it. Length is a feature, not a cost.

**Core principle:** the source document's details are the deliverable. Your job is to
*expand* them with explanation, not *compress* them into summary.

## Bundled assets

- **`assets/structure.md`** — the structural devices that force detail (numbered parts,
  speaker cards, typed callouts, decode tables, collapsible glossary, status chips).
  Style-agnostic on purpose: re-skin per `html-page`'s recency rules. **Read this before
  building.**
- **`assets/form-engine.js`** — drop-in intake engine. Define `FORM_ID` + `SCHEMA` above
  it, provide `<div id="form-root">`. Includes three browser-verified fixes (event
  delegation, output-outside-root, clipboard fallback) — see its header comment.
- **`assets/verify.py`** — static checks. `python3 verify.py <path>/index.html`. Catches
  unbalanced tags, broken anchors, missing stamp/sidecar, and depth below target. Run it
  after assembling; it does **not** replace browser testing.

## The length attractor (why this skill exists)

Measured across 38 pages from `html-page`: median **2,402 words**, mean 2,624, p75
3,001 — but max **8,389**. So there is **no hard cap**; there is a strong attractor
around ~2.5k words.

The cause is structural, not a limit:

| Page | Headings | Tables | Words |
|------|----------|--------|-------|
| typical | 3–15 | 1–6 | 1,300–3,500 |
| outlier | 25 | 5 | 6,674 |
| outlier | 51 | 13 | 8,389 |

**Heading count predicts word count.** Plan "7 sections" and each section becomes a
summarizing paragraph. Plan 25 fine-grained sections and each leaf is small enough
that you write the *actual content* instead of a summary of it.

Glossing is a symptom of **too-coarse structure**, not of a length limit. A section
called "The Comments" gets one paragraph. Twenty sections named after individual
claims get twenty pieces of real content.

## Workflow

### 1. Extract the source exhaustively — before writing anything

Get **everything**, not just the body:

- The document body in full.
- **All comments, all threads, including resolved ones.** In Notion: `notion-fetch`
  with `include_discussions: true` shows counts, then `notion-get-comments` with
  `include_all_blocks: true` and `include_resolved: true` gets the actual content.
  The fetch tool shows only ~3 example discussions — **always call get-comments
  separately** or you will silently miss most of the conversation.
- **Resolve every participant's identity** (`notion-get-users` per ID). "user://2add..."
  is useless to the reader; "Tim Goodwin, compilers team" is the whole point.
- **Follow every external reference.** Linked PRs, epics, tickets. Verify claims —
  if a comment says "this is already live," check (`gh pr view`). Verified facts are
  the highest-value content in the brief and often reframe the document.
- **Note timestamps.** Body-last-edited vs. last-comment is frequently the story:
  a doc whose body predates its most substantive comments is materially incomplete
  to anyone reading only the body.

### 2. Build a section inventory FIRST — target 20-30 sections

Before writing, list the sections. **This is the step that defeats the attractor.**

Aim for **20–30 numbered parts**. One section per:
- each distinct argument in the source
- **each comment thread** (never merge threads — one section each)
- each option/alternative considered
- the mechanism/implementation detail
- external evidence you verified
- the cast of participants
- your assessment
- the blocking gaps
- the intake form

If your inventory has fewer than 15 entries, **it is too coarse — split it.** Ask of
each entry: "would this be 3+ paragraphs?" If yes, split it.

### 3. Write section files SEPARATELY, then concatenate

Do **not** write one giant `Write` call. One call = one implicit budget = self-rationing,
and the summarizing instinct is strongest at the end.

```
~/html-pages/<date>-<slug>/
  parts/00-head.html      ← doctype, CSS, masthead
  parts/01-orient.html    ← TOC + glossary
  parts/02-...html        ← content sections
  parts/NN-form-js.html   ← form engine, closing tags
  index.html              ← assembled
```

Then: `cat parts/*.html > index.html` (list explicitly to guarantee order).

Each part file is its own budget. 10 files × 1.5k words = 15k words, and no single
call ever feels long.

### 4. Verify, don't assume

Run the bundled checker first — it covers tag balance, internal anchors, depth, stamp,
and sidecar in one pass:

```bash
python3 <skill>/assets/verify.py ~/html-pages/<date>-<slug>/index.html
```

Then do what static analysis cannot:

- **Actually test interactivity in a browser.** `file://` is blocked in Playwright;
  serve it (`python3 -m http.server 8899`) and click through. On the first build of this
  skill's reference page, `Generate` silently did nothing — `render()` was destroying
  the button's handler. Code review missed it; the browser caught it. Verify: Generate
  produces output, JSON parses, multi-select preserves all values, notes are captured,
  a second Generate after more edits still works.
- **375px reflow** — zero horizontal *page* overflow (wide tables may scroll internally).
- **Clear your test answers from localStorage** when done, so the user starts fresh.

When re-querying the DOM in test scripts, **re-query after every click** — `render()`
replaces nodes, so stale references report wrong results and look like page bugs.

## Content rules (the actual craft)

**Quote verbatim, then analyze.** For any comment or key passage: the exact words in
a `blockquote`/speaker card, *then* your reading. Never paraphrase-and-move-on — the
user cannot tell what the source said vs. what you concluded. This is the single
biggest difference from a normal page.

**Every source bullet list gets decoded.** A 7-item list in the source becomes 7
subsections explaining what each item means and what goes wrong. Source lists are
compressed by their author; your job is decompression.

**Lead with a glossary.** For a user with little context, terms are the barrier. Use
`<details>` so each term is one line collapsed — experts scroll past, newcomers expand.
Explain not just *what* a term means but **why it's load-bearing in this document**.

**Mark your epistemic status.** Distinguish: the source says X / a commenter says Y /
I verified Z / I infer W / nobody has addressed V. Use visible chips
(`Settled` / `Open` / `Gap`). The user must always know whose claim they're reading.

**Name the crux.** Most documents have one load-bearing idea everything else depends
on. Give it its own early section and say plainly that it's the crux.

**Preserve defects.** Typos in a schema example, truncated words, empty required
fields, unanswered questions — these are findings, not noise. Reproduce them exactly
(mark `(sic)`) and explain the consequence.

**Never write "and other points were raised."** That sentence is the failure this
skill exists to prevent. Enumerate them.

## The intake form

Use **`assets/form-engine.js`** (a hardened extraction of `intake-form`'s engine), with
one inversion of that skill's guidance: **`intake-form` says keep it short; here, ask
everything that's genuinely unknown.** 15–25 questions across 3–5 sections is right.

Only ask what **you could not derive from the source**. Before each question: "did I
already answer this from the document?" If yes, cut it — asking it wastes the user's
attention and signals you didn't read carefully.

Good question categories:
- **The user's position** — role, what they were asked to do, decision authority.
  Changes what output is even useful.
- **Facts absent from the source** — team size, timelines, internal ownership.
  Usually where your analysis is weakest.
- **Your judgment calls** — you ranked/prioritized something; invite disagreement.
- **Meta** — did the depth work? Which parts earned their space?

Always include a "what did I get wrong or miss?" textarea. Keep the per-question
"note to Claude" channel and the `INTAKE-JSON` output block for round-tripping.

## Structure that produces depth

**See `assets/structure.md` for the markup.** In brief, the devices that force detail
(and roughly double word count vs. plain prose over the same source):

- **Numbered parts** with big ghosted numerals — makes 25 sections feel navigable
- **Speaker cards** for each comment — avatar, name, timestamp, verbatim quote
- **Callout types** with distinct semantics: `why` / `risk` / `aha` / `gap` / `jargon`
- **Decode tables** — every "the doc lists N things" becomes an N-row table with
  a "what this means" column. The mechanical anti-gloss device.
- **`<details>` glossary** — depth without wall-of-text
- **TOC with every section** — the honest signal of how much is here
- **Reading-progress bar** — orientation in a long document

## Quality floor

Inherit `html-page`'s bar: real typography, cohesive palette, mobile reflow, contrast,
`prefers-reduced-motion`. Inherit `intake-form`'s Fillability Floor: 44px tap targets,
high-contrast inputs, reachable action bar.

**Pick a style per `html-page`'s recency rules** (run the last-8 check; honor the
technical-utility family ban). Long-form reading favors generous serif body text and
strong sectioning, but that's a lot of styles — don't converge on one.

Add the `html-page` stamp (`<dl><dt>Style/Keywords/Recreate prompt</dt>`) and a
`meta.json` sidecar so the gallery indexes it.

## Quick reference

| Step | Action |
|------|--------|
| Extract | Body + ALL comments (`include_all_blocks`, `include_resolved`) + resolve users + verify external links |
| Inventory | 20–30 sections BEFORE writing. <15 means too coarse |
| Write | Separate `parts/NN-*.html` files, one per section group; concatenate last |
| Threads | One section per comment thread. Verbatim quote, then analysis |
| Glossary | `<details>` per term, explaining why it's load-bearing here |
| Status | Chips: Settled / Open / Gap. Never blur who claimed what |
| Verify | `python3 assets/verify.py <page>/index.html`, then browser-test the form at 375px + desktop; clear localStorage |
| Form | `assets/form-engine.js`; 15–25 questions, only genuinely-unknown things, + "what did I miss?" |
| Target | 8k–20k words. If under 6k, you summarized — go back |

## Common mistakes

- **Planning too few sections.** The root cause of every gloss. 7 sections → 2.5k words
  of summary, guaranteed.
- **One giant Write call.** Self-rationing kicks in; the tail gets compressed.
- **Merging comment threads** into "Discussion." Each thread is a distinct argument
  with distinct participants and its own resolution status.
- **Paraphrasing instead of quoting.** The reader loses the ability to distinguish
  source from analysis.
- **Skipping `notion-get-comments`.** `notion-fetch` shows only ~3 sample discussions.
  You will miss most of the conversation and not know it.
- **Leaving user IDs unresolved.** `user://2add872b` tells the reader nothing.
- **Not verifying external claims.** "This is already live" is checkable, and checking
  it often reframes the whole document.
- **Asking form questions you already answered.** Signals you didn't read the source.
- **Trusting code review over a browser.** Interactive bugs hide from reading.
- **Summarizing your own assessment.** The user wants the reasoning, not the verdict.
