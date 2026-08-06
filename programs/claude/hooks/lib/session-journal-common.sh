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
# How many recent entries an append checks for an identical predecessor. Bounded
# so dedupe cost stays flat as a journal grows to thousands of entries.
SJ_DEDUPE_WINDOW="${SJ_DEDUPE_WINDOW:-40}"

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
#   4. default ENABLED, seeded on first read
#
# Enabled by default: the whole point is monitoring many parallel sessions the
# user never individually configures, and an opt-in default meant a fresh
# machine journaled nothing until someone remembered to turn it on.
#
# The escape hatch for sensitive work is per-repo: drop a `.no-session-journal`
# file in a client repo's root and nothing there is ever recorded, regardless of
# the global setting.
sj_enabled() {
  # Everything downstream builds JSON with jq. Without it there is nothing this
  # can usefully do, and pressing on would leave hooks exiting non-zero (127),
  # which surfaces as an error inside the user's Claude session.
  command -v jq >/dev/null 2>&1 || return 1

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
    printf 'ENABLED\n' >"$SJ_STATE_FILE" 2>/dev/null
    return 0
  fi

  # Only an explicit DISABLED turns it off. Anything else (including a corrupted
  # or partially-written file) reads as on, matching the enabled-by-default
  # stance — a garbled state file should not silently stop journaling.
  [ "$(tr -d '[:space:]' <"$SJ_STATE_FILE" 2>/dev/null)" != "DISABLED" ]
}

# --- Mutex -------------------------------------------------------------------

# macOS has no flock(1), so mkdir(2) — which is atomic on APFS — is the portable
# primitive. The critical section is a single printf to an append-mode fd, so
# contention is microseconds even with many concurrent panes and subagents.
# Bounded by WALL CLOCK, not iteration count. `sleep 0.001` cannot actually
# deliver 1ms — process spawn dominates, so a 3000-iteration cap took ~18-26s in
# practice. That is a catastrophic stall inside a Stop/PostToolUse hook, which
# runs on every single turn.
SJ_LOCK_WAIT="${SJ_LOCK_WAIT:-2}"    # seconds to wait for a live holder
SJ_LOCK_STALE="${SJ_LOCK_STALE:-30}" # a lock older than this is presumed abandoned

sj_lock() {
  local dir="$1/.lock"
  local deadline=$(($(date +%s) + SJ_LOCK_WAIT))

  until mkdir "$dir" 2>/dev/null; do
    # An unwritable parent can never yield the lock. Retrying for the full
    # deadline turns a permission error into a multi-second hook stall, so
    # bail immediately — this is not contention.
    [ -w "$1" ] || return 1

    # Steal ONLY a provably stale lock. An earlier version stole purely on a
    # timeout, which removed a live holder's lock while it was still inside its
    # critical section — three writers were observed holding it at once, and
    # meta.json (a read-modify-write) silently lost updates as a result.
    local age
    age=$(sj_file_age "$dir")
    if [ -n "$age" ] && [ "$age" -gt "$SJ_LOCK_STALE" ]; then
      rmdir "$dir" 2>/dev/null || true
      mkdir "$dir" 2>/dev/null && return 0
    fi

    # Give up rather than stall a hook. Callers treat this as "skip this write":
    # a dropped journal entry is strictly better than a wedged Claude session.
    [ "$(date +%s)" -ge "$deadline" ] && return 1
    sleep 0.01
  done
  return 0
}

# Age in whole seconds of a path, or empty if it cannot be stat'd.
sj_file_age() {
  local mtime now
  mtime=$(stat -f %m "$1" 2>/dev/null) || return 0
  [ -n "$mtime" ] || return 0
  now=$(date +%s)
  printf '%s' "$((now - mtime))"
}

sj_unlock() { rmdir "$1/.lock" 2>/dev/null || true; }

# --- Titles ------------------------------------------------------------------

# stdin: prose (usually markdown). Args: max length.
#
# Produce a human-skimmable one-liner. A blind `cut -c1-120` of a markdown
# report gives titles like "## Token cost **Per session** | Cost | Tokens |",
# which is unreadable in a list, so: skip markdown structure (headings, table
# rows, list bullets, code fences) to reach the first line of actual prose,
# strip inline markup, and cut at a sentence boundary when one is in range.
sj_summarize_line() {
  local max="${1:-120}"
  awk -v max="$max" '
    # Track fenced code blocks so their contents are never used as a title.
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line == "") next
      if (line ~ /^#+[[:space:]]*/) { sub(/^#+[[:space:]]*/, "", line) }  # heading text is fine
      else if (line ~ /^[|>]/) next                                       # table row / quote
      else if (line ~ /^([-*+]|[0-9]+\.)[[:space:]]/) sub(/^([-*+]|[0-9]+\.)[[:space:]]+/, "", line)
      else if (line ~ /^[-=]{3,}$/) next                                  # setext rule
      if (line == "") next
      print line
      exit
    }
  ' | sed -e 's/\*\*//g' -e 's/`//g' -e 's/__//g' |
    awk -v max="$max" '{
      # Cut at the first sentence end that fits, else hard-truncate on a word
      # boundary so the title never ends mid-word.
      if (match($0, /[.!?](  *|$)/) && RSTART <= max) { print substr($0, 1, RSTART); exit }
      if (length($0) <= max) { print; exit }
      s = substr($0, 1, max)
      if (match(s, /[[:space:]][^[:space:]]*$/)) s = substr(s, 1, RSTART - 1)
      print s "…"
    }' | sed -e 's/[[:space:]]*$//'
}

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

  # Content hash for dedupe: kind + title + body, deliberately EXCLUDING the
  # timestamp, session id and pane id so the same payload is recognised across
  # sessions and panes. Computed BEFORE the jq call that serializes it.
  local sig
  sig=$(printf '%s\037%s\037%s' "$kind" "$title" "$body" | shasum -a 256 2>/dev/null | cut -c1-16)

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
    --arg sig "$sig" \
    '{ts:$ts, kind:$kind, source:$source, title:$title, body:$body,
      session_id:$session_id, pane_id:$pane_id, workspace_id:$workspace_id,
      agent:$agent, sig:$sig}') || return 1

  # Suppress an exact repeat of a recent entry.
  #
  # Compaction re-fires SessionStart/SubagentStop, which replayed the identical
  # report minutes apart (observed: the same 2KB body written twice, either side
  # of a `Session compact` entry). Retries and hooks racing on one turn do the
  # same.
  #
  # Runs OUTSIDE the lock, with grep rather than jq. Both matter:
  #   - An in-lock check lengthened the critical section by ~500ms (a jq spawn,
  #     flat in journal size), so with 8 concurrent writers the last one blew
  #     sj_lock's 2s deadline and its entry was DROPPED. Measured: 7 of 160
  #     appends lost.
  #   - grep -F on the sig field costs no process spawn beyond grep itself, and
  #     the sig is a 16-hex-char hash, so a fixed-string match on the last
  #     SJ_DEDUPE_WINDOW lines cannot false-positive on body text.
  # Racing here is harmless: the worst case is a duplicate slipping through, and
  # a duplicate is a cosmetic flaw where a lost entry is data loss.
  #
  # Bounded to a window rather than the whole file so cost stays flat as journals
  # grow to thousands of entries; a repeat further back is real recurrence.
  if [ -n "$sig" ] && [ -s "$dir/entries.txt" ] &&
    tail -n "$SJ_DEDUPE_WINDOW" "$dir/entries.txt" 2>/dev/null |
    grep -qF "\"sig\":\"$sig\""; then
    return 0
  fi

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
  # Journals hold user prompts, agent reasoning, filenames and commit subjects —
  # potentially client-confidential. Owner-only, not the 0755/0644 that umask 022
  # would otherwise give. (The gallery server runs as the same user, so it can
  # still read them.)
  chmod 700 "$dir" 2>/dev/null || true

  tpl="${SJ_TEMPLATE:-$SJ_LIB_SELF_DIR/journal-template.html}"

  if [ ! -f "$dir/index.html" ]; then
    if [ ! -f "$tpl" ]; then
      echo "session-journal: template missing: $tpl" >&2
      return 1
    fi
    # mktemp, not "$dir/index.html.tmp.$$": PIDs collide across concurrent
    # subshells (observed as an intermittent `mv: No such file or directory`
    # under 8 parallel writers), and a predictable name in a user-writable
    # directory is a symlink-follow target for anything already running as the
    # user. mktemp gives an unpredictable name and O_EXCL creation.
    local tmp
    tmp=$(mktemp "$dir/.index.html.XXXXXXXX") || return 1
    SJ_T_TITLE="$(sj_esc_html "$(sj_repo_name) · $(sj_branch_name)")" \
    SJ_T_REPO="$(sj_esc_html "$(sj_repo_name)")" \
    SJ_T_BRANCH="$(sj_esc_html "$(sj_branch_name)")" \
    SJ_T_WSID="$(sj_esc_html "${CMUX_WORKSPACE_ID:-$(sj_wsid8)}")" \
    SJ_T_CWD="$(sj_esc_html "$(sj_repo_root)")" \
    SJ_T_CREATED="$(date +%F)" \
      sj_render_template "$tpl" >"$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$dir/index.html" || {
      rm -f "$tmp"
      return 1
    }
  fi

  if [ ! -f "$dir/entries.txt" ]; then
    : >"$dir/entries.txt"
    chmod 600 "$dir/entries.txt" 2>/dev/null || true
  fi
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
  local dir="$1" tmp
  # See sj_init: mktemp rather than a $$-suffixed name — PIDs collide across
  # concurrent subshells, and a predictable path is a symlink-follow target.
  tmp=$(mktemp "$dir/.meta.json.XXXXXXXX") || return 1
  cat >"$tmp" || { rm -f "$tmp"; return 1; }
  if jq -e . "$tmp" >/dev/null 2>&1; then
    chmod 600 "$tmp" 2>/dev/null || true
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

  # Retry the whole read-modify-write a few times. sj_lock gives up rather than
  # stall a hook, and this update is idempotent, so re-checking and retrying is
  # both safe and the difference between recording a session id and silently
  # dropping it under contention from many panes and subagents.
  local attempt=0
  while [ "$attempt" -lt 5 ]; do
    attempt=$((attempt + 1))

    # Cheap pre-check outside the lock. Racy by design: the worst case is a
    # redundant write, which the in-lock jq then makes idempotent anyway.
    local changed
    changed=$(jq -r --arg s "$sid" --arg p "$pid" --arg d "$today" '
      (.date != $d)
      or ($s != "" and (((.session_ids // []) | index($s)) == null))
      or ($p != "" and (((.pane_ids    // []) | index($p)) == null))
    ' "$dir/meta.json" 2>/dev/null)
    [ "$changed" = "true" ] || return 0

    if sj_lock "$dir"; then
      break
    fi
    [ "$attempt" -ge 5 ] && return 1
    sleep 0.05
  done
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
