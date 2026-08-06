#!/usr/bin/env bash
# Shared library for the session-journal hooks and CLI.
#
# Sourced, never executed. This is the ONLY file that touches a journal on disk,
# so all path, locking, and concurrency logic lives here and the hook scripts
# stay thin (parse stdin -> call the CLI).
#
# Every function is written to fail soft: a hook must never break a Claude Code
# session because journaling had a bad day.

SJ_STATE_FILE="${SJ_STATE_FILE:-$HOME/.claude/session-journal-state}"
SJ_PAGES_DIR="${SJ_PAGES_DIR:-$HOME/html-pages}"
SJ_RUNTIME_DIR="${SJ_RUNTIME_DIR:-$HOME/.claude/session-journal}"
SJ_MAX_BODY="${SJ_MAX_BODY:-4096}"

# --- Identity ----------------------------------------------------------------

# Repo root of the workspace. Prefers cmux's launch directory over $PWD, which
# wanders as the agent cd's around during a session.
sj_repo_root() {
  local dir="${CMUX_AGENT_LAUNCH_CWD:-$PWD}"
  [ -d "$dir" ] || dir="$PWD"
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$dir"
}

sj_repo_name() { basename "$(sj_repo_root)"; }

# `git branch --show-current` rather than `rev-parse --abbrev-ref HEAD`: on a
# freshly-init'd repo with no commits, rev-parse prints "HEAD" AND exits
# non-zero, so a `||` fallback concatenates onto its output. show-current
# returns the unborn branch name cleanly and prints nothing on detached HEAD.
sj_branch_name() {
  local b
  b=$(git -C "$(sj_repo_root)" branch --show-current 2>/dev/null)
  if [ -z "$b" ]; then
    # Detached HEAD -> short sha; not a git repo at all -> "nogit".
    b=$(git -C "$(sj_repo_root)" rev-parse --short HEAD 2>/dev/null) || b=""
    [ -z "$b" ] && b="nogit"
  fi
  printf '%s' "$b"
}

# Short, stable workspace discriminator. Without this, two cmux workspaces on the
# same repo AND branch created on the same day would share a folder and silently
# merge into one journal.
sj_wsid8() {
  local id="${CMUX_WORKSPACE_ID:-}"
  if [ -z "$id" ]; then
    # Outside cmux: derive a stable hash from the launch dir instead.
    id=$(printf '%s' "$(sj_repo_root)" | shasum -a 256 | cut -c1-8)
  fi
  printf '%s' "$id" | tr 'A-Z' 'a-z' | tr -cd 'a-f0-9' | cut -c1-8
}

# Lowercase, filesystem-safe. Note branch names legitimately contain '/', which
# must not become a path separator in the slug.
sj_sanitize() {
  printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9._-' '-' | sed 's/--*/-/g; s/^-//; s/-$//'
}

# <YYYY-MM-DD>-session-<repo>-<branch>-<wsid8>
#
# The date is the CREATION date: once a directory exists for this workspace we
# reuse it forever (no daily rotation), so the folder is found by its wsid8
# suffix rather than rebuilt from today's date.
sj_slug() {
  local wsid8 existing
  wsid8=$(sj_wsid8)
  if [ -d "$SJ_PAGES_DIR" ]; then
    existing=$(find "$SJ_PAGES_DIR" -maxdepth 1 -type d -name "*-session-*-$wsid8" 2>/dev/null | head -1)
    if [ -n "$existing" ]; then
      basename "$existing"
      return 0
    fi
  fi
  printf '%s-session-%s-%s-%s' \
    "$(date +%F)" \
    "$(sj_sanitize "$(sj_repo_name)")" \
    "$(sj_sanitize "$(sj_branch_name)")" \
    "$wsid8"
}

sj_dir() { printf '%s/%s' "$SJ_PAGES_DIR" "$(sj_slug)"; }

# --- Enable flag -------------------------------------------------------------

# Resolution order, first match wins:
#   1. SESSION_JOURNAL=0/1 env var
#   2. .session-journal / .no-session-journal in the repo root
#   3. ~/.claude/session-journal-state (ENABLED/DISABLED)
#   4. default DISABLED (opt-in), seeded on first read
#
# Anything unrecognized is treated as disabled: failing closed means a corrupted
# state file cannot silently start logging a client repo.
sj_enabled() {
  case "${SESSION_JOURNAL:-}" in
    0 | off | false | no) return 1 ;;
    1 | on | true | yes) return 0 ;;
  esac

  local root
  root=$(sj_repo_root)
  if [ -n "$root" ]; then
    [ -e "$root/.no-session-journal" ] && return 1
    [ -e "$root/.session-journal" ] && return 0
  fi

  if [ ! -f "$SJ_STATE_FILE" ]; then
    mkdir -p "$(dirname "$SJ_STATE_FILE")" 2>/dev/null
    printf 'DISABLED\n' >"$SJ_STATE_FILE" 2>/dev/null
    return 1
  fi

  [ "$(tr -d '[:space:]' <"$SJ_STATE_FILE" 2>/dev/null)" = "ENABLED" ]
}

# --- Mutex -------------------------------------------------------------------

# macOS has no flock(1), so mkdir(2) — which is atomic on APFS — is the portable
# primitive. The critical section is a single printf to an append-mode fd, so
# contention is microseconds even with many concurrent panes and subagents.
sj_lock() {
  local dir="$1/.lock"
  local n=0
  until mkdir "$dir" 2>/dev/null; do
    n=$((n + 1))
    if [ "$n" -gt 3000 ]; then
      # ~3s. Assume the holder crashed without unlocking and steal the lock;
      # losing one entry beats wedging a hook forever.
      rmdir "$dir" 2>/dev/null || true
      mkdir "$dir" 2>/dev/null && return 0
      return 1
    fi
    sleep 0.001
  done
  return 0
}

sj_unlock() { rmdir "$1/.lock" 2>/dev/null || true; }

# --- Append ------------------------------------------------------------------

# One JSON object per line. jq -c does the escaping, so newlines, quotes and
# tabs in the body can never break the one-entry-per-line invariant that the
# page's parser depends on.
#
# Args: kind source title [body]
sj_append() {
  local kind="$1" source="$2" title="$3" body="${4:-}"
  local dir
  dir=$(sj_dir)
  [ -d "$dir" ] || return 1

  # Bound entry size so one runaway body cannot dominate the page.
  if [ "${#body}" -gt "$SJ_MAX_BODY" ]; then
    body="${body:0:$SJ_MAX_BODY}…[truncated]"
  fi

  local line
  line=$(jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg kind "$kind" \
    --arg source "$source" \
    --arg title "$title" \
    --arg body "$body" \
    --arg session_id "${SJ_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}" \
    --arg pane_id "${CMUX_PANEL_ID:-}" \
    --arg workspace_id "${CMUX_WORKSPACE_ID:-}" \
    --arg agent "${SJ_AGENT:-main}" \
    '{ts:$ts, kind:$kind, source:$source, title:$title, body:$body,
      session_id:$session_id, pane_id:$pane_id, workspace_id:$workspace_id,
      agent:$agent}') || return 1

  sj_lock "$dir" || return 1
  printf '%s\n' "$line" >>"$dir/entries.txt"
  sj_unlock "$dir"
  return 0
}
