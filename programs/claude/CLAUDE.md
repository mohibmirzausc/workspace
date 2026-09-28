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
