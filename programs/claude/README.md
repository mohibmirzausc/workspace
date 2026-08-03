# Claude Code Configuration

This directory contains my Claude Code configuration, managed via Nix home-manager.

## Files

- **settings.json** - Global Claude settings including hooks, marketplaces, enabled plugins, and base permissions
- **beep-state** - Beep notification preference (ENABLED/DISABLED)
- **hooks/** - Hook scripts that run during Claude Code execution
  - **tool-after.sh** - Plays system beep when tools complete

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

## What's Not Here

Runtime state remains in `~/.claude/` and is NOT version controlled:
- `history.jsonl` - Session history
- `plugins/` - Plugin cache and metadata
- `debug/`, `file-history/`, `session-env/`, etc. - Runtime state

## Project-Local Overrides

Per-project settings can be added via `.claude/settings.local.json` in each project.
These extend/override the global settings.

Example: `workstations/.claude/settings.local.json` adds `Bash(nix run:*)` permission.
