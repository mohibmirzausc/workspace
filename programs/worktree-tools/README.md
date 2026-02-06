# Git Worktree Tools

This directory contains complementary git worktree management tools integrated into the home-manager configuration.

## Recommended Workflow

**1. Clone a repository:**
```bash
tree-me clone https://github.com/user/repo
# Creates: ~/src.wt/repo/main/
```

**2. Work on a new feature:**
```bash
cd ~/src.wt/repo/main
tree-me create feature-x
# Creates: ~/src.wt/repo/feature-x/
# Auto-cd's you to ~/src.wt/repo/feature-x/
```

**3. Switch between branches:**
```bash
tree-me switch main
# Takes you to: ~/src.wt/repo/main/
```

**Directory structure:**
```
~/src.wt/
  repo/                    # Parent directory (detached HEAD - don't work here!)
    main/                  # Default branch - work here
    feature-x/             # Feature branch - work here
    feature-y/             # Another feature - work here
    .git/                  # Shared git directory
    .gitignore             # Ignores all branch directories
    README-WORKTREE.md     # Explanation of the structure
```

**Important:** The parent directory (`repo/`) will show a detached HEAD - this is normal and expected! Always work inside the branch directories (`main/`, `feature-x/`, etc.).

## Tools Overview

### tree-me (Command-line tool)
**Source**: https://github.com/haacked/dotfiles/blob/main/bin/tree-me
**Article**: https://haacked.com/archive/2025/11/21/tree-me/

A minimal, git-like command-line wrapper for worktree management with organized directory structure.

**Features**:
- Clone repositories in worktree-ready structure (`tree-me clone`)
- Clean command-line interface (clone, switch, create, pr, list, remove, prune)
- Smart worktree detection: uses parent dir if already in worktree structure
- Falls back to `~/src.wt/<repo>/<branch>` for standard repos
- Auto-cd functionality after creating/switching worktrees
- Tab completion for commands and branch names
- Automatic Graphite (gt) integration when available
- GitHub PR support via `gh` CLI

**Usage**:
```bash
tree-me clone https://github.com/user/repo  # Clone in worktree structure
tree-me clone git@github.com:user/repo.git myname  # Clone with custom name
tree-me switch feature-branch        # Switch to existing branch
tree-me create my-feature            # Create new branch (from main/master)
tree-me create my-feature develop    # Create new branch from develop
tree-me pr 123                       # Checkout GitHub PR #123
tree-me list                         # List all worktrees
tree-me remove old-branch            # Remove a worktree
tree-me prune                        # Clean stale worktree files
```

**Configuration**:
- `WORKTREE_ROOT` is set to `~/src.wt` in the home-manager configuration
- Automatically detects if you're in a worktree structure and uses that
- Shell integration is automatically configured via `source <(tree-me shellenv)`

### wt (Interactive switcher)
**Already configured**: git-worktree-switcher
**Location**: Line 54 in home.nix

An fzf-based interactive worktree switcher.

## Integration

All tools are integrated in `home.nix`:

```nix
# Packages installed
((callPackage ./programs/worktree-tools/package.nix {}).tree-me)

# Shell integration (zsh)
export WORKTREE_ROOT="$HOME/src.wt"
source <(tree-me shellenv)  # Enables auto-cd and completion

# Aliases
alias tm='tree-me'
```

## Workflow Examples

### Starting a new project:
```bash
# Clone in worktree structure
tree-me clone https://github.com/user/awesome-project
# Auto-cd's you to ~/src.wt/awesome-project/main

# Create feature branch
tree-me create add-auth-system

# You're now in ~/src.wt/awesome-project/add-auth-system/
# Work on your feature...

# Switch back to main
tree-me switch main

# Create another feature
tree-me create fix-bug-123
```

### Working with PRs:
```bash
cd ~/src.wt/repo/main
tree-me pr 456                    # Checks out PR #456 to repo/pr-456/
tree-me pr https://github.com/... # Also works with URLs
```

### Listing and cleaning up:
```bash
tree-me list                      # See all worktrees
tree-me remove old-feature        # Remove a worktree
tree-me prune                     # Clean up stale admin files
```

## Which Tool to Use?

### Use `tree-me` for:
- Everything! It's your all-in-one worktree tool
- Cloning repositories
- Creating and switching branches
- Managing GitHub PRs
- Command-line workflow with Graphite integration

### Use `wt` when:
- You want quick fuzzy-finding between worktrees
- You prefer minimal keystrokes
- You're already familiar with fzf

## Directory Structure

```
programs/worktree-tools/
├── README.md           # This file
├── package.nix         # Nix package definitions
└── tree-me.sh          # tree-me script (includes clone command)
```

## Notes

- `tree-me` is designed for bash/zsh shells
- Nushell users can call `tree-me` directly but won't get auto-cd features
- `tree-me` optionally uses `gh` (GitHub CLI) for PR operations
- `tree-me` optionally integrates with Graphite for stacked diffs
- Both `tree-me` and `wt` can coexist and complement each other
- `tree-me` is smart about detecting worktree structures
