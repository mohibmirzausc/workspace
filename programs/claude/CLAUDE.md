# Global instructions

These apply to every session. My personal knowledge base is an Obsidian vault stored as a
plain folder at `~/src/notes` (it is a git repo). There is no `obsidian` CLI on this machine —
read and write notes with the normal file tools (Read / Write / Edit / Glob / Grep) directly
against files under `~/src/notes`.

## Response style

- Be direct and to the point. Cut preamble, filler, and restating the question. Answer first.
- Explain in simple, plain terms — but use the correct technical terminology, don't dumb it
  down or invent vague substitutes. Name the real concept, then make it understandable.

## 0. Public notes — NEVER write secrets or company-confidential info

`~/src/notes` is intended to be public (the repo is private today but MUST be written as if
world-readable). This is a hard rule:

- NEVER write credentials of any kind: passwords, API keys, tokens, private keys, connection
  strings, `.env` values, session cookies.
- NEVER write company-confidential material: internal hostnames/IPs, internal URLs, customer
  or client names, unreleased product details, proprietary source code, internal financials,
  or anything covered by an NDA/confidentiality obligation.
- Scrub identifiers when logging work: refer to internal systems by generic role
  ("the release pipeline", "the artifact store") rather than internal names, and redact or
  omit anything that would leak the employer or a client.
- When in doubt, leave it out — or ask me before writing it. It is always safe to log a note
  as "handled an internal issue with X" without the confidential specifics.

If a task genuinely requires recording confidential detail, tell me and keep it out of
`~/src/notes` (surface it in the conversation only).

## 1. Search the vault for non-generalizable info

When a task needs information that is NOT resolvable from general knowledge or the public
web — my personal workflows, homelab setup, project context, day-to-day notes, names of my
own projects — search `~/src/notes` first (Grep/Glob over the folder) before asking me or
guessing. Skip this for purely general/public questions.

## 2. Daily note / work log (the point of these notes)

The primary purpose of this vault is a work log: if a co-worker is out, they (or I) can read
the daily notes and know exactly what happened while they were away. Keep it accurate and
useful for that.

- Agent work logs live at `~/src/notes/Daily/<YYYY-MM-DD>.md` (today = the date in the
  session context; convert any relative dates to absolute).
- This is deliberately SEPARATE from my personal Obsidian daily journal, which the Daily
  Notes plugin writes to `Knowledge/Daily Notes/`. Do not write agent logs there, and don't
  "fix" the split — `Daily/` is for automated worklogs, `Knowledge/Daily Notes/` is mine.
- At the start of real work in a session, ensure that day's note exists. If it doesn't,
  create it with a short header (`# <YYYY-MM-DD>`) and an empty log section (`## Log`), then
  append under it. Create the `Daily/` folder if it isn't there yet.
- As work proceeds, append notable actions, decisions, and outcomes — enough that someone who
  was absent understands what changed and why. Do NOT log trivial one-off questions.
- Write the log for an absent reader: what was done, what decision was made and the reasoning,
  what's still open, and what they should do next.
- Link out rather than restating: wikilink the canonical topic notes the work touched
  (e.g. `[[homelab setup]]`) and reference work-tracking items by ID (e.g. Shortcut
  `sc-XXXXX`) instead of copying their details. The daily note is an index of the day.
- Obey point 0 in every log entry — no secrets, no company-confidential specifics.

## 3. Record important findings to the vault

Whenever something surfaces that's useful beyond the current session — a decision and its
reasoning, how one of my systems works, a recurring fact, a TODO — capture it into a topical
note under `~/src/notes`. Prefer updating an existing relevant note over creating a duplicate;
create a new note only when none fits. Keep the vault a connected graph: wikilink new/edited
notes to related notes so they're discoverable later. Same public-notes rule (point 0) applies.

## 4. Committing

Do not `git commit` or `git push` the notes repo unless I ask. When I do, double-check the
diff for anything that violates point 0 before committing.

Note: the vault has the `obsidian-git` plugin installed, which auto-commits/pushes from the
Obsidian app on its own schedule. Leave routine syncing to it — don't race it with manual
commits. Commit by hand only when I explicitly ask (e.g. to get a change out immediately).
