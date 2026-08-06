#!/usr/bin/env bash
# UserPromptSubmit: record a truncated first line of each user message.
#
# Prompts are the best available index of what a session was actually doing —
# far better than any reconstruction from tool calls. Only the first line and at
# most 120 characters are stored: enough to orient a human scanning the journal,
# without copying whole conversations into ~/html-pages.
set -uo pipefail

SJ_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/session-journal-common.sh
. "$SJ_HOOK_DIR/lib/session-journal-common.sh"

sj_enabled || exit 0

payload=$(cat 2>/dev/null || printf '{}')

SJ_SESSION_ID=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SJ_SESSION_ID" ] && SJ_SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
export SJ_SESSION_ID

prompt=$(printf '%s' "$payload" | jq -r '.prompt // .user_prompt // .message // empty' 2>/dev/null)
[ -n "$prompt" ] || exit 0

# First non-empty line, collapsed and capped.
line=$(printf '%s' "$prompt" |
  grep -v '^[[:space:]]*$' |
  head -1 |
  tr '\t' ' ' |
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//' |
  cut -c1-120)
[ -n "$line" ] || exit 0

sj_init || exit 0
sj_append "prompt" "hook" "▸ $line" "" || true
sj_meta_touch || true

exit 0
