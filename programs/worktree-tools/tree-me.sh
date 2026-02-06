#!/usr/bin/env bash
# Minimal git worktree helper - leverages git's native capabilities
# Usage: tree-me <command> [options]
#
# For auto-cd and tab completion, add this to your ~/.bashrc or ~/.zshrc:
#   source <(tree-me shellenv)
#
# This enables:
# - Automatic cd to worktree after switch/create/pr commands
# - Tab completion for commands and branch names

set -e

# Worktree organization: ~/src.wt/<repo>/<branch> or <repo>/<branch> (if already in worktree structure)
WORKTREE_ROOT="${WORKTREE_ROOT:-$HOME/dev/worktrees}"

# Detect if we're already in a worktree structure (where parent dir contains .git)
# If so, use parent dir as the worktree root for this repo
get_worktree_root_for_repo() {
    local repo="$1"
    local git_common_dir

    # Check if we're in a worktree by looking for .git file (not directory)
    if [ -f .git ]; then
        git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"
        if [ -n "$git_common_dir" ]; then
            # We're in a worktree, use the parent of the common git dir
            dirname "$git_common_dir"
            return
        fi
    fi

    # Default: use WORKTREE_ROOT
    echo "$WORKTREE_ROOT/$repo"
}

# Check if Graphite is initialized in this repo
is_graphite_repo() {
    command -v gt >/dev/null 2>&1 && gt repo name >/dev/null 2>&1
}

# Track branch with Graphite, specifying parent
graphite_track() {
    local branch="$1"
    local parent="$2"
    if is_graphite_repo; then
        echo "📊 Tracking branch with Graphite…"
        if [ -n "$parent" ]; then
            gt track "$branch" --parent "$parent" --force 2>/dev/null || gt track "$branch" --force 2>/dev/null || true
        else
            gt track "$branch" --force 2>/dev/null || true
        fi
    fi
}

# Show help if no arguments
show_help() {
    cat << 'EOF'
Usage: tree-me <command> [options]

Git-like worktree management with organized directory structure.
Automatically integrates with Graphite (gt) when available.

Commands:
  clone <repo-url> [name]       Clone repository in worktree-ready structure
  switch, sw <branch>           Switch to an existing branch in new worktree
  create <branch> [base]        Create new branch in worktree (default: main/master)
  pr <number|url>               Checkout GitHub PR in worktree (uses gh)
  list, ls                      List all worktrees
  remove, rm <branch>           Remove a worktree
  prune                         Remove worktree administrative files
  shellenv                      Output shell function for auto-cd (source this)

Examples:
  tree-me clone https://github.com/user/repo
  tree-me clone git@github.com:user/repo.git myname
  tree-me switch feature-branch
  tree-me create my-feature
  tree-me create my-feature develop
  tree-me pr 123
  tree-me pr https://github.com/org/repo/pull/123
  tree-me list
  tree-me remove old-branch
  tree-me prune

Setup auto-cd:
  Add to ~/.bashrc or ~/.zshrc:
    source <(tree-me shellenv)

Worktrees are organized at: $WORKTREE_ROOT/<repo>/<branch>
Set WORKTREE_ROOT to customize the location (default: ~/dev/worktrees)

Graphite Integration:
  When Graphite (gt) is installed and initialized in a repo, tree-me
  automatically tracks new branches with Graphite after creation.
  This enables seamless use of gt commands (modify, submit, sync, etc.)
  in worktrees without manual 'gt track' calls.
EOF
}

if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

# Get repo name from git
get_repo_name() {
    basename "$(git remote get-url origin 2>/dev/null || git rev-parse --show-toplevel)" .git
}

# Get default base branch
get_default_base() {
    # Try refs/remotes/origin/HEAD first (standard setup)
    local default_branch
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

    # If that fails, check HEAD directly (worktree setup)
    if [ -z "$default_branch" ]; then
        default_branch=$(git symbolic-ref HEAD 2>/dev/null | sed 's@^refs/heads/@@')
    fi

    # Fall back to checking for common branch names
    if [ -z "$default_branch" ]; then
        if git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
            default_branch="main"
        elif git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
            default_branch="master"
        else
            default_branch="main"
        fi
    fi

    echo "$default_branch"
}

# Extract PR number from URL or number
get_pr_number() {
    local input="$1"
    if [[ "$input" =~ ^https://github.com/.*/pull/([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$input" =~ ^[0-9]+$ ]]; then
        echo "$input"
    else
        echo "Error: Invalid PR number or URL: $input" >&2
        exit 1
    fi
}

command="$1"
shift

case "$command" in
    clone)
        REPO_URL="${1:?Repository URL required. Usage: tree-me clone <repo-url> [name]}"
        CUSTOM_NAME="$2"

        # Extract repo name from URL
        REPO_NAME=$(basename "$REPO_URL" .git)

        # Allow override of target directory
        if [ -n "$CUSTOM_NAME" ]; then
            REPO_NAME="$CUSTOM_NAME"
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

        # Clone as bare repository
        cd "$TARGET_DIR"
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
        echo "TREE_ME_CD:$TARGET_DIR/$DEFAULT_BRANCH"
        ;;

    shellenv)
        cat << 'EOF'
tree-me() {
    local output
    output=$(command tree-me "$@")
    local exit_code=$?
    echo "$output"
    if [ $exit_code -eq 0 ]; then
        local cd_path=$(echo "$output" | grep "^TREE_ME_CD:" | cut -d: -f2-)
        [ -n "$cd_path" ] && cd "$cd_path"
    fi
    return $exit_code
}

# Bash completion
if [ -n "$BASH_VERSION" ]; then
    _tree_me_complete() {
        local cur prev commands
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        commands="clone switch sw create pr list ls remove rm prune help shellenv"

        # Complete commands if first argument
        if [ $COMP_CWORD -eq 1 ]; then
            COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
            return 0
        fi

        # Complete branch names for switch/remove/rm
        case "$prev" in
            co|checkout|switch|sw|remove|rm)
                local branches
                branches=$(git worktree list 2>/dev/null | sed -n 's/.*\[\([^]]*\)\].*/\1/p' | tail -n +2)
                COMPREPLY=( $(compgen -W "$branches" -- "$cur") )
                return 0
                ;;
        esac
    }
    complete -F _tree_me_complete tree-me
fi

# Zsh completion
if [ -n "$ZSH_VERSION" ]; then
    _tree_me_complete_zsh() {
        local -a commands branches
        commands=(
            'clone:Clone repository in worktree-ready structure'
            'switch:Switch to an existing branch in new worktree'
            'sw:Switch to an existing branch in new worktree'
            'create:Create new branch in worktree'
            'pr:Checkout GitHub PR in worktree'
            'list:List all worktrees'
            'ls:List all worktrees'
            'remove:Remove a worktree'
            'rm:Remove a worktree'
            'prune:Remove worktree administrative files'
            'help:Show help'
            'shellenv:Output shell function for auto-cd'
        )

        if (( CURRENT == 2 )); then
            _describe 'command' commands
        elif (( CURRENT == 3 )); then
            case "$words[2]" in
                checkout|co|switch|sw|remove|rm)
                    branches=(${(f)"$(git worktree list 2>/dev/null | sed -n 's/.*\[\([^]]*\)\].*/\1/p' | tail -n +1)"})
                    _describe 'branch' branches
                    ;;
            esac
        fi
    }
    compdef _tree_me_complete_zsh tree-me
fi
EOF
        ;;

    checkout|co|switch|sw)
        repo=$(get_repo_name)
        branch="${1:?Branch name required. Usage: tree-me switch <branch>}"
        worktree_base=$(get_worktree_root_for_repo "$repo")
        path="$worktree_base/$branch"

        # Check if worktree already exists
        if git worktree list | grep -q "\[$branch\]"; then
            existing=$(git worktree list | grep "\[$branch\]" | awk '{print $1}')
            echo "✓ Worktree already exists: $existing"
            echo "TREE_ME_CD:$existing"
            exit 0
        fi

        # Check if branch exists
        if git show-ref --verify --quiet "refs/heads/$branch" || \
           git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
            git worktree add "$path" "$branch"
            echo "✓ Worktree created at: $path"

            # Set up tracking if remote branch exists
            if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
                (cd "$path" && git branch --set-upstream-to="origin/$branch" "$branch" 2>/dev/null || true)
            fi

            # Ensure push is enabled for worktree (in case parent has it disabled)
            (cd "$path" && git config remote.origin.pushurl "$(git remote get-url origin)" 2>/dev/null || true)

            # Track with Graphite if available (use --force to auto-detect parent)
            (cd "$path" && graphite_track "$branch" "")

            echo "TREE_ME_CD:$path"
        else
            echo "Error: Branch '$branch' does not exist" >&2
            echo "Use 'tree-me create $branch' to create a new branch" >&2
            exit 1
        fi
        ;;

    create)
        repo=$(get_repo_name)
        branch="${1:?Branch name required. Usage: tree-me create <branch> [base-branch]}"
        base="${2:-$(get_default_base)}"
        worktree_base=$(get_worktree_root_for_repo "$repo")
        path="$worktree_base/$branch"

        # Check if worktree already exists
        if git worktree list | grep -q "\[$branch\]"; then
            existing=$(git worktree list | grep "\[$branch\]" | awk '{print $1}')
            echo "✓ Worktree already exists: $existing"
            echo "TREE_ME_CD:$existing"
            exit 0
        fi

        # Create new branch
        git worktree add "$path" -b "$branch" "$base"
        echo "✓ Worktree created at: $path"

        # Set up tracking if base branch has a remote
        if git show-ref --verify --quiet "refs/remotes/origin/$base"; then
            # The new branch tracks the remote base branch initially
            (cd "$path" && git branch --set-upstream-to="origin/$base" "$branch" 2>/dev/null || true)
        fi

        # Ensure push is enabled for worktree
        (cd "$path" && git config remote.origin.pushurl "$(git remote get-url origin)" 2>/dev/null || true)

        # Track with Graphite if available
        (cd "$path" && graphite_track "$branch" "$base")

        echo "TREE_ME_CD:$path"
        ;;

    pr)
        repo=$(get_repo_name)
        input="${1:?PR number or URL required. Usage: tree-me pr <number|url>}"
        pr_number=$(get_pr_number "$input")

        # Check if gh is installed
        if ! command -v gh >/dev/null 2>&1; then
            echo "Error: 'gh' CLI not found. Install it from https://cli.github.com" >&2
            exit 1
        fi

        # Use gh to checkout PR in a worktree
        branch="pr-$pr_number"
        worktree_base=$(get_worktree_root_for_repo "$repo")
        path="$worktree_base/$branch"

        # Check if worktree already exists
        if git worktree list | grep -q "\[$branch\]"; then
            existing=$(git worktree list | grep "\[$branch\]" | awk '{print $1}')
            echo "✓ Worktree already exists: $existing"
            echo "TREE_ME_CD:$existing"
            exit 0
        fi

        # Fetch the PR and create worktree
        git fetch origin "pull/$pr_number/head:$branch" 2>/dev/null || true
        git worktree add "$path" "$branch"
        echo "✓ PR #$pr_number checked out at: $path"

        # Note: PR branches don't typically have tracking set up since they're fetched from pull refs
        # Users can manually set tracking if needed with: git branch --set-upstream-to=origin/branch-name

        # Ensure push is enabled for worktree
        (cd "$path" && git config remote.origin.pushurl "$(git remote get-url origin)" 2>/dev/null || true)

        # Track with Graphite if available (use --force to auto-detect parent)
        (cd "$path" && graphite_track "$branch" "")

        echo "TREE_ME_CD:$path"
        ;;

    list|ls)
        git worktree list
        ;;

    remove|rm)
        branch="${1:?Branch name required. Usage: tree-me remove <branch>}"
        existing=$(git worktree list | grep "\[$branch\]" | awk '{print $1}')
        if [ -z "$existing" ]; then
            echo "Error: No worktree found for branch: $branch" >&2
            exit 1
        fi
        git worktree remove "$existing"
        echo "✓ Removed worktree: $existing"
        ;;

    prune)
        git worktree prune
        echo "✓ Pruned stale worktree administrative files"
        ;;

    help|--help|-h)
        show_help
        ;;

    *)
        echo "Error: Unknown command '$command'" >&2
        echo "Run 'tree-me help' for usage information" >&2
        exit 1
        ;;
esac
