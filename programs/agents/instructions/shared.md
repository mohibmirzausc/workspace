# Global instructions

## Name your cmux workspace after the task

I run each session in its own cmux window and find them by name, so an
accurate name is how I navigate. cmux's automatic name is taken from early
terminal output and is often noise (a warning banner, half a sentence).

When `$CMUX_WORKSPACE_ID` is set, rename this session's workspace as soon as
the task is clear, usually right after my first real request:

```bash
cmux workspace-action --action rename --title "<task>"
```

- **16 characters at most.** The name shows on the sketchybar workspace bar,
  where each window pill is cut at 16 characters (`WM_WIN_CHARS` in
  darwin.nix; wider pills run under the notch). Anything past 16 is invisible,
  so a longer name is no better than a cut-off one.
- Put the distinguishing word first, since the end is what gets cut:
  `dwindle keys`, `cve triage`, `mx mouse tilt`, not `workspace: omniwm
  dwindle keys`. Skip the repo name unless it is the distinguishing part
  (`release-ops cve`).
- Rename again only if the task genuinely changes, not every turn.
- Do it silently. It is housekeeping, not something to report.
- Skip it if you are a subagent or fork. Subagents inherit the parent's
  environment, so the command would rename the parent's workspace.
- Never pass `--workspace`. With no flag, cmux targets `$CMUX_WORKSPACE_ID`,
  which is this session's workspace even while I am focused on another window.

## Search with ripgrep, not grep

Use `rg` instead of `grep -r` when searching files. It is faster and skips
`.gitignore`d paths by default, so it does not return duplicate hits from
`.worktrees/` or `node_modules/`. Add `--no-ignore` when you need to search
ignored files. `rg` is installed via `home.nix`.

## Work in a git worktree, not the main checkout

Several agents work in the same repos at once. The checkout named after the
repo (`~/src/workspace`, `~/src/crew`) is shared by all of them, so it stays
on `main`, clean, matching `origin/main`. Changing it under another session
stomps on that session's work.

For any change you will commit, branch a worktree off the latest `main`:

```bash
git fetch origin
git worktree add .worktrees/<topic> -b <type>/<topic> origin/main
cd .worktrees/<topic>
```

- Make every edit, commit and push there. In the main checkout, never switch
  branches, commit, or leave edits. The only change it gets is
  `git pull --ff-only` on `main`.
- Check that `.worktrees/` is ignored (`git check-ignore -q .worktrees/x`).
  If it isn't, add it to `.git/info/exclude`, which stays local, rather than
  editing the repo's `.gitignore`.
- Rebase onto the latest `origin/main` before opening a PR, and again before
  it merges.
- After the PR merges, remove the worktree and its branch
  (`git worktree remove .worktrees/<topic>`, `git branch -d <type>/<topic>`),
  then fast-forward the main checkout.
- Reading, searching and running things without changing them need no
  worktree.
- A repo's own `AGENTS.md` or `CLAUDE.md` wins over this rule, for repos
  whose main checkout is also live data.
