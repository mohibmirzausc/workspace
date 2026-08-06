#!/usr/bin/env bash
# SubagentStop: harvest the subagent's own final report into the journal.
#
# This is how subagents contribute WITHOUT being instructed. They skip skills by
# design, and CLAUDE_CODE_CHILD_SESSION cannot discriminate them here because
# cmux sets it on every session. The hook firing at all IS the discriminator.
#
# The subagent's final report is already a summary, so harvesting it is both
# free and higher quality than anything we could reconstruct from a transcript.
set -uo pipefail

SJ_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/session-journal-common.sh
. "$SJ_HOOK_DIR/lib/session-journal-common.sh"

sj_enabled || exit 0

payload=$(cat 2>/dev/null || printf '{}')

SJ_SESSION_ID=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SJ_SESSION_ID" ] && SJ_SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
export SJ_SESSION_ID

# Optional debug capture: set SJ_CAPTURE_PAYLOAD to a path to record the real
# payload shape. Used during live verification, since the SubagentStop schema
# is not something we could confirm offline.
if [ -n "${SJ_CAPTURE_PAYLOAD:-}" ]; then
  printf '%s' "$payload" >"$SJ_CAPTURE_PAYLOAD" 2>/dev/null || true
fi

atype=$(printf '%s' "$payload" |
  jq -r '.agent_type // .subagent_type // .agentType // .agent // empty' 2>/dev/null)
[ -z "$atype" ] && atype="subagent"

# The field carrying the report varies; try the plausible names in order.
summary=$(printf '%s' "$payload" |
  jq -r '.result // .final_message // .output // .response // .last_message // empty' 2>/dev/null)

# Fall back to the transcript's last assistant text block.
if [ -z "$summary" ]; then
  tp=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$tp" ] && [ -f "$tp" ]; then
    summary=$(tail -80 "$tp" 2>/dev/null | jq -rs '
      [ .[]
        | select(.type == "assistant")
        | .message.content[]?
        | select(.type == "text")
        | .text
      ] | last // empty' 2>/dev/null)
  fi
fi

[ -z "$summary" ] && summary="(no report captured)"

sj_init || exit 0

title=$(printf '%s' "$summary" | tr '\n' ' ' | sed 's/^[[:space:]]*//' | cut -c1-120)
[ -z "$title" ] && title="finished"

SJ_AGENT="$atype" sj_append "subagent" "subagent" "[$atype] $title" "$summary" || true
sj_meta_touch || true

exit 0
