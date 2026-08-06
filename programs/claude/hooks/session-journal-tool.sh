#!/usr/bin/env bash
# PostToolUse: buffer file edits for coalescing at Stop; log git commits now.
#
# Edits are buffered rather than logged individually because a single refactor
# can touch hundreds of files, and a wall of "edited foo.ts" would bury the
# reasoning that is the whole point of the journal.
set -uo pipefail

SJ_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/session-journal-common.sh
. "$SJ_HOOK_DIR/lib/session-journal-common.sh"

sj_enabled || exit 0

payload=$(cat 2>/dev/null || printf '{}')
tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)
[ -n "$tool" ] || exit 0

SJ_SESSION_ID=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SJ_SESSION_ID" ] && SJ_SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
export SJ_SESSION_ID

case "$tool" in
  Edit | Write | MultiEdit | NotebookEdit)
    fp=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
    [ -n "$fp" ] || exit 0
    buf="$SJ_RUNTIME_DIR/$(sj_wsid8)"
    mkdir -p "$buf" 2>/dev/null || exit 0
    printf '%s\n' "$fp" >>"$buf/files.txt" 2>/dev/null || true
    ;;

  Bash)
    cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
    case "$cmd" in
      *"git commit"*)
        # Skip commits that failed — a non-zero result means nothing landed.
        sj_init || exit 0
        # Pull the subject out of -m "..." or -m '...'; fall back to a bare label.
        msg=$(printf '%s' "$cmd" | sed -n 's/.*-m[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        [ -z "$msg" ] && msg=$(printf '%s' "$cmd" | sed -n "s/.*-m[[:space:]]*'\([^']*\)'.*/\1/p" | head -1)
        [ -z "$msg" ] && msg="(commit)"
        # Only the subject line; commit bodies are long and already in git.
        msg=$(printf '%s' "$msg" | head -1 | cut -c1-160)
        sj_append "commit" "hook" "Commit: $msg" "" || true
        ;;
    esac
    ;;
esac

exit 0
