---
name: triage
description: Use when the user says "/triage", "triage my windows", "organize my terminals", "clean up my workspaces", or complains they cannot find a session. Groups open cmux windows into projects, gives each project its own OmniWM workspace (2-9 or 11), labels the workspaces, fixes junk window names, and parks anything it is unsure about on workspace 10 ("review"). It never closes windows.
---

# Triage

The user runs one terminal per cmux window (no tabs, no tmux) under the OmniWM
tiling window manager. Over a day those windows drift: junk auto-names, one
project spread over three workspaces, finished sessions left open. This skill
puts them back in order: **one project per workspace, every window named,
every workspace labelled on the bar.**

There is no registry file. The state lives in OmniWM itself: a workspace's
bar label says which project owns it, and the windows on it are the project.
Each run reads that state fresh and changes as little as it can.

OmniWM persists labels into `~/.config/omniwm/settings.toml`, so the live
file drifts from the repo seed while projects are allocated. That is
expected. Labels are runtime state, so don't copy them back into
`programs/omniwm/settings.toml`. Rebuilds keep them: when the seed is
re-installed, the pool workspaces' `displayName` is carried over from the
live file (`programs/omniwm/keep-workspace-state.py`). Layouts are not
triage's: every workspace is niri, set in the seed.

## Rules

- **Workspace 1 is the user's.** Never move a window into it or out of it,
  and never relabel it. Report what is there, but leave it alone.
  The one exception is a cmux restart, which piles every window onto one
  workspace (1, or whichever one the user was on): `restore` puts each back
  where the last run left it, which can mean off 1 or back onto it (see
  [Restart recovery](#restart-recovery)).
- **The pool is workspaces 2-9 and 11.** Projects are allocated from it.
  11 is numbered after review but sits with 1-5 on the external monitor
  (key Caps+6).
- **Workspace 10 is `review`.** Anything you're unsure about goes there
  instead of being closed or guessed into a project. That means windows that
  look finished or abandoned, and windows you can't place. The user clears it
  by hand.
- **Only cmux windows move.** Leave every other app where it is (browsers,
  Slack, Docker). Scratchpad and floating windows are the user's comms setup,
  so never touch them either.
- **Never close a window.** Closing is the only step that can lose work, and
  the user closes windows themselves. Park doubtful windows on `review`
  instead.
- **All changes go through `apply.py`.** Don't run the rename, move or
  label commands by hand. `apply.py` refuses a plan that leaves any
  window without a decision. It moves windows by their own OmniWM ID, never
  the focused window. It skips windows already in place, returns the user to
  their workspace, and logs every change so `--undo` can reverse it.
- **Stability over tidiness.** A project already on one workspace stays there.
  Don't reshuffle workspaces to close gaps in the numbering.

## Steps

### 1. Inventory

```bash
python3 <this skill's directory>/inventory.py
```

It prints JSON and changes nothing. For each cmux window it gives:

- `name`, `repo`, `cwd`
- `state`: `working`, `idle` (an agent waiting), or `shell`
- `last_message` and `last_active`
- `cmux_tab_count`: more than 1 means a window full of tabs
- `omniwm_id`, `omniwm_workspace` and `omniwm_match`

It also flags the windows that need a decision:

- `new`: not open at the last triage run. `null` means there's no log yet.
- `misplaced`: on a pool workspace whose project is a different repo. The
  reason says why, e.g. "repo internal-allocations, but workspace
  'F1 dotfiles' is workspace; its repo's windows are on workspace 2".
- `home`: the one pool workspace that already holds this repo's windows, if
  it isn't the one the window is on.

`layout` is not a flag: it names the `mem layout` that built the window (the
memory repo's `layouts/<name>.yaml`, e.g. the always-on agents' window). Its
layout file owns its name, so never rename it (`apply.py` refuses, and
`mem layout up` would rename it back). Place it like any other window.

**A flag means "consider this", not "move this".** A new window can be exactly
where it belongs. But every flagged window must be weighed deliberately, and
keeping it in place takes a stated `reason` (step 5).

For each workspace it gives its label, layout, tiled count, non-cmux apps,
and `project_repos`. The inventory also reports `current_workspace`.

It also reports `restart` and `restart_workspace` (top level) and each
window's `last_workspace`, `restore_to` and `restore_from`, for
[Restart recovery](#restart-recovery). If `restart` is true, or any window
has a `restore_to`, recover first.

### Restart recovery

cmux restarts often. Afterwards every window is piled on one workspace, the
**pile**, and has a new `id`, so every window reads `new`; names survive.
The pile is usually the workspace the user was looking at, so it can be any
of 1-11 (on 2026-09-30 all 12 windows landed on 7). Each run logs where every
window ended up, by name, and the inventory reads that back:

- `last_workspace`: where the last run left this window. It's `null` when
  the window's name isn't unique now, the log doesn't know the name, or the
  log says the name was another repo's.
- `restart: true` and `restart_workspace: N`: at least 75% of the cmux
  windows (and at least 3) are on workspace N; at least 75% of those have
  new ids; at least 75% of the new ones with unique names are names the log
  knows; and at least two of them were left by the last run somewhere other
  than N and 1. The windows that live on N count as new too (a restart
  renews every id), so a pile on the user's busiest workspace is still
  found. A busy project workspace whose windows kept their ids is not a
  restart, and nor is a window or two closed and reopened under the same
  name. Windows bound for 1 don't count toward the two, so a pile elsewhere
  never moves a window onto 1 on their say-so alone. The price: a restart
  that brings back only one window, or that follows a run with many
  windows opened since, isn't detected; the user moves those by hand. With
  no restart, `restart_workspace` is `null`. If the windows look piled
  (most on one workspace, most `new`) but `restart` is false, say so and
  ask before applying anything: every run logs each window where it is, so
  after one more run the log no longer knows where the piled ones belonged.
- `restore_to` / `restore_from`: the workspace `restore` would put this
  window on, and the pile it takes it from, or `null`. They're set for a
  window on the pile with a new id whose `last_workspace` is any other
  workspace, during a restart. They're also set for a window whose approved
  restore failed last time, or that an undo put back on the pile, while it
  is still the same window (same `id`) on that pile, even if `restart` is
  now false. A window the log already put on the pile gets none: it's home.

Restores are part of the plan, so they share the one go-ahead in step 5.
Show them first, one line each, from the pile to the workspace
(`a work  7 → 3`), and ask as part of that go-ahead: "cmux restarted and
piled N windows on workspace 7: restore them to their workspaces?" On a yes,
each window with a `restore_to` gets `{"id": "<id>", "action": "restore"}`.
`restore` takes no `to` (or exactly its `restore_to`) and no `rename`. Put
the restores first in the plan too.

While the windows are piled, the pile's own project is unknown: the
inventory's `project_repos` for an unlabelled pile is just whichever repo
dominates the pile. Don't label the pile from that; label it for the
windows that live there once the restores are planned. For the same
reason, during a restart the inventory leaves `misplaced` and `home` null
for every window on the pile: plan the ones with no `restore_to` from their
`repo`, `cwd` and `last_workspace`, not from the pile's mix.

**Restores and workspace 1.** A pile on 1 is the one way a window leaves 1.
A pile elsewhere is the one way a window goes *onto* 1: a window the last
run left on 1 gets `restore_to: 1`, because the restart took the user's own
window off their workspace, and putting it back is what they'd do by hand.
Nothing else ever goes onto 1. Every restore that touches workspace 1,
off it (`a  1 → 3 (your workspace)`, a pile on 1) or onto it
(`jan  7 → 1 (your workspace)`), goes on its own line marked
`(your workspace)`, so the user can say no to each one alone. List the ones
onto 1 last, apart from the rest, and ask about them separately: "and put
`jan` back on your workspace 1?" To
decline one, plan it like any window on the pile (it isn't on 1, so not
`skip`; `stay` needs a reason, since it reads `new`). The log knows only
where a window was, not why: after a pile on 1, windows left there
(declined restores, or a restart that wasn't detected) are recorded on 1
too, so a later pile elsewhere offers them onto 1. That's why each one is
asked about.

Everything else gets a normal decision, as in any run:

- a window on the pile with no `restore_to` is planned like any window
  there. If the pile is 1, that means `skip`. That covers windows that were
  on the pile before the restart (`last_workspace` is the pile), windows
  with no usable `last_workspace` (a new name, or one shared by two
  windows), and windows the user dragged onto the pile (same id as last
  run). If the pile is a pool workspace or review, they `stay`, `move` or go
  to `review` as usual (they read `new`, so `stay` needs a reason). Say
  which ones, so the user can move them by hand if they want;
- if the user says no to the restores, every window on the pile gets the
  same normal decision. A declined restore is forgotten: the next run won't
  offer it again;
- windows off the pile, including any on 1 when the pile is elsewhere, are
  planned as usual (`skip` on 1).

`apply.py` refuses a restore unless the window has a `restore_to`, is still
on its `restore_from`, is uniquely matched and uniquely named, and goes to
that workspace. (A window already on its `last_workspace`, 2-11, passes as
`already on N`, so a re-applied plan is harmless.) Floating and scratchpad windows are refused too. It
re-checks all of this against one fresh inventory, taken after the renames
and just before the moves. Undo moves restored windows back to the pile they came off (back
onto 1 only if the pile was 1, off 1 only if the restore put them there),
with the same name and id checks, and they can be restored again
afterwards. Undoing a restore off 1 or onto it also needs that run's own log entry to
show the window left where the restore put it. A window carried onto 1 (its
restore onto 1 failed, or an undo took it back off) is offered again only if
the log last really placed it on 1. The undo has no time limit: it stays the
undo target until a later run changes something. An approved restore that fails keeps its `restore_to`, so the
next run can offer it again. Re-applying a restore plan after it ran reports
`already on N`, except for a window it put on 1: that one is on 1 now, so
the re-applied plan is refused until it's `skip`.

### 2. Group windows into projects

A project is usually a **repo**, and worktrees count as their repo. But a
catch-all repo like the dotfiles repo (`workspace`) hosts unrelated tasks. If
its windows clearly work on different things (different names or
`last_message`), treat each distinct thing as its own project. When unsure,
keep windows together: one project too many is worse than one too few.

### 3. Allocate a workspace to each project

1. **Labelled already?** If a pool workspace's label matches the project, use
   that workspace.
2. **Mostly in one place?** If most of the project's windows already sit on
   one pool workspace that no other project dominates, use that one.
3. **Otherwise** take the lowest-numbered **free** pool workspace. Free means
   no tiled windows and no project label: no label at all, or just the bare
   key (`"3"`, `"F2"`, `"6"` on 11).
4. **Out of workspaces?** Merge the two smallest idle projects onto one
   workspace, and say so in the plan. Never overflow a project onto 10.

### 4. Leave layouts alone

Every workspace is niri, from the OmniWM seed, whatever the project's size.
Niri columns resize the way the user wants; dwindle's split tiles annoyed
them. So never put `layout` in a plan. If the inventory shows a workspace
that isn't niri, it was toggled live (Opt+Shift+L) or the machine predates
the seed change. Leave it, and mention it to the user.

### 5. Plan, then ask once

Write the plan as JSON: **one entry for every window in the inventory.**

```json
{"windows": [
   {"id": "<id>", "action": "move", "to": 2, "reason": "internal-allocations work"},
   {"id": "<id>", "action": "stay", "reason": "new, but it is dotfiles work"},
   {"id": "<id>", "action": "review", "reason": "idle 4 days, plain shell"},
   {"id": "<id>", "action": "skip"},
   {"id": "<id>", "action": "stay", "rename": "dotfiles PRs"}],
 "workspaces": [
   {"number": 2, "label": "2 alloc", "repos": ["internal-allocations"]}]}
```

- **Actions:**
  - `move` needs `to`, a pool workspace: 2 to 9, or 11.
  - `review` means workspace 10.
  - `restore` is only for [Restart recovery](#restart-recovery).
  - `skip` is for workspace 1. Every window there must be `skip` unless
    it's being restored, and so must any window with
    `maybe_user_workspace: true`. That's a window whose title collides with
    another, so it can't be located and might be on workspace 1. Skipped
    windows can't be renamed.
  - `stay` keeps the window where it is. A flagged window can `stay` only
    with a `reason`.
- **Only matched, tiled windows move.** A window whose `omniwm_match` isn't
  `ok` can only `stay`. Give it a unique `rename` so it matches, and it can
  move on the next run. `floating` and `scratchpad` windows never move.
- **`rename`** is optional. Base the name on the window's `last_message`,
  `repo` and `cwd`, following the naming rule in `~/.claude/CLAUDE.md`:
  16 characters at most, with the distinguishing word first. Names must stay
  unique across all windows once the plan has run. Never rename a window
  with a `layout`; if its name looks wrong, tell the user to change its
  layout file.
- **Workspaces:**
  - `label` is `<key> <project>`, where the key is the one the user presses:
    the digit for 2-5, F1-F5 for 6-10, and `6` for 11. Examples: `2 alloc`,
    `F1 dotfiles`, `6 alloc`, `F5 review`. The whole label is at most 12
    characters. OmniWM's bar shows the label *instead of* the number, so the
    key must be in it.
  - `repos` records which repos the label stands for, which is how later
    runs know a workspace's project. It's recorded on every run, even when
    the label doesn't change. So list every project workspace with its label
    and `repos` each time, including ones that are already right.
  - When a pool workspace empties, set its label to the bare key: `"3"` for
    2-5, `"F2"` for 6-10, `"6"` for 11. (For 2-5 the bare key is the number
    itself; 6-11 need theirs written out, or the bar would show the number,
    `7` or `11`, instead of the key.)
  - Label workspace 10 `F5 review` while it holds anything, and `F5` when
    it's empty.
- **Review** is for windows idle for a day or more with nothing pending, plain
  `shell` windows in a home, `~/src` or scratch directory, and anything you
  can't place. Windows already on review stay there unless they clearly
  belong to a project now.

Save the plan to a temp file and dry-run it:

```bash
python3 <this skill's directory>/apply.py --dry-run /tmp/triage-plan.json
```

If it prints `refused`, fix the plan. Every problem names its window. Then
show the user:

- **Restores**, after a restart, one line each, pile to workspace:
  `a work  7 → 3`. Mark every one off or onto 1, on its own line:
  `a  1 → 3 (your workspace)`, `jan  7 → 1 (your workspace)`, with the
  ones onto 1 last and asked about separately.
- **Moves**, one line each: `alloc misc  6 → 2  (misplaced: internal-allocations on F1 dotfiles)`.
  Put these first after any restores, so none gets lost in a table.
- **Flagged windows that stay**, each with its reason.
- **Renames, review and labels.**
- **Tab hoards** (`cmux_tab_count` > 1): suggest splitting live tabs, but
  don't do it.
- **Coverage**: `12 / 12 windows`.

Ask for one go-ahead covering all of it.

### 6. Execute

```bash
python3 <this skill's directory>/apply.py /tmp/triage-plan.json
```

It applies the plan in order: renames, then a fresh inventory, then moves
and labels. Each move is re-checked against that one fresh inventory
(not a new one per move) just before it happens. It then puts every display back on the workspace it showed
and logs the run to `~/.local/state/triage/log.jsonl`. If a move reports
`already on N`, the change was already made, for example by an earlier run in
a rolled-back conversation. That's expected.

**Exit status:**

- **0:** everything was done.
- **2:** the plan was refused, and nothing changed.
- **1:** some steps failed. The JSON lists them under `failed`, and whatever
  did happen is logged. Tell the user what failed, re-run the inventory, and
  then either plan again for what's left or offer `--undo`. If it exits 1
  with no JSON at all, a cmux or OmniWM query failed before the plan was
  checked, so nothing changed. The error is on stderr.

### 7. Verify and report

Re-run the inventory and check that every window is where the plan put it.
Report in a few lines:

- which projects are on which workspaces, with their Caps Lock key: 2-5 are
  Caps+2-5, 6-9 are Caps+F1-F4, 11 is Caps+6, review is Caps+F5
- what was renamed, and what went to review
- anything skipped, with the reason

### Undo

If the user wants the last run reversed:

```bash
python3 <this skill's directory>/apply.py --undo --dry-run   # show what it would do
python3 <this skill's directory>/apply.py --undo
```

It reverses the most recent run that changed something: labels, then layouts,
then moves and restores, then renames. Undoing a restore moves the window
back onto the pile it came off. That is the one time an undo moves a window
onto workspace 1 (the pile was 1) or off it (the restore put it there), and
only a window that restore moved, still under the same name. A plain move
is undone only for a window still under the name it was moved with.
Only runs from before every workspace was niri logged layouts. If the dry
run would set one to dwindle, ask the user first.

- It leaves alone anything the user has changed since, and says so.
- It refuses log entries that are outside triage's bounds.
- Undoing again goes one run further back.
- If an undo fails part-way (exit 1), running `--undo` again finishes it.
- Malformed or out-of-bounds log entries are listed under `ignored`. They
  never run, and they don't block the undo.
- If a retry keeps failing for a reason that won't clear, `apply.py --undo
  --abandon` stops trying to undo that run, so `--undo` can reach older
  ones. It changes nothing on screen. Ask the user before abandoning.
