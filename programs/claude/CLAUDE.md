# Global instructions

## Name your cmux workspace after the task

I run each session in its own cmux window and find them by name, so an
accurate name is how I navigate. cmux's automatic name is taken from early
terminal output and is often noise (a warning banner, half a sentence).

When `$CMUX_WORKSPACE_ID` is set, rename this session's workspace as soon as
the task is clear, usually right after my first real request:

```bash
cmux workspace-action --action rename --title "<repo>: <task>"
```

- `<repo>` is the git repo (or directory) you are working in; `<task>` is 2-5
  words, e.g. `workspace: omniwm dwindle keys`, `release-ops: cve triage`.
  Keep it under ~40 characters.
- Rename again only if the task genuinely changes, not every turn.
- Do it silently. It is housekeeping, not something to report.
- Skip it if you are a subagent or fork. Subagents inherit the parent's
  environment, so the command would rename the parent's workspace.
- Never pass `--workspace`. With no flag, cmux targets `$CMUX_WORKSPACE_ID`,
  which is this session's workspace even while I am focused on another window.
