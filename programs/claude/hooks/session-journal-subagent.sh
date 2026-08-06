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

atype=$(printf '%s' "$payload" |
  jq -r '.agent_type // .subagent_type // .agentType // .agent // empty' 2>/dev/null)
[ -z "$atype" ] && atype="subagent"

# `.result` is the field observed live; the rest are defensive in case the
# harness renames it. Cheap — it is one jq call, not extra process spawns.
summary=$(printf '%s' "$payload" |
  jq -r '.result // .final_message // .output // .response // .last_message // empty' 2>/dev/null)

# Pull the last assistant text block out of a transcript.
sj_last_assistant_text() {
  # tail -c before tail -n: -n bounds LINES, not bytes, so a transcript with a
  # few enormous lines (80 x 10MB observed) stalls the hook for ~10s.
  tail -c 2000000 "$1" 2>/dev/null | tail -80 | jq -rs '
    [ .[]
      | select(.type == "assistant")
      | .message.content[]?
      | select(.type == "text")
      | .text
    ] | last // empty' 2>/dev/null
}

# Fall back to the subagent's OWN transcript.
#
# Verified live: the payload's `transcript_path` points at the PARENT session's
# transcript, so reading it captures the parent's narration rather than the
# subagent's report. The subagent's real transcript lives beside it under
# `subagents/agent-<id>.jsonl`, with an `agent-<id>.meta.json` sidecar carrying
# agentType. Resolve that directory and take the most recently modified entry —
# this hook fires as the subagent finishes, so the newest file is ours.
if [ -z "$summary" ]; then
  tp=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
  sub_id=$(printf '%s' "$payload" | jq -r '.agent_id // .agentId // .subagent_id // empty' 2>/dev/null)

  if [ -n "$tp" ]; then
    sub_dir="$(dirname "$tp")/subagents"
    cand=""
    # Prefer an exact id match when the payload gives us one.
    if [ -n "$sub_id" ] && [ -f "$sub_dir/agent-$sub_id.jsonl" ]; then
      cand="$sub_dir/agent-$sub_id.jsonl"
    elif [ -d "$sub_dir" ]; then
      cand=$(ls -t "$sub_dir"/agent-*.jsonl 2>/dev/null | head -1)
    fi
    [ -n "$cand" ] && [ -f "$cand" ] && summary=$(sj_last_assistant_text "$cand")

    # If the agent type was not in the payload, the sidecar has it.
    if [ "$atype" = "subagent" ] && [ -n "$cand" ]; then
      meta="${cand%.jsonl}.meta.json"
      if [ -f "$meta" ]; then
        t=$(jq -r '.agentType // .agent_type // empty' "$meta" 2>/dev/null)
        [ -n "$t" ] && atype="$t"
      fi
    fi

    # Last resort: the parent transcript. Better than nothing, but it will read
    # as the parent's voice, so only use it if the subagent's own is missing.
    if [ -z "$summary" ] && [ -f "$tp" ]; then
      summary=$(sj_last_assistant_text "$tp")
    fi
  fi
fi

[ -z "$summary" ] && summary="(no report captured)"

sj_init || exit 0

title=$(printf '%s' "$summary" | tr '\n' ' ' | sed 's/^[[:space:]]*//' | cut -c1-120)
[ -z "$title" ] && title="finished"

SJ_AGENT="$atype" sj_append "subagent" "subagent" "[$atype] $title" "$summary" || true
sj_meta_touch || true

exit 0
