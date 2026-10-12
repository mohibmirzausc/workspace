---
name: keep-session
description: Use when the user wants to keep the current session going for days or weeks, "immortalize" it, make it a defined or hosted agent, stop losing it when its window closes, or asks to "adopt" this session. Turns a running Pi session into an interactive agent of the shared memory system (kept alive in tmux by the keeper, in its own cmux window). Pi only.
---

# Keep this session alive (adopt it as an interactive agent)

Mohib works in some sessions for many days. Defined as **interactive agents**
in the memory repo (`~/src/memory/agents/<name>/agent.md`, `kind: interactive`)
they are tracked, hosted in tmux, brought back by the keeper if they die, and
shown in a cmux window declared in `~/src/memory/layouts/<name>.yaml`. Closing
the window no longer ends the session. Details:
`~/src/memory/docs/standing-agents.md`, section "Interactive agents".

**Pi only.** It needs the Pi session's id (`PI_SESSION_ID`). In Claude Code,
say it isn't supported there yet.

## Steps

1. **Check it isn't one already.** If `MEM_ROLE` is `interactive` or
   `standing`, this session is already an agent (`MEM_AGENT` names it): say so
   and stop.
2. **Agree the name and description with the user, in one question.**
   - Name: default to the name this session already logs under (`MEM_AGENT`,
     else the Pi session name, lowercased with dashes), so its ledger history
     stays under one name. Lowercase letters, digits, `.` `_` `-`.
   - Description: one line saying what the session is for.
   - Its window title is the name, cut to its last words that fit in 16
     characters (e.g. `concourse-migration-audit` → "migration audit").
3. **Preview, then adopt:**
   ```bash
   mem agent adopt <name> --description "<one line>" --dry-run
   mem agent adopt <name> --description "<one line>"
   ```
   It writes the definition (with a comment naming this Pi session and the
   date), pins this session to resume, writes `layouts/<name>.yaml` unless it
   exists (`--layout <l>` uses another layout, `--no-layout` skips the
   window), and leaves a watcher waiting for this Pi to exit.
4. **Hand over to the user. You can't do the next step yourself.** Tell them:
   - Type `/quit` in this session. Within a few seconds the agent starts in
     tmux, resuming this same conversation, and its new cmux window opens.
   - Then close this old window, so nothing (cmux included) resumes the same
     session twice. Two Pi processes on one session file corrupt it.
   - Run `/triage` if they want the new window placed.
5. **Committing.** The new `agents/<name>/agent.md` and `layouts/<name>.yaml`
   go into the memory repo with code (see `~/src/memory/AGENTS.md`). Mention
   it. The resumed session, or the user, can commit them.

## Afterwards

- `mem agent list` shows it as `interactive`; `mem agent attach <name>` opens
  it in any terminal; `mem layout up <name>` reopens its window.
- `/quit` in the hosted session marks it down: the keeper stops bringing it
  back. `mem agent up <name>` brings it back.
- The keeper never restarts it for an upgrade. When `mem agent list` says
  "old code", use `/reload` (memory code) or `mem agent restart <name>`
  (a new Pi version).
- If the watcher didn't bring it up, its log is
  `~/src/memory/.mem/agents/<name>/adopt.log`; `mem agent up <name>` does the
  same by hand.
