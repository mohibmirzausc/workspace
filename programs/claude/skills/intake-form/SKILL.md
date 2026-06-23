---
name: intake-form
description: Use when you need to gather a lot of structured information from a human at once — when the user says "intake form", "questionnaire", "interview me", "ask me a bunch of questions", "build me a form", "let's do a feedback loop", or whenever you find yourself with many parallel questions for a human (project kickoff, design brief, requirements gathering, planning, retro, bug report). Generates a designed, interactive HTML form whose questions YOU author for the specific situation, which the human fills (skipping freely, noting back per question), then round-trips a structured JSON payload back to you to close — and reopen — the feedback loop.
---

# intake-form

## Overview

Turn "I need to understand X from this person" into a **designed, interactive HTML
form** that closes a tight human↔Claude feedback loop. Three jobs:

1. **You author the questions** for the *specific* situation (not a fixed template).
2. **The human fills it in a browser** — skipping freely, noting back to you per
   question, on any device.
3. **A structured JSON payload round-trips back to you** so you parse answers
   reliably and can launch a sharper next round.

**Core principle:** the form is a *conversation accelerator*, not a survey. The
value is in (a) asking the *right* questions for *this* situation and (b) making
it effortless for the human to answer, skip, and talk back — then getting clean,
machine-readable answers back to you.

This skill **composes `html-page`** for look-and-feel and the gallery. It owns the
*form logic*; it delegates *aesthetics* to `html-page` conventions.

## When to use (trigger proactively)

Reach for this whenever you'd otherwise fire off many questions in chat, OR the
user asks for a form/questionnaire/interview. Strong signals:

- Project/feature kickoff, requirements gathering, design brief, planning a thing
- "Ask me everything", "interview me", "build a form", "intake", "questionnaire"
- A brainstorming moment where you have 8+ parallel questions
- Onboarding, retros, bug reports, vendor/status tracking

If you have ≤3 questions, just ask them in chat — a form is overkill. The form
wins when there are *many* questions, or matrix/status data, or the human will
want to fill it over time.

## Workflow

1. **Understand the goal.** What do you need to learn, and why? What decisions do
   the answers unblock? This determines the questions — spend real thought here.
2. **Author the questions** using the Question Design Rubric below. Group into
   logical sections. Pick field types per question. Add conditional logic where a
   question only matters given a prior answer.
3. **Pre-fill what you already know** (optional but powerful). If you know an
   answer from the conversation, seed it as the field's default so the human just
   *confirms or corrects* instead of typing from scratch. Set `prefill` on the field.
4. **Build the form** from `assets/form-template.html`: drop your question schema
   into the `SCHEMA` array (see Schema Reference). Commit to a fitting aesthetic
   per `html-page`'s quality bar — but honor the Fillability Floor below.
5. **File it into the gallery** like `html-page`: write to
   `~/html-pages/<YYYY-MM-DD>-<slug>-intake/index.html` plus a `meta.json` sidecar,
   so it's browsable at http://localhost:7777. Add the `html-page` stamp.
6. **Serve & hand off.** Start a local server and give the user the URL. Tell them:
   fill what they can, skip freely, use the per-question "note to Claude" to talk
   back, then click **Generate Summary → Copy** and paste the block back to you.
7. **Close the loop.** When they paste the JSON, parse it. Confirm what you heard,
   surface gaps (skipped/unsure items), and act.
8. **Reopen if needed (multi-round).** Round 1 is broad. After reading answers,
   if you now have sharper questions, build a **round-2 form** targeting just the
   gaps and tensions. Iterate until you understand enough to act.

## Question Design Rubric (the hard part — do this well)

A generic form teaches you nothing. Good questions are the whole value.

- **Start from decisions, not topics.** For each question ask: "what will I *do*
  differently based on the answer?" If nothing, cut it.
- **Prefer multiple-choice over open text** when the option space is known — it's
  faster for the human and cleaner for you. Use textarea only for genuinely open
  things.
- **Make "I don't know / skip" legitimate.** You *want* gaps surfaced honestly,
  not papered over. Every field is skippable; never block on "required".
- **One concept per question.** Split compound questions.
- **Order by momentum:** easy/concrete first (names, dates, counts), open/strategic
  later (worries, non-negotiables).
- **Add a hint** where the question could be misread.
- **Use a matrix** for parallel status tracking (e.g. a list of vendors/components
  each with status + note) — far better than N separate questions.
- **Use conditionals** to keep it short: only show a follow-up when it's relevant.
- **Always end with an escape hatch:** "anything else I should know?" and "where
  can I help most?"

## Schema Reference

The template reads a `SCHEMA` array. Each section:

```js
{
  id: "basics",                    // unique, used for state keys
  title: "The Essentials",
  ico: "💍",                       // optional emoji
  sub: "One-line description of the section.",
  questions: [ /* question objects */ ]
}
```

Question objects by `type`:

```js
// Free text / number
{ id: "guest_count", type: "number", label: "Guest count",
  hint: "ballpark is fine", placeholder: "e.g. 200", prefill: "" }

{ id: "venue", type: "text", label: "Venue name & city", placeholder: "" }

// Long text (genuinely open answers)
{ id: "worries", type: "textarea", label: "What worries you most?" }

// Single choice
{ id: "formality", type: "radio", label: "Formality",
  options: ["Black-tie", "Formal", "Relaxed", "Casual"], prefill: "Formal" }

// Multiple choice
{ id: "events", type: "checkbox", label: "Which events?",
  options: ["Mehndi", "Nikah", "Walima", "Reception"] }

// Matrix: a list of rows, each with a status dropdown + free note
{ id: "vendors", type: "matrix", label: "Vendor status",
  rows: ["Venue", "Catering", "DJ", "Photographer"],
  statuses: ["Booked ✅", "Shortlisted", "Researching", "Not started", "N/A"] }

// Conditional: show this question only when another answer matches.
// `showIf` references another question's id and the value(s) that reveal it.
{ id: "alcohol_detail", type: "text", label: "Which bar package?",
  showIf: { id: "alcohol", equals: "Yes" } }

{ id: "kid_count", type: "number", label: "Roughly how many kids?",
  showIf: { id: "kids", in: ["Yes, fully", "Limited"] } }
```

Notes:
- **`prefill`** seeds a default (string for text/number/radio; array for checkbox).
  Use it to pre-fill what you already know so the human just confirms.
- **`showIf`** supports `equals` (exact match) or `in` (any of a list). For
  checkbox sources, the condition is met if the source's selected array *includes*
  the value. Conditional questions auto-hide and are excluded from the count/JSON
  when hidden.
- **Every** non-matrix question automatically gets an optional **"note to Claude"**
  field beneath it (the talk-back channel). Matrix rows have a per-row note.
- The template handles autosave/resume (`localStorage`), progress, the Generate
  Summary → structured JSON + Copy, all rendering. You only write `SCHEMA` (and the
  page title / theme).

## Fillability Floor (composing html-page, with constraints)

`html-page` explores wild aesthetics. A form has stricter UX needs. Whatever style
you pick, the form MUST:

- Keep **inputs and labels high-contrast and obviously interactive** (no mystery-meat).
- **Reflow on a phone (~375px)** — humans fill these on the go.
- Keep **tap targets ≥ ~40px** and spacing comfortable.
- Keep the **progress + action bar reachable** (sticky or clearly placed).
- Respect `prefers-reduced-motion`.

Within those, commit to a real aesthetic and add the `html-page` **stamp**
(`<dl><dt>Style/Keywords/Recreate prompt</dt>…`) + `meta.json` sidecar so the
gallery indexes it. Note the interactivity as "intake form".

## The Loop (v1: copy-paste structured JSON)

The form's **Generate Summary** button produces:
- a human-readable summary (for the user to eyeball), and
- a fenced **`INTAKE-JSON`** block: machine-readable answers keyed by question id,
  with each answer's value, optional note-to-Claude, and a `skipped` flag.

The user clicks **Copy** and pastes it back. You parse the JSON block — it's the
source of truth (the prose is just for the human). Then confirm + act + (maybe)
launch round 2.

Example of what comes back:

```INTAKE-JSON
{
  "form": "wedding-intake",
  "answers": {
    "guest_count": { "value": "350", "note": "" },
    "alcohol": { "value": "No alcohol (dry)", "note": "religious" },
    "vendors": { "value": { "DJ": "Booked ✅", "Dhol": "Not started" },
                 "notes": { "Dhol": "need to decide entrance vs floor" } },
    "colors": { "skipped": true }
  }
}
```

## Multi-round philosophy

One form rarely captures everything. Treat it as **rounds**:
- **Round 1:** broad — map the whole territory, surface what's unknown.
- **Read the answers**, especially `skipped` items and `note` talk-backs.
- **Round 2:** narrow — sharper questions about the gaps, tensions, and the
  decisions still open. Pre-fill round 2 with what round 1 established.
- Stop when you can act confidently.

## Quick reference

| Step | Action |
|------|--------|
| Decide to use | Many parallel questions, matrix data, or user asks for a form. ≤3 Qs → just ask in chat. |
| Author Qs | Use the Rubric: start from decisions, MC over open text, skip is valid, matrix for parallel status, conditionals to stay short. |
| Pre-fill | Seed `prefill` for anything you already know — human confirms, not retypes. |
| Build | Drop `SCHEMA` into `assets/form-template.html`; pick a fitting `html-page` style within the Fillability Floor. |
| File | `~/html-pages/<date>-<slug>-intake/` → `index.html` + `meta.json` + stamp. |
| Serve | Local server; give URL; tell user to fill/skip/note then Generate Summary → Copy → paste back. |
| Close loop | Parse the `INTAKE-JSON` block. Confirm, surface gaps, act. |
| Reopen | Build round-2 form for gaps; pre-fill from round 1. |

## Common mistakes

- **Generic questions.** The skill's value is situation-specific questions. Don't
  ship a template — author for *this* goal using the Rubric.
- **Too many questions / making them required.** Long, blocking forms get
  abandoned. Keep it scannable; everything skippable.
- **Reading the prose, not the JSON.** The `INTAKE-JSON` block is the source of
  truth — parse it.
- **Ignoring the talk-back notes & skipped items.** Those are the highest-signal
  parts — they tell you where the human is uncertain or wants to discuss.
- **One-and-done.** If gaps remain, do round 2. The loop is the point.
- **Breaking fillability for style.** A gorgeous form nobody can fill on a phone
  is a failed form. Honor the Fillability Floor.
- **Forgetting the stamp/sidecar.** Then the gallery can't index it.

## Future (not in v1 — documented intentionally)

- **Save-to-file loop:** download `answers.json` to a known path Claude reads
  directly (avoids pasting big blocks).
- **Diff on re-run:** highlight what changed since last submission.
- **Auto-export** answers into a repo doc.
- **Reusable seed templates** (a `templates.md` of seeds to escape from, à la
  `html-page`'s `styles.md`) — kept as *seeds*, never a rigid menu.
