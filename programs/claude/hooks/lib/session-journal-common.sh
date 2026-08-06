#!/usr/bin/env bash
# Shared library for the session-journal hooks and CLI.
#
# Sourced, never executed. This is the ONLY file that touches a journal on disk,
# so all path, locking, and concurrency logic lives here and the hook scripts
# stay thin (parse stdin -> call the CLI).
#
# Every function is written to fail soft: a hook must never break a Claude Code
# session because journaling had a bad day.

# Resolve this library's own directory ONCE, at load time, to an absolute path.
# ${BASH_SOURCE[0]} is relative when sourced via a relative path (and empty
# under zsh), so computing it lazily inside a function is unreliable.
SJ_LIB_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"

SJ_STATE_FILE="${SJ_STATE_FILE:-$HOME/.claude/session-journal-state}"
SJ_PAGES_DIR="${SJ_PAGES_DIR:-$HOME/html-pages}"
SJ_RUNTIME_DIR="${SJ_RUNTIME_DIR:-$HOME/.claude/session-journal}"
SJ_MAX_BODY="${SJ_MAX_BODY:-4096}"

# --- Identity ----------------------------------------------------------------

# Repo root of the workspace. Prefers cmux's launch directory over $PWD, which
# wanders as the agent cd's around during a session.
sj_repo_root() {
  local dir="${CMUX_AGENT_LAUNCH_CWD:-$PWD}" root
  [ -d "$dir" ] || dir="$PWD"
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$root" ] || root="$dir"
  # Strip any trailing newline: these values are interpolated into slugs, sed
  # patterns and HTML, where an embedded newline corrupts the output silently.
  printf '%s' "${root%$'\n'}"
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
  local id="${CMUX_WORKSPACE_ID:-}" out
  if [ -z "$id" ]; then
    # Outside cmux: derive a stable hash from the launch dir instead.
    id=$(printf '%s' "$(sj_repo_root)" | shasum -a 256 | cut -c1-8)
  fi
  out=$(printf '%s' "$id" | tr 'A-Z' 'a-z' | tr -cd 'a-f0-9' | cut -c1-8)
  # A non-hex id (not a UUID) can filter down to nothing, which would leave a
  # slug ending in a bare '-' and, worse, make unrelated workspaces collide on
  # the empty string. Hash the raw id instead so it stays unique.
  if [ ${#out} -lt 8 ]; then
    out=$(printf '%s' "$id" | shasum -a 256 | cut -c1-8)
  fi
  printf '%s' "$out"
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
# Bounded by WALL CLOCK, not iteration count. `sleep 0.001` cannot actually
# deliver 1ms — process spawn dominates, so a 3000-iteration cap took ~18-26s in
# practice. That is a catastrophic stall inside a Stop/PostToolUse hook, which
# runs on every single turn.
sj_lock() {
  local dir="$1/.lock"
  local deadline=$(($(date +%s) + 2))
  until mkdir "$dir" 2>/dev/null; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      # Assume the holder crashed without unlocking and steal the lock. Losing
      # one entry beats wedging a hook.
      rmdir "$dir" 2>/dev/null || true
      mkdir "$dir" 2>/dev/null && return 0
      return 1
    fi
    sleep 0.01
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

# --- Page rendering ----------------------------------------------------------

# Escape a value for interpolation into HTML text/attributes.
sj_esc_html() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

# Substitute {{PLACEHOLDER}}s in the template.
#
# awk with index()/substr() rather than sed: sed's replacement text treats & as
# "the whole match", so escaping a branch name to `a&amp;b` and feeding it to
# sed yields `a{{BRANCH}}amp;b`. awk does literal string replacement, so escaped
# HTML survives intact.
sj_render_template() {
  local tpl="$1"
  awk 'BEGIN{
      M["{{TITLE}}"]        = ENVIRON["SJ_T_TITLE"];
      M["{{REPO}}"]         = ENVIRON["SJ_T_REPO"];
      M["{{BRANCH}}"]       = ENVIRON["SJ_T_BRANCH"];
      M["{{WORKSPACE_ID}}"] = ENVIRON["SJ_T_WSID"];
      M["{{CWD}}"]          = ENVIRON["SJ_T_CWD"];
      M["{{CREATED}}"]      = ENVIRON["SJ_T_CREATED"];
    }
    {
      for (k in M) {
        while ((i = index($0, k)) > 0)
          $0 = substr($0, 1, i - 1) M[k] substr($0, i + length(k));
      }
      print;
    }' "$tpl"
}

# --- init --------------------------------------------------------------------

# ORDER MATTERS: index.html is written FIRST. The gallery skips any directory
# whose index.html cannot be stat'd, so a journal created in the other order is
# invisible in the gallery with no error surfaced anywhere.
sj_init() {
  local dir tpl
  dir=$(sj_dir)
  mkdir -p "$dir" || return 1

  tpl="${SJ_TEMPLATE:-$SJ_LIB_SELF_DIR/journal-template.html}"

  if [ ! -f "$dir/index.html" ]; then
    if [ ! -f "$tpl" ]; then
      echo "session-journal: template missing: $tpl" >&2
      return 1
    fi
    local tmp="$dir/index.html.tmp.$$"
    SJ_T_TITLE="$(sj_esc_html "$(sj_repo_name) · $(sj_branch_name)")" \
    SJ_T_REPO="$(sj_esc_html "$(sj_repo_name)")" \
    SJ_T_BRANCH="$(sj_esc_html "$(sj_branch_name)")" \
    SJ_T_WSID="$(sj_esc_html "${CMUX_WORKSPACE_ID:-$(sj_wsid8)}")" \
    SJ_T_CWD="$(sj_esc_html "$(sj_repo_root)")" \
    SJ_T_CREATED="$(date +%F)" \
      sj_render_template "$tpl" >"$tmp" && mv -f "$tmp" "$dir/index.html" || {
      rm -f "$tmp"
      return 1
    }
  fi

  [ -f "$dir/entries.txt" ] || : >"$dir/entries.txt"
  sj_meta_init
}

# --- meta.json ---------------------------------------------------------------
#
# The gallery reads this sidecar for title/style/date and ignores our marker
# fields, so the markers exist for filesystem discovery rather than for the UI.
#
# ALWAYS write via tmp + mv: rename(2) is atomic within a filesystem, so a
# reader never observes a partial file. This matters more than it looks — the
# server wraps its sidecar parse in try/catch and falls back to title-only
# extraction, so a torn meta.json fails completely silently.

# stdin: complete JSON document. Caller must already hold the lock.
sj_meta_write() {
  local dir="$1"
  local tmp="$dir/meta.json.tmp.$$"
  cat >"$tmp" || { rm -f "$tmp"; return 1; }
  if jq -e . "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$dir/meta.json"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

sj_meta_init() {
  local dir
  dir=$(sj_dir)
  [ -d "$dir" ] || return 1
  [ -f "$dir/meta.json" ] && return 0

  local now repo branch common
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  repo=$(sj_repo_name)
  branch=$(sj_branch_name)
  common=$(git -C "$(sj_repo_root)" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || printf '')

  sj_lock "$dir" || return 1
  # Re-check inside the lock: another pane may have created it while we waited.
  if [ ! -f "$dir/meta.json" ]; then
    jq -n \
      --arg title "$repo · $branch" \
      --arg date "$(date +%F)" \
      --arg ws "${CMUX_WORKSPACE_ID:-}" \
      --arg cwd "$(sj_repo_root)" \
      --arg launch "${CMUX_AGENT_LAUNCH_CWD:-}" \
      --arg repo "$repo" \
      --arg branch "$branch" \
      --arg common "$common" \
      --arg started "$now" \
      --arg updated "$now" \
      '{kind:"session-journal", title:$title, style:"Session journal",
        keywords:"live session log · decisions · progress",
        recreate:"Session journal — auto-maintained by the session-journal hooks.",
        date:$date, cmux_workspace_id:$ws, session_ids:[], pane_ids:[],
        cwd:$cwd, launch_cwd:$launch, repo:$repo, branch:$branch,
        git_common_dir:$common, started:$started, updated:$updated}' |
      sj_meta_write "$dir"
  fi
  sj_unlock "$dir"
  return 0
}

# Refresh date/updated and accumulate session + pane ids.
#
# Writes ONLY when content would actually change: meta.json is a .json file and
# therefore inside the gallery server's fs.watch filter, so a needless write
# broadcasts an SSE reload to every open tab.
sj_meta_touch() {
  local dir
  dir=$(sj_dir)
  [ -f "$dir/meta.json" ] || return 0

  local sid="${SJ_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
  local pid="${CMUX_PANEL_ID:-}"
  local today
  today=$(date +%F)

  # Cheap pre-check outside the lock. Racy by design: the worst case is a
  # redundant write, which the in-lock jq then makes idempotent anyway.
  local changed
  changed=$(jq -r --arg s "$sid" --arg p "$pid" --arg d "$today" '
    (.date != $d)
    or ($s != "" and (((.session_ids // []) | index($s)) == null))
    or ($p != "" and (((.pane_ids    // []) | index($p)) == null))
  ' "$dir/meta.json" 2>/dev/null)
  [ "$changed" = "true" ] || return 0

  sj_lock "$dir" || return 1
  jq --arg s "$sid" --arg p "$pid" --arg d "$today" \
    --arg u "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      .date = $d
    | .updated = $u
    | .session_ids = (((.session_ids // []) + (if $s == "" then [] else [$s] end)) | unique)
    | .pane_ids    = (((.pane_ids    // []) + (if $p == "" then [] else [$p] end)) | unique)
  ' "$dir/meta.json" | sj_meta_write "$dir"
  sj_unlock "$dir"
  return 0
}
