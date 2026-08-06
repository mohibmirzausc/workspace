---
name: session-journal
description: Use when working in a cmux workspace with journaling enabled — records the decisions and reasoning that scroll out of the chat into a per-workspace HTML page at localhost:7777, so a human monitoring many parallel sessions can review them later and question what you did.
---

# session-journal

## What this is

Each cmux workspace has ONE HTML journal, browsable at http://localhost:7777.

The human runs many sessions in parallel and reads these pages *instead of* the
transcripts, which are far too verbose to monitor at that scale. Hooks already
record the mechanical facts automatically — files touched, commits, subagent
reports. They cannot record **why**. That part is yours.

Write for someone who will open this tomorrow, see that you made a choice, and
ask you to justify it.

## When to log

| Log it | Don't log it |
|---|---|
| A decision between real alternatives | Routine file edits (hooks capture these) |
| Something blocking you | Restating the user's request |
| A milestone that starts working | Narrating each step of a task |
| A constraint you discovered that changed the approach | Anything you would not want to re-read |
| An approach you rejected, and why | Tool output |

A handful of substantial entries per session. Not a running commentary.

## How

```bash
session-journal add --kind decision \
  --title "Used a mkdir mutex instead of flock" \
  --body "flock(1) does not ship on macOS. mkdir(2) is atomic on APFS, so a lock
directory is the portable primitive. Verified with 8 concurrent writers."
```

**Kinds:** `decision`, `progress`, `blocker`, `milestone`, `question`.
(`files`, `commit`, `subagent`, `session` are reserved for the hooks.)

For long bodies, pipe them in:

```bash
some-command | session-journal add --kind progress --title "..." --body-stdin
```

Other commands: `session-journal tail -n 20`, `session-journal path`,
`session-journal status`.

## Rules

- **The title is a claim, not a topic.** "Chose X over Y because Z" beats
  "Discussed options".
- **The body carries the alternatives.** What you rejected is usually the part
  worth reading.
- **Never read the whole journal.** It is never pruned. Use `tail -n` if you
  need recent context.
- **Failing to log is not an error.** If journaling is disabled the command
  exits 0 silently — never work around it, and never treat it as a failure.
- **Do not tell the user you logged something** unless they asked. The journal
  is a side channel, not conversation.

## Finding a journal

Markers are embedded in both the page and its sidecar:

```bash
# By workspace or session id (sidecar; also lists every session that ran there)
grep -l "<uuid>" ~/html-pages/*-session-*/meta.json

# By workspace id (page itself — works over HTTP too)
grep -l 'session-journal:workspace-id" content="<uuid>' ~/html-pages/*-session-*/index.html

# This workspace's journal
session-journal path
```

## Enabling and disabling

Journaling is **on by default**. Resolution order: `SESSION_JOURNAL=0/1` env var, then
`.session-journal` / `.no-session-journal` in the repo root, then
`~/.claude/session-journal-state`.

Shell helpers: `claude-journal-on`, `claude-journal-off`, `claude-journal-status`.

If the user asks you to stop journaling, run `claude-journal-off` — the check
lives in the hook scripts, so this genuinely stops all writes immediately.
