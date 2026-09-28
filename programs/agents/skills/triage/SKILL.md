---
name: triage
description: Use when the user says "/triage", "triage my windows", "organize my terminals", "clean up my workspaces", or complains they cannot find a session. Groups open cmux windows into projects, gives each project its own OmniWM workspace (2-10, dwindle for small projects, niri for large ones), labels the workspaces, fixes junk window names, and proposes what to close.
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

OmniWM persists labels and layouts into `~/.config/omniwm/settings.toml`, so
the live file drifts from the repo seed while projects are allocated. That is
expected. These are runtime state, so don't copy them back into
`programs/omniwm/settings.toml`. A rebuild that changes the seed resets them,
and the next triage run puts them back.

## Rules

- **Workspace 1 is the user's.** Never move a window into it or out of it,
  and never relabel or re-layout it. Report what is there, but leave it alone.
- **The pool is workspaces 2-10.** Projects are allocated from it.
- **Only cmux windows move.** Leave every other app where it is (browsers,
  Slack, Docker). Scratchpad and floating windows are the user's comms setup,
  so never touch them either.
- **Nothing closes without an explicit, per-item OK.** Closing is the only
  step that can lose work.
- **Never guess which window to move.** Move only windows whose
  `omniwm_match` is `ok`, by their `omniwm_id`. Never use
  `omniwmctl command move-to-workspace`: it moves whatever window is focused,
  which may not be the one you mean.
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

For each workspace it gives its label, layout, tiled count and non-cmux apps.

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
   no tiled windows and no label.
4. **Out of workspaces?** Merge the two smallest idle projects onto one
   workspace, and say so in the plan.

### 4. Pick the layout from the project's size

Count the windows that will be tiled on the workspace, including other apps
already there:

- **4 or fewer: dwindle.** Everything stays visible.
- **5 or more: niri.** Windows keep their size and scroll.
- **Hysteresis:** only switch a niri workspace back to dwindle at 3 or fewer.
  That stops it flipping every run when a project hovers around 4-5.

OmniWM can only set the layout of the **active** workspace. So switch to it,
set the layout, and switch back to where the user was (note the current
workspace number first):

```bash
omniwmctl command switch-workspace <N>
omniwmctl command set-workspace-layout <dwindle|niri>
omniwmctl command switch-workspace <where-the-user-was>
```

### 5. Plan, then ask once

Show one table: each project, its windows, the target workspace and layout,
and the label. Below it, list separately:

- **Renames**: windows whose name is junk.
- **Close candidates**: idle for a day or more with nothing pending, and
  plain `shell` windows sitting in a home or `~/src` directory. Give the
  reason for each.
- **Tab hoards** (`cmux_tab_count` > 1): suggest splitting live tabs into their
  own windows, but don't do it automatically.

Ask for a single go-ahead for the renames, moves, labels and layouts. Closing
is asked separately, item by item.

### 6. Execute, in this order

1. **Rename** junk-named windows. Base the name on `last_message`, `repo` and
   `cwd`, using the naming rule in `~/.claude/CLAUDE.md`: 16 characters at
   most, with the distinguishing word first. Here `--workspace` is required,
   because you are renaming other sessions' windows:

   ```bash
   cmux workspace-action --workspace <cmux_workspace> --action rename --title "<name>"
   ```

2. **Re-run the inventory.** Renames change titles, and titles are how
   windows are matched to OmniWM, so matches taken from before the renames
   are stale.
3. **Move** each window:
   `omniwmctl window move-to-workspace <omniwm_id> <N>`.
4. **Set layouts** as in step 4.
5. **Label** each project's workspace with a short label on the bar
   (10 characters or fewer):
   `omniwmctl workspace rename <N> "<label>"`. Clear the label of any pool
   workspace that is now empty: `omniwmctl workspace rename <N> ""`.
6. **Close** only the windows the user approved, one at a time.

### 7. Verify and report

Re-run the inventory and check that every moved window landed where planned.
Report in a few lines: which projects are on which workspaces (with their
Caps Lock key: 2-5 are Caps+2-5, 6-9 are Caps+F1-F4, 10 is Caps+F5), what was
renamed and closed, and anything skipped with the reason. Skips include
ambiguous matches and windows on workspace 1.
