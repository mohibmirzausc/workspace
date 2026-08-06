# Claude Code Configuration

This directory contains my Claude Code configuration, managed via Nix home-manager.

## Files

- **settings.json** - Global Claude settings including hooks, marketplaces, enabled plugins, and base permissions
- **beep-state** - Beep notification preference (ENABLED/DISABLED)
- **session-journal-state** - Seed for the session journal toggle (see below)
- **hooks/** - Hook scripts that run during Claude Code execution
  - **tool-after.sh** - Plays system beep when tools complete
  - **session-journal** - CLI for the per-workspace session journal
  - **session-journal-*.sh** - Hooks that populate the journal
  - **lib/** - Shared library + HTML template for the journal

## Activation

These files are symlinked to `~/.claude/` via home-manager configuration in `home.nix`.

To apply changes:
```bash
homeswitch
```

## Plugins

Plugins are declared **declaratively in settings.json**, not with the `claude plugin` CLI.

`claude plugin marketplace add` writes to `~/.claude/settings.json`, which home-manager
symlinks read-only into the Nix store. The command therefore fails here with:

```
EACCES: permission denied, open '/nix/store/...-home-manager-files/.claude/settings.json.tmp...'
```

Instead, add two entries to `settings.json` and run `homeswitch`:

- `extraKnownMarketplaces.<marketplace-name>` - registers the marketplace source
- `enabledPlugins["<plugin>@<marketplace>"]` - enables the plugin

Claude Code reads both at startup and installs the plugin into its own cache, so no
mutable state needs to be committed. The marketplace name must match the `name` field
in the source repo's `.claude-plugin/marketplace.json`.

Private marketplace repos are cloned over your existing GitHub auth (SSH keys or `gh`),
so the repo must be readable by your account.

## Session Journal

Each cmux workspace maintains ONE auto-updating HTML page summarizing what its
Claude session is doing, browsable alongside everything else at
**http://localhost:7777**. The point is to monitor many parallel sessions by
skimming pages instead of reading verbose agent logs — and to keep the reasoning
that scrolls out of the chat, so you can come back and ask the agent why it did
something.

**Opt-in.** Nothing is written until you turn it on:

```bash
claude-journal-on       # enable (takes effect on the next session start)
claude-journal-off      # disable (takes effect immediately)
claude-journal-status   # show current state and this workspace's journal path
```

Per-repo overrides: drop a `.no-session-journal` file in a repo root to exclude
it, or `.session-journal` to include it while the global default is off. The
`SESSION_JOURNAL=0` / `=1` env var beats both.

### What lands in a journal

Two tiers. **Hooks** record what cannot be forgotten — session starts, a
truncated first line of each prompt, files touched (coalesced per turn), git
commits, and every subagent's final report. **The agent** records the reasoning
hooks cannot infer: decisions, blockers, milestones. A skill and a
`SessionStart` reminder prompt it to do so; if it doesn't, the hook-written
timeline still stands on its own.

Subagents contribute without being instructed — the `SubagentStop` hook harvests
their final report, which matters because subagents skip skills by design.

### Where journals live

```
~/html-pages/<YYYY-MM-DD>-session-<repo>-<branch>-<workspace-id8>/
  index.html     # the page: polls entries.txt, never reloads itself
  entries.txt    # JSON Lines, append-only, never pruned
  meta.json      # gallery metadata + discovery markers
```

The 8-char workspace-id suffix keeps two workspaces on the same repo and branch
from merging into one journal. The folder keeps its creation date while
`meta.json.date` tracks last-updated, so active journals float to the top of the
gallery.

To find a specific journal:

```bash
session-journal path                                    # this workspace
grep -l "<session-or-workspace-uuid>" ~/html-pages/*-session-*/meta.json
```

### Caveat

Prompts and reasoning are stored **in plaintext** under `~/html-pages/`. If
you're working in a client repo and would rather not have that on disk, add a
`.no-session-journal` file to it.

## What's Not Here

Runtime state remains in `~/.claude/` and is NOT version controlled:
- `history.jsonl` - Session history
- `plugins/` - Plugin cache and metadata
- `debug/`, `file-history/`, `session-env/`, etc. - Runtime state

## Project-Local Overrides

Per-project settings can be added via `.claude/settings.local.json` in each project.
These extend/override the global settings.

Example: `workstations/.claude/settings.local.json` adds `Bash(nix run:*)` permission.
