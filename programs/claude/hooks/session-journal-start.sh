#!/usr/bin/env bash
# SessionStart: open or attach this workspace's journal, and tell the model it
# exists.
#
# The additionalContext we return is prepended into the model's context by the
# harness. That is the only mechanism that reliably reaches a session the user
# never instructs — they run too many in parallel to brief each one.
set -uo pipefail

SJ_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/session-journal-common.sh
. "$SJ_HOOK_DIR/lib/session-journal-common.sh"

sj_enabled || exit 0

payload=$(cat 2>/dev/null || printf '{}')

# Prefer the documented stdin field; fall back to the env var.
SJ_SESSION_ID=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SJ_SESSION_ID" ] && SJ_SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
export SJ_SESSION_ID

src=$(printf '%s' "$payload" | jq -r '.source // "startup"' 2>/dev/null)
[ -z "$src" ] && src="startup"

sj_init || exit 0
SJ_SOURCE=hook sj_append "session" "hook" \
  "Session $src — $(sj_repo_name) · $(sj_branch_name)" \
  "session_id: ${SJ_SESSION_ID:-unknown}" || true
sj_meta_touch || true

jq -n --arg d "$(sj_dir)" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: (
      "SESSION JOURNAL ACTIVE — this workspace keeps a shared journal at \($d).\n" +
      "\n" +
      "The human runs many parallel sessions and reads these journals instead of\n" +
      "transcripts. Hooks already record files touched, commits, and subagent\n" +
      "reports automatically. They CANNOT record why you did things — that is your job.\n" +
      "\n" +
      "  session-journal add --kind <decision|progress|blocker|milestone|question> \\\n" +
      "      --title \"<one-line claim>\" --body \"<why, alternatives, tradeoffs>\"\n" +
      "\n" +
      "Log a `decision` whenever you choose between real alternatives, a `blocker`\n" +
      "when stuck, and a `milestone` when something meaningful starts working.\n" +
      "Do NOT log routine file edits or narrate each step. Aim for a handful of\n" +
      "substantial entries per session. Write for someone who will read this\n" +
      "tomorrow and ask you to justify a choice."
    )
  }
}'
