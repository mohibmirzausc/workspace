#!/usr/bin/env bash
# git-clone-wt: Clone a repository in worktree-ready structure
# Usage: git-clone-wt <repo-url> [target-dir]
#
# This creates a structure like:
#   <repo_name>/
#     main/        (or master, or default branch)
#     .git/
#     .gitignore   (optional, to ignore all subdirs except .git)
#
# After cloning, you can use tree-me to create branches:
#   cd <repo_name>/main
#   tree-me create feature-x  -> creates <repo_name>/feature-x/

set -e

if [ $# -eq 0 ]; then
    cat << 'EOF'
Usage: git-clone-wt <repo-url> [target-dir]

Clone a git repository in a worktree-ready structure.

Examples:
  git-clone-wt https://github.com/user/repo
  git-clone-wt git@github.com:user/repo.git my-project

Structure created:
  <repo_name>/
    main/          # Default branch checked out here
    .git/          # Git directory

After cloning, cd into <repo_name>/main and use tree-me:
  cd <repo_name>/main
  tree-me create feature-x    # Creates <repo_name>/feature-x/
  tree-me switch main         # Switches to <repo_name>/main/

Environment Variables:
  WORKTREE_ROOT: Base directory for clones (default: ~/src.wt)
EOF
    exit 0
fi

REPO_URL="$1"
WORKTREE_ROOT="${WORKTREE_ROOT:-$HOME/src.wt}"

# Extract repo name from URL
REPO_NAME=$(basename "$REPO_URL" .git)

# Allow override of target directory
if [ -n "$2" ]; then
    REPO_NAME="$2"
fi

TARGET_DIR="$WORKTREE_ROOT/$REPO_NAME"

# Check if target already exists
if [ -e "$TARGET_DIR" ]; then
    echo "Error: Directory already exists: $TARGET_DIR" >&2
    exit 1
fi

echo "Cloning $REPO_URL into worktree structure..."
echo "Target: $TARGET_DIR"

# Create the parent directory
mkdir -p "$TARGET_DIR"

# Clone with --bare first, then convert to worktree structure
cd "$TARGET_DIR"

# Clone as bare repository
git clone --bare "$REPO_URL" .bare

# Move .bare to .git
mv .bare .git

# In a bare clone, branches are in refs/heads/* not refs/remotes/origin/*
# Detect the default branch by checking what HEAD points to
DEFAULT_BRANCH=$(git symbolic-ref HEAD 2>/dev/null | sed 's@^refs/heads/@@')

# If HEAD doesn't point to anything, manually detect from available branches
if [ -z "$DEFAULT_BRANCH" ]; then
    # Check if main exists, otherwise try master, otherwise use first branch
    if git show-ref --verify --quiet refs/heads/main; then
        DEFAULT_BRANCH="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        DEFAULT_BRANCH="master"
    else
        # Get first branch from refs/heads
        DEFAULT_BRANCH=$(git branch --list | head -1 | sed 's/^[* ]*//' | xargs)
    fi
fi

# Validate we got a branch
if [ -z "$DEFAULT_BRANCH" ]; then
    echo "Error: Could not detect default branch" >&2
    echo "Available refs:" >&2
    git show-ref >&2
    exit 1
fi

echo "Default branch detected: $DEFAULT_BRANCH"

# Configure it as a non-bare repo
git config --unset core.bare

# CRITICAL SAFETY: Disable pushing from the parent directory
# This prevents accidentally pushing deletions from the repo root
git config remote.origin.pushurl "DISABLED-USE-WORKTREE-DIRECTORIES"
git config --add remote.origin.pushurl ""  # This makes push fail with clear error

# Set up remote tracking refs (needed for tree-me to work properly)
git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

# Fetch to populate remote tracking branches
git fetch origin 2>/dev/null || true

# Set the default remote branch
git remote set-head origin "$DEFAULT_BRANCH" 2>/dev/null || true

# Detach HEAD so the branch isn't considered "checked out" at this location
# Point HEAD to a commit instead of a branch reference
COMMIT=$(git rev-parse "$DEFAULT_BRANCH")
echo "$COMMIT" > .git/HEAD

# Now create worktree for default branch
git worktree add "$DEFAULT_BRANCH" "$DEFAULT_BRANCH"

# Set up tracking for the default branch
cd "$DEFAULT_BRANCH"
git branch --set-upstream-to="origin/$DEFAULT_BRANCH" "$DEFAULT_BRANCH" 2>/dev/null || true

# Re-enable pushing for worktree directories
git config remote.origin.pushurl "$REPO_URL"

cd ..

# Create .gitignore to ignore all directories except .git
# This makes it clear the parent directory is not a working directory
cat > .gitignore << 'GITIGNORE'
# Worktree structure: ignore all branch directories
# Only .git/ should be tracked here - all work happens in worktree subdirectories
/*
!/.git
!/.gitignore
GITIGNORE

# Create a README to explain the structure
cat > README-WORKTREE.md << 'README'
# Worktree Repository Structure

This directory is organized using git worktrees. **Do not work directly in this directory.**

## Structure
```
workspace/
  .git/           # Shared git directory
  main/           # Main branch worktree - work here
  feature-x/      # Feature branch worktree - work here
  feature-y/      # Another feature worktree - work here
```

## Working with this repo
- Always `cd` into a branch directory (e.g., `cd main/`)
- Use `tree-me` commands to create/switch branches
- Each directory is a full working copy of that branch

## Commands
- `tree-me create <branch>` - Create new branch
- `tree-me switch <branch>` - Switch to existing branch
- `tree-me list` - List all worktrees
- `tree-me remove <branch>` - Remove a worktree

⚠️ **Never run `git push` from this parent directory** - it's disabled for safety.
Always push from within a branch directory.
README

# Create a pre-commit hook to prevent accidental commits in parent directory
mkdir -p .git/hooks
cat > .git/hooks/pre-commit << 'HOOK'
#!/bin/sh
# Prevent commits in the worktree parent directory
echo "ERROR: You are trying to commit in the worktree parent directory!"
echo "This directory is only for organizing worktrees."
echo ""
echo "Please cd into a branch directory and commit there:"
echo "  cd main/    (or whichever branch you want to work on)"
echo ""
exit 1
HOOK
chmod +x .git/hooks/pre-commit

echo ""
echo "✓ Repository cloned successfully!"
echo ""
echo "Structure created:"
echo "  $TARGET_DIR/"
echo "    $DEFAULT_BRANCH/          (default branch)"
echo "    .git/                     (git directory)"
echo ""
echo "Next steps:"
echo "  cd $TARGET_DIR/$DEFAULT_BRANCH"
echo "  tree-me create feature-x    # Creates $TARGET_DIR/feature-x/"
echo "  tree-me switch $DEFAULT_BRANCH      # Switches to $TARGET_DIR/$DEFAULT_BRANCH/"
echo ""
