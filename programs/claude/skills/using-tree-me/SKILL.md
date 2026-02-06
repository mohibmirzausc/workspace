---
name: using-tree-me
description: Use when working with git repositories and worktrees - teaches Claude how to use tree-me for cloning, branch management, and worktree workflows
---

# Tree-me: Git Worktree Management Tool

<CRITICAL>
Use this skill whenever:
- User wants to clone a repository
- User wants to create a new branch
- User wants to switch between branches
- User is working with multiple branches simultaneously
- User mentions git worktrees
</CRITICAL>

## What is tree-me?

tree-me is a unified git worktree management tool that organizes repositories in a structure where each branch is a separate directory. This allows working on multiple branches simultaneously without switching contexts.

## Directory Structure

After cloning with tree-me, the structure looks like:
```
~/src.wt/
  repo/                    # Parent directory (never work here!)
    main/                  # Main branch - work here
    feature-x/             # Feature branch - work here
    feature-y/             # Another feature - work here
    .git/                  # Shared git directory
    README-WORKTREE.md     # Explanation of structure
```

**IMPORTANT:** The parent directory shows a detached HEAD - this is normal! Always work inside branch directories.

## Commands

### Clone a Repository
```bash
tree-me clone https://github.com/user/repo
tree-me clone git@github.com:user/repo.git custom-name
```

- Creates `~/src.wt/repo/main/` structure automatically
- Auto-cd's you to the main branch directory
- Sets up safety features (no push from parent, pre-commit hook)

**Aliases:** `tm clone`

### Create a New Branch
```bash
tree-me create feature-name              # Creates from main/master
tree-me create feature-name base-branch  # Creates from specific branch
```

- Creates `~/src.wt/repo/feature-name/` directory
- Auto-cd's you to the new branch
- Shows push command for first push: `git push -u origin feature-name`
- Integrates with Graphite if available

**IMPORTANT:** New branches are NOT set up to track remote by default. On first push, use:
```bash
git push -u origin branch-name
```

### Switch Between Branches
```bash
tree-me switch branch-name
```

- Switches to existing branch worktree
- Creates worktree if branch exists remotely but not locally
- Auto-cd's you to the branch directory
- Sets up tracking if branch exists on remote

**Aliases:** `tree-me sw`

### Checkout a GitHub PR
```bash
tree-me pr 123
tree-me pr https://github.com/org/repo/pull/123
```

- Creates `~/src.wt/repo/pr-123/` directory
- Fetches PR and checks it out
- Auto-cd's you to the PR directory

### List All Worktrees
```bash
tree-me list
```

**Aliases:** `tree-me ls`

### Remove a Worktree
```bash
tree-me remove branch-name
```

**Aliases:** `tree-me rm`

### Clean Up Stale Worktrees
```bash
tree-me prune
```

## Workflow Examples

### Starting Fresh with a Repository
```bash
tree-me clone https://github.com/user/awesome-project
# Auto-cd'd to ~/src.wt/awesome-project/main/

# Create feature branch
tree-me create add-auth-system
# Auto-cd'd to ~/src.wt/awesome-project/add-auth-system/

# Work on feature
vim src/auth.js
git add .
git commit -m "add authentication"

# First push (sets up tracking)
git push -u origin add-auth-system

# Switch back to main
tree-me switch main
# Now in ~/src.wt/awesome-project/main/

# Create another feature
tree-me create fix-bug-123
# Now in ~/src.wt/awesome-project/fix-bug-123/
```

### Working on Multiple Features Simultaneously
```bash
cd ~/src.wt/awesome-project/main
tree-me create feature-a
# Work on feature-a...

tree-me create feature-b
# Work on feature-b...

tree-me switch feature-a
# Back to feature-a, continue working...

# Each directory maintains its own state:
# - Uncommitted changes
# - Stash
# - Branch history
```

### Reviewing a PR
```bash
cd ~/src.wt/repo/main
tree-me pr 456
# Auto-cd'd to ~/src.wt/repo/pr-456/

# Review code, test, etc.
npm test

# Switch back to your work
tree-me switch my-feature
```

## Important Safety Features

### Parent Directory Protection
The parent directory (`~/src.wt/repo/`) has safety features:

1. **Push disabled** - Can't accidentally push deletions
2. **Pre-commit hook** - Prevents commits in parent directory
3. **Detached HEAD** - Normal and expected, don't try to fix it

**Always work in branch directories**, never in the parent!

### Tracking and Pushing

**Existing branches** (via `tree-me switch`):
- Automatically set up to track `origin/branch-name`
- `git pull` and `git push` work immediately

**New branches** (via `tree-me create`):
- NOT tracked by default
- First push requires: `git push -u origin branch-name`
- Subsequent pushes: `git push` works normally

This matches standard git behavior and gives helpful error messages.

## Integration Features

### Graphite Integration
If Graphite CLI (`gt`) is installed and initialized:
- New branches are automatically tracked with Graphite
- Stacked diffs workflow enabled
- Shows parent relationships

### Auto-cd
When using tree-me in shell (after `source <(tree-me shellenv)`):
- Automatically cd's to worktree after clone/create/switch
- Tab completion for commands and branch names

### Environment Variables
- `WORKTREE_ROOT`: Base directory (default: `~/src.wt`)

## Common Patterns

### Rebasing on Main
```bash
cd ~/src.wt/repo/feature-branch

# Option 1: Rebase on remote main
git pull -r origin main

# Option 2: Rebase on local main worktree
git rebase main  # or: git rebase ../main
```

### Cleaning Up Branches
```bash
tree-me list                    # See all worktrees
tree-me remove old-feature      # Remove specific worktree
tree-me prune                   # Clean up stale references
```

### Using with Multiple Repos
```bash
tree-me clone https://github.com/user/frontend
tree-me clone https://github.com/user/backend

# Each repo gets its own directory structure:
# ~/src.wt/frontend/main/, ~/src.wt/frontend/feature-x/
# ~/src.wt/backend/main/, ~/src.wt/backend/feature-y/
```

## Troubleshooting

### "fatal: 'branch' is already used by worktree"
The branch already has a worktree. Use `tree-me switch branch` to go there.

### "No tracking information for current branch"
For new branches, set up tracking:
```bash
git push -u origin branch-name
```

### Parent directory shows detached HEAD
This is normal and expected! The parent is just a container. Work in branch directories.

### Can't push from parent directory
This is intentional! Always push from branch directories like `main/` or `feature-x/`.

## When to Use tree-me

✅ **Use tree-me when:**
- Cloning any repository
- Creating new feature branches
- Switching between branches frequently
- Working on multiple features simultaneously
- Reviewing PRs without disrupting current work
- Need to quickly compare code across branches

❌ **Don't use tree-me for:**
- Repositories that don't need multiple active branches
- Temporary clones for quick checks (just use `git clone`)

## Assistant Guidelines

When helping users with git workflows:

1. **Always suggest tree-me for cloning**: Instead of `git clone`, use `tree-me clone`
2. **Use tree-me for branch creation**: Instead of `git checkout -b`, use `tree-me create`
3. **Remind about push command**: After creating a branch, remind about `git push -u origin branch-name`
4. **Explain the structure**: Help users understand they should work in branch directories, not parent
5. **Leverage multiple worktrees**: Suggest using multiple branch directories when appropriate

## Quick Reference

| Task | Command |
|------|---------|
| Clone repo | `tree-me clone <url>` |
| Create branch | `tree-me create <name>` |
| Switch branch | `tree-me switch <name>` |
| List worktrees | `tree-me list` |
| Remove worktree | `tree-me remove <name>` |
| Checkout PR | `tree-me pr <number>` |
| First push | `git push -u origin <branch>` |
| Update from main | `git pull -r origin main` |

## Alias
The user has configured: `alias tm='tree-me'`

So `tm clone`, `tm create`, `tm switch`, etc. all work.
