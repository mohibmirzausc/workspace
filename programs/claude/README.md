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

### Currently declared

| Plugin | Marketplace | Source |
| --- | --- | --- |
| `superpowers` | `superpowers-marketplace` | `obra/superpowers-marketplace` |
| `momentum` | `momentum-tracker` | `mechanical-orchard/momentum-tracker` |

Both halves must be present for a plugin to be reproducible. `superpowers` was listed in
`enabledPlugins` without a matching `extraKnownMarketplaces` entry, so it only resolved
because its marketplace had been registered imperatively in `~/.claude/plugins/` — a
fresh machine would have enabled a plugin from an unknown marketplace. Its source is now
declared too.

### Upgrading a plugin

`settings.json` declares *which* plugins are enabled, not which **version**. There is
no version or pin field in `extraKnownMarketplaces` / `enabledPlugins`, and `homeswitch`
does not upgrade plugins — once a plugin is in the cache, Claude Code keeps using that
version until an explicit update runs. So a plugin can sit silently stale for months
while upstream moves on (momentum did exactly this: declared at 0.14.0, upstream 0.17.0).

Unlike `claude plugin marketplace add`, the update commands only write to the mutable
`~/.claude/plugins/` cache, never to `settings.json` — so they work fine here despite
the read-only Nix store symlink:

```bash
claude plugin marketplace update momentum-tracker && \
    claude plugin update momentum@momentum-tracker
```

Restart Claude Code afterwards to load the new version, and confirm with
`claude plugin list`.

To avoid doing this by hand, open `/plugin` → Marketplaces → select the marketplace →
enable auto-update. That toggle is mutable per-machine state, so Nix cannot capture it
and it must be set once per machine. There *is* an `autoUpdate: true` field on
`extraKnownMarketplaces` entries, but it is honoured only in **managed** (org-deployed)
settings, so it cannot be used from this repo's user-scope `settings.json`.

## What's Not Here

Runtime state remains in `~/.claude/` and is NOT version controlled:
- `history.jsonl` - Session history
- `plugins/` - Plugin cache and metadata
- `debug/`, `file-history/`, `session-env/`, etc. - Runtime state

## Project-Local Overrides

Per-project settings can be added via `.claude/settings.local.json` in each project.
These extend/override the global settings.

Example: `workstations/.claude/settings.local.json` adds `Bash(nix run:*)` permission.
