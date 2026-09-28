---
name: triage
description: Use when the user says "/triage", "triage my windows", "organize my terminals", "clean up my workspaces", or complains they cannot find a session. Groups open cmux windows into projects, gives each project its own OmniWM workspace (2-9, dwindle for small projects, niri for large ones), labels the workspaces, fixes junk window names, and parks anything it is unsure about on workspace 10 ("review"). It never closes windows.
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
`programs/omniwm/settings.toml`. Rebuilds keep them: when the seed is
re-installed, the pool workspaces' `displayName` and `layoutType` are carried
over from the live file (`programs/omniwm/keep-workspace-state.py`).

## Rules

- **Workspace 1 is the user's.** Never move a window into it or out of it,
  and never relabel or re-layout it. Report what is there, but leave it alone.
- **The pool is workspaces 2-9.** Projects are allocated from it.
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
   workspace, and say so in the plan. Never overflow a project onto 10.

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
- **Review**: windows headed for workspace 10, each with its reason. A window
  goes to review when it has been idle for a day or more with nothing pending,
  when it is a plain `shell` in a home, `~/src` or scratch directory, or when
  you can't tell which project it belongs to. Windows already on `review` stay
  there unless they clearly belong to a project now.
- **Tab hoards** (`cmux_tab_count` > 1): suggest splitting live tabs into their
  own windows, but don't do it automatically.

Ask for a single go-ahead covering everything: renames, moves (including to
review), labels and layouts.

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
5. **Label** each project's workspace as `<key> <project>`, where the key is
   the one the user presses to get there. That's the digit for 2-5 and F1-F5
   for 6-10: `2 alloc`, `F1 dotfiles`, `F5 review`. OmniWM's bar shows the
   label *instead of* the workspace number, so a label without the key hides
   which button to press. Keep the whole label to 12 characters or fewer:

   ```bash
   omniwmctl workspace rename <N> "<key> <project>"
   ```

   When a pool workspace empties, reset its label to the bare key. For 2-5
   that's `omniwmctl workspace rename <N> ""`, which falls back to the digit.
   For 6-10 it's `omniwmctl workspace rename <N> "F<N-5>"`; an empty label
   there would show "6"-"10", which isn't a key.
6. **Label workspace 10 `F5 review`** while it holds anything, and reset it
   to `F5` when it's empty. It keeps whatever layout the window count calls for
   (step 4), like any other workspace.

### 7. Verify and report

Re-run the inventory and check that every moved window landed where planned.
Report in a few lines: which projects are on which workspaces (with their
Caps Lock key: 2-5 are Caps+2-5, 6-9 are Caps+F1-F4, review is Caps+F5), what was
renamed, what went to review, and anything skipped with the reason. Skips include
ambiguous matches and windows on workspace 1.
