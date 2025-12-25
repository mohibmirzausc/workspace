# Claude Code Configuration

This directory contains my Claude Code configuration, managed via Nix home-manager.

## Files

- **settings.json** - Global Claude settings including hooks, enabled plugins, and base permissions
- **beep-state** - Beep notification preference (ENABLED/DISABLED)
- **hooks/** - Hook scripts that run during Claude Code execution
  - **tool-after.sh** - Plays system beep when tools complete

## Activation

These files are symlinked to `~/.claude/` via home-manager configuration in `home.nix`.

To apply changes:
```bash
homeswitch
```

## What's Not Here

Runtime state remains in `~/.claude/` and is NOT version controlled:
- `history.jsonl` - Session history
- `plugins/` - Plugin cache and metadata
- `debug/`, `file-history/`, `session-env/`, etc. - Runtime state

## Project-Local Overrides

Per-project settings can be added via `.claude/settings.local.json` in each project.
These extend/override the global settings.

Example: `workstations/.claude/settings.local.json` adds `Bash(nix run:*)` permission.
