---
name: working-journal
description: Use when the user asks for a "working journal" — or when investigative/multi-PR/multi-day work will outlive one context window and needs a durable source of truth. Produces an append-only HTML document where narrative findings and intake questions interleave, growing in labelled "waves" (rounds) so nothing is silently rewritten and no thread is dropped. Each wave carries a you-said/done ledger and a carry-forward table of open threads. Use instead of intake-form when the work spans rounds; instead of html-page when the user must answer inline; instead of deep-brief when the material is work-in-progress rather than an existing document to comprehend.
---

# working-journal

## Overview

Long investigations lose things. Context windows compact, sessions end, findings
get reported in chat and evaporate, and three days later nobody can say what was
decided or what's still open.

A working journal is **one HTML file that outlives the conversation**. It grows
downward in **waves** — you report, the user answers inline, you act, you append
what you did. Nothing already written is edited, so the drift between what you
believed in Wave I and what you know by Wave IV stays visible to both of you.

**Core principle: the document is the source of truth, not the conversation.**
If a finding, decision, or open thread isn't in the journal, it will be lost.

## How this differs from its neighbours

| Skill | Optimizes for | Rounds | User answers? |
|---|---|---|---|
| `html-page` | style variety, presentation | one | no |
| `intake-form` | brevity, getting answers | one (reopenable) | yes, at the end |
| `deep-brief` | completeness on *existing* material | one | gaps only |
| **`working-journal`** | **continuity across sessions** | **many, labelled** | **yes, inline per finding** |

`working-journal` **composes** `intake-form` (the question engine and JSON
round-trip) and `html-page` (style rotation, the stamp, the gallery). It adds
waves, the ledger, carry-forward tracking, and prose-beside-questions layout.

## When to use

Strong signals:
- The user says "working journal" (the explicit trigger)
- Work spans multiple sessions and you can feel context slipping
- You're tracking many parallel things — several PRs, several stories, several open questions
- The user says something like "keep appending", "use this as source of truth", "don't let anything get dropped"
- You've revised your own conclusions more than once and the history matters

Don't use it for a single question, a one-shot explanation (`deep-brief`), or a
document nobody needs to answer (`html-page`).

## Vocabulary (constant across all journals)

These terms stay the same no matter which visual style is rolled. Use them in the
document and when talking to the user — a shared vocabulary is the point.

| Term | Means |
|---|---|
| **Entry** | One section of narrative — a self-contained finding with its tables/code. Numbered `Entry I`, `Entry II`, … continuing across waves. |
| **Wave** | One round: you report → user answers → you act → you append. Separated by a visible divider with a date. |
| **Response card** | The intake questions sitting directly beneath an Entry |
| **Marginalia** | A short aside — a caveat, a correction, an "I was wrong about this" |
| **Ledger** | The two-column *You said → Done* table opening each wave after the first |
| **Carry-forward** | The table of every open thread and what it's blocked on, closing each wave |

## Workflow

### Wave I
1. **Write the Entries.** Each is a finding, with evidence. Interleave response
   cards so the user answers *while looking at* the finding, not after scrolling
   past ten of them.
2. **Roll a style** per `html-page` — run its mandatory recency check, honor the
   family bans. The structure below is fixed; the skin is not.
3. Build from `assets/journal-template.html`, file to
   `~/html-pages/<YYYY-MM-DD>-<slug>-journal/` with `index.html` + `meta.json` +
   the `html-page` stamp.
4. Serve it, give the user the URL, tell them: answer inline, skip freely, then
   **Copy Wave I answers** at the bottom of that wave.

### Every wave after
5. **Parse the `INTAKE-JSON`.** Take the **last** ```` ```INTAKE-JSON ```` fence in
   the paste, not the first — answers can legitimately contain code fences, and
   while the engine neutralizes them in the human preamble, an older journal or a
   hand-edited paste may not. Read `note` fields and `skipped` items first; they're
   the highest-signal parts. Each payload carries `"wave": N` so you know which
   round it belongs to.
6. **Act on the answers** before writing anything.
7. **Append a new wave**, never edit the old one:
   - A `wave-break` divider with the date
   - A **ledger** Entry: *You said → Done*, one row per answer you acted on.
     Mark anything still running as such.
   - New Entries for what you found
   - A **carry-forward** Entry: every open thread, its state, and who/what it's
     blocked on
8. **Answer questions the user asked you.** If they asked something in a `note`,
   answer it as an Entry — don't let it die in chat.
9. Tell them the wave is up, and to hard-refresh (`?v=<wave>`) — browsers cache
   these aggressively.

## Structural rules (the parts that make it work)

- **Append only.** Never rewrite a previous wave. If you were wrong, say so in a
  *new* Entry or a marginalia note in the new wave. The record of being wrong is
  valuable.
- **Every wave ends with carry-forward.** If a thread isn't in that table, it's
  been dropped. This is the anti-drift mechanism — treat it as mandatory.
- **Every wave after the first opens with the ledger.** It proves you acted on
  what they said, and surfaces anything you consciously didn't do.
- **Per-wave copy.** Each wave has its own Copy button emitting only that wave's
  answers. Without this, the pasted block grows unbounded and the user re-sends
  answers you already have.
- **Entries are numbered continuously** across waves (Wave I ends at Entry VIII,
  Wave II starts at Entry IX). Continuous numbering makes them citable in chat.
- **Answer their questions in the document**, not only in chat — the journal is
  the record.
- **Show evidence, not conclusions.** Real command output, real measured numbers,
  real before/after tables. A journal of assertions is worthless later.

## Template

`assets/journal-template.html` is the `intake-form` engine plus:

- A `prose` field per section, rendered as an Entry *before* its response card
- Sections with `questions: []` render as prose only — use for wave dividers.
  (Ledgers and carry-forward tables *do* carry a question or two, so they are
  not prose-only; see the table above.)
- `wave` field on each section, grouping it in the nav and the per-wave copy
- A floating **wave selector**: entries grouped by wave, live progress dots
  (`○` untouched, `◐` partial, `●` answered), active-section tracking, collapsing
  to a bottom drawer on mobile
- Per-wave copy buttons at the foot of each wave

Edit only the `CONFIG` block, the `SCHEMA` array, and the theme variables.

### Schema

```js
{
  id: "w2_reimport",              // MUST be unique across the whole document
  wave: 2,                        // MUST be a number, never "2"
  entry: "X",                     // roman numeral; omit on wave dividers only
  title: "The fresh import result",
  ico: "🧪",
  sub: "One line under the card heading.",
  prose: `<h2>…</h2><p>…</p>`,    // the Entry; rendered before the card
  questions: [ /* intake-form question objects */ ]   // REQUIRED, [] if none
}
```

Question objects are exactly `intake-form`'s: `text`, `number`, `textarea`,
`radio`, `checkbox`, `matrix`, plus `hint`, `prefill`, `showIf`.

### Schema rules that bite (all verified by testing)

- **`questions: []` is required on every section**, including wave dividers and
  carry-forward tables. Omitting the key entirely used to blank the whole page;
  the engine now normalizes it, but write it explicitly.
- **`wave` must be a numeric literal** — `wave: 2`, never `wave: "2"`. A string
  silently splits one wave into two nav groups and two copy buttons, each emitting
  *half* the answers. The engine now coerces it; don't rely on that.
- **`id` must be unique across every wave.** A duplicate makes the second Entry
  unreachable from the nav (both links scroll to the first). Reusing a slug like
  `w2_ledger` across waves is the easy mistake — prefix with the wave.
- **Never change `FORM_ID` after Wave I.** It is the `localStorage` key. Changing
  it wipes every answer the user has already given, with no warning.
- **`entry` numerals are not validated.** Keep them continuous yourself
  (Wave I ends at VIII → Wave II starts at IX); the engine only warns on exact
  duplicates.
- **Append waves in ascending order.** The nav sorts numerically while the
  document renders in `SCHEMA` order, so an out-of-order append makes "Wave II"
  jump past Wave III.
- **If prose or a label must contain a literal `</script>`, write `<\/script>`** —
  otherwise the inline `<script>` block closes early and the page dies.

### Which sections get an `entry` numeral

| Section | `entry` | `questions` |
|---|---|---|
| Wave divider | **omit** | `[]` |
| Ledger (You said → Done) | **yes** | 1 sanity question |
| Finding | **yes** | 1–4 |
| Answering their question | **yes** | 0–2 |
| Carry-forward | **yes** | 1–3 steering questions |

Only wave dividers go un-numbered. Everything else is a citable Entry.

## Implementation gotchas (learned the hard way)

- **`scroll-margin-top`** on Entries, or every nav jump lands the target *under*
  the sticky progress bar. 74px works for the default header.
- **The floating nav must measure the action bar at runtime**
  (`--actionbar-h`), or it overlaps it on mobile.
- **Browsers cache hard.** Always hand the user a `?v=<wave>` URL after appending.
- **Wide tables and `<pre>` need `overflow-x:auto`** or they break the mobile
  layout — check `scrollWidth - clientWidth === 0` at 375px.
- **The skip control belongs on the label's baseline** (`display:flex` +
  `margin-left:auto`), not wrapped below it, or every question looks ragged.
- **Verify the round-trip by execution** before handing it over: fill one of each
  field type, click Generate, and parse the emitted block. Don't assume.

## Quality bar

Inherit `html-page`'s floor — readable contrast, reflows at 375px, ≥40px tap
targets, 16px inputs (no iOS zoom), `prefers-reduced-motion` respected — and add:

- **Evidence over assertion.** Command output and measured numbers, not "I checked."
- **Corrections are first-class.** When you were wrong, say so plainly in the new
  wave. `marginalia` is the right home for it.
- **Severity honestly scoped.** If a bug affects nobody today, say that. Don't
  inherit a subagent's severity without checking exposure.

## Common mistakes

- **Rewriting earlier waves.** Destroys the record of how thinking changed — the
  main reason to keep a journal at all.
- **Skipping the carry-forward table.** Threads then silently vanish; the user
  asked for this document precisely so that wouldn't happen.
- **One giant copy button.** By Wave IV the user is re-pasting Wave I answers.
- **Letting the style dictate the vocabulary.** Terms are constant; only the skin
  rotates. A Bauhaus-styled journal still has Entries and Waves.
- **Answering the user's questions only in chat.** If it isn't in the journal, it
  is lost.
- **Reporting a subagent's findings unverified.** Check the headline claim
  yourself before it enters the record.
- **Forgetting the stamp / `meta.json`.** Then the gallery can't index it.
