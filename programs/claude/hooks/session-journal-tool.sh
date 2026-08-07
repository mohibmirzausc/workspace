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
        # Read the subject from git rather than parsing it out of the command
        # string. This does double duty: it sidesteps quoting entirely (the
        # command may use -m "...", -m '...', -F, a heredoc, or --amend), and it
        # means a FAILED commit logs nothing — if the commit did not land, HEAD
        # still points at the previous one, which we skip as already-journalled.
        #
        # Deliberately not reading `.tool_response`: that schema is undocumented
        # and guessing at its field names is exactly what produced the earlier
        # subagent-transcript bug. git is the source of truth here.
        head_sha=$(git -C "$(sj_repo_root)" rev-parse HEAD 2>/dev/null) || exit 0
        [ -n "$head_sha" ] || exit 0

        seen="$SJ_RUNTIME_DIR/$(sj_wsid8)/last-commit"
        [ "$(cat "$seen" 2>/dev/null)" = "$head_sha" ] && exit 0

        msg=$(git -C "$(sj_repo_root)" log -1 --pretty=%s 2>/dev/null | cut -c1-160)
        [ -n "$msg" ] || exit 0

        sj_init || exit 0
        mkdir -p "$(dirname "$seen")" 2>/dev/null
        printf '%s\n' "$head_sha" >"$seen" 2>/dev/null || true
        sj_append "commit" "hook" "Commit: $msg" "${head_sha:0:8}" || true
        ;;
    esac
    ;;
esac

exit 0
