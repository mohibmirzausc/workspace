# Git Worktree Tools

This directory contains complementary git worktree management tools integrated into the home-manager configuration.

## Recommended Workflow

**1. Clone a repository:**
```bash
git-clone-wt https://github.com/user/repo
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

### 1. git-clone-wt (Clone wrapper)

A wrapper around `git clone` that sets up repositories in a worktree-ready structure.

**Features**:
- Clones into `<repo>/main/` structure automatically
- Sets up shared `.git` directory at repo root
- Works seamlessly with `tree-me`
- Detects default branch (main/master/etc.)

**Usage**:
```bash
git-clone-wt https://github.com/user/repo         # Clone to ~/src.wt/repo/main/
git-clone-wt git@github.com:user/repo.git myname  # Clone to ~/src.wt/myname/main/
```

### 2. tree-me (Command-line tool)
**Source**: https://github.com/haacked/dotfiles/blob/main/bin/tree-me
**Article**: https://haacked.com/archive/2025/11/21/tree-me/

A minimal, git-like command-line wrapper for worktree management with organized directory structure.

**Features**:
- Clean command-line interface (switch, create, pr, list, remove, prune)
- Smart worktree detection: uses parent dir if already in worktree structure
- Falls back to `~/src.wt/<repo>/<branch>` for standard repos
- Auto-cd functionality after creating/switching worktrees
- Tab completion for commands and branch names
- Automatic Graphite (gt) integration when available
- GitHub PR support via `gh` CLI

**Usage**:
```bash
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

### 3. gw (TUI tool)
**Source**: https://github.com/peterwwillis/junkdrawer/blob/main/gw.sh

An interactive Terminal User Interface (TUI) wrapper using `dialog` for visual worktree management.

**Features**:
- Interactive dialog-based menu system
- Visual selection of worktrees with commit dates
- Form-based worktree creation
- Convert existing repos to worktree layout
- Sort worktrees by commit date or default order
- Maintains directory context when switching

**Usage**:
```bash
gw              # Launch interactive menu
gw switch       # Switch worktree (with dialog menu)
gw add          # Add worktree (with dialog form)
gw convert      # Convert repo to worktree structure
gw remove       # Remove current worktree
gw list         # List worktrees in dialog
```

**Configuration**:
- Set `GW_SORT_MODE=date` to sort by commit date (newest first)
- Set `GW_SORT_MODE=default` for git's default order
- Requires `dialog` package (automatically installed)

### 4. wt (Interactive switcher)
**Already configured**: git-worktree-switcher
**Location**: Line 54 in home.nix

An fzf-based interactive worktree switcher.

## Integration

All tools are integrated in `home.nix`:

```nix
# Packages installed
((callPackage ./programs/worktree-tools/package.nix {}).git-clone-wt)
((callPackage ./programs/worktree-tools/package.nix {}).tree-me)
((callPackage ./programs/worktree-tools/package.nix {}).gw)
dialog  # Required for gw

# Shell integration (zsh)
export WORKTREE_ROOT="$HOME/src.wt"
source <(tree-me shellenv)  # Enables auto-cd and completion
source gw.sh                # Enables gw command (if dialog available)
```

## Workflow Examples

### Starting a new project:
```bash
# Clone in worktree structure
git-clone-wt https://github.com/user/awesome-project

# Start working
cd ~/src.wt/awesome-project/main

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

### Use `git-clone-wt` when:
- Starting fresh with a new repository
- You want the worktree structure from the beginning
- You prefer all branches at the same directory level

### Use `tree-me` when:
- You prefer command-line interfaces
- You want scriptable operations
- You need GitHub PR integration
- You want Graphite integration
- You prefer explicit, git-like commands

### Use `gw` when:
- You prefer visual, menu-driven interfaces
- You want to see worktrees with commit dates
- You need to convert existing repos
- You prefer form-based input for new worktrees

### Use `wt` when:
- You want quick fuzzy-finding between worktrees
- You prefer minimal keystrokes
- You're already familiar with fzf

## Directory Structure

```
programs/worktree-tools/
├── README.md           # This file
├── package.nix         # Nix package definitions
├── git-clone-wt.sh     # git-clone-wt script
├── tree-me.sh          # tree-me script
└── gw.sh               # gw script
```

## Notes

- `git-clone-wt`, `tree-me` and `gw` are designed for bash/zsh shells
- Nushell users can call `tree-me` directly but won't get auto-cd or TUI features
- `gw` requires `dialog` to be installed (handled automatically)
- `tree-me` optionally uses `gh` (GitHub CLI) for PR operations
- All four tools (`git-clone-wt`, `tree-me`, `gw`, `wt`) can coexist and complement each other
- `tree-me` is smart about detecting worktree structures created by `git-clone-wt`
