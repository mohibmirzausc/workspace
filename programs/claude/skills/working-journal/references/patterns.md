# Patterns

Reusable shapes for journal Entries. Copy the markup; adapt the content.

## The ledger (opens every wave after the first)

Two columns: what they said, what you did. This is how the user verifies you
acted on their answers — and how you surface what you *didn't* do.

```html
<h2>What I did with your answers</h2>
<table class="ledger">
  <tr><th>You said</th><th>Done</th></tr>
  <tr><td>Put the lesson in CLAUDE.md</td><td class="status-done">✔ Added, with the concrete example</td></tr>
  <tr><td>File a story for X</td><td class="status-done">✔ <strong>sc-12345</strong></td></tr>
  <tr><td>Fix Y now</td><td class="status-open">⏳ In flight — agent running</td></tr>
  <tr><td>Hold off on Z</td><td class="status-done">✔ Nothing filed</td></tr>
</table>
```

Include rows for things you deliberately *didn't* do. "You said hold off — I held
off" is a real ledger entry and closes the loop.

## The carry-forward (closes every wave)

Every open thread, its state, and what unblocks it. **Mandatory.** If a thread
isn't here, it has been dropped.

```html
<h2>Open threads carried forward</h2>
<table class="ledger">
  <tr><th>Thread</th><th>State</th><th>Waiting on</th></tr>
  <tr><td>Root cause of X</td><td class="status-open">blocked</td><td>A file only they can export</td></tr>
  <tr><td>PR #109</td><td class="status-open">in flight</td><td>Agent chain</td></tr>
  <tr><td>sc-12345</td><td class="status-done">filed</td><td>—</td></tr>
</table>
<div class="marginalia">Nothing dropped. Anything open is waiting on a person or a file.</div>
```

## Before/after evidence

The single most valuable Entry shape. Never assert a fix works — show it.

```html
<table>
  <tr><th>Scenario</th><th><code>main</code></th><th>This branch</th></tr>
  <tr><td>Wed start, no allocations</td><td>40 ❌</td><td>24 ✅</td></tr>
  <tr><td>Monday start</td><td>40</td><td>40 ✅ unchanged</td></tr>
</table>
```

Pair with real command output:

```html
<pre><code>distinctDates           : 178
weekdayMisreadByNewDate :   0   ← the bug never fires</code></pre>
```

## The correction

When you were wrong, give it its own Entry or a prominent marginalia in the *new*
wave. Never quietly edit the old one — the record of changing your mind is one of
the most useful things in the document.

```html
<div class="marginalia">A reviewer called this a merge blocker. Checking actual
exposure showed nobody is affected, so I downgraded it. Worth knowing that
reviewers over-rate severity without exposure data.</div>
```

## Verdict chips

Inline status markers for scannability. Restyle to fit the rolled aesthetic.

```html
<span class="verdict good">merged</span>
<span class="verdict warn">inconclusive</span>
<span class="verdict bad">defect</span>
```

## Answering a question they asked you

If the user asks something in a `note`, answer it as an Entry — not only in chat.

```html
<h3>“Am I missing something from my export?”</h3>
<p>You're not doing it wrong — but yes, one file is missing…</p>
```

## Section types at a glance

| Section | `entry` | `questions` | Purpose |
|---|---|---|---|
| Wave divider | omit | `[]` | Visual break + date |
| Ledger | yes | 1 sanity question | You said → Done |
| Finding | yes | 1–4 | Evidence + response card |
| Answering their question | yes | 0–2 | Close a loop from a `note` |
| Carry-forward | omit or yes | 1–3 steering questions | Open threads |

## Question design

Inherit `intake-form`'s rubric — start from decisions, prefer multiple-choice,
make skipping legitimate, one concept per question. Two additions for journals:

- **Ask about the finding directly above.** "Is that reading correct?" beats a
  generic question at the end of the document.
- **Ask what to do next**, not just what's true. The carry-forward Entry is the
  natural home for "what should Wave III cover?" as a checkbox.
