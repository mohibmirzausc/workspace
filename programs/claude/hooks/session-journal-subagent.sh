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

# Locate the subagent's OWN transcript.
#
# Verified live: the payload's `transcript_path` points at the PARENT session's
# transcript, so reading it captures the parent's narration rather than the
# subagent's report. The subagent's real transcript lives under
#
#   <dir of transcript_path>/<session-id>/subagents/agent-<id>.jsonl
#
# with an `agent-<id>.meta.json` sidecar carrying agentType and description.
# NOTE the `<session-id>/` component: an earlier version looked in
# `<dir>/subagents` (one level too shallow), which NEVER existed. Every
# SubagentStop therefore fell through to the parent transcript and logged the
# main agent's narration as if it were a subagent report — 59 such entries in a
# session that ran only 6 real subagents. `transcript_path` is
# `<dir>/<session-id>.jsonl`, so strip the extension to get the sibling dir.
tp=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
sub_id=$(printf '%s' "$payload" | jq -r '.agent_id // .agentId // .subagent_id // empty' 2>/dev/null)

cand=""
if [ -n "$tp" ]; then
  for sub_dir in "${tp%.jsonl}/subagents" "$(dirname "$tp")/subagents"; do
    [ -d "$sub_dir" ] || continue
    # Prefer an exact id match when the payload gives us one.
    if [ -n "$sub_id" ] && [ -f "$sub_dir/agent-$sub_id.jsonl" ]; then
      cand="$sub_dir/agent-$sub_id.jsonl"
    else
      # This hook fires as the subagent finishes, so the newest file is ours.
      cand=$(ls -t "$sub_dir"/agent-*.jsonl 2>/dev/null | head -1)
    fi
    [ -n "$cand" ] && break
  done
fi

# GATE: only record when a subagent transcript actually exists.
#
# Without this, a SubagentStop that fires with no resolvable subagent (or on the
# main session's own turn end) reads the PARENT transcript and writes the main
# agent's last message as a "subagent report" — duplicating narration the human
# has already read, and burying the handful of genuine reports. A missed entry
# is far cheaper than a journal that is 60% noise.
[ -n "$cand" ] && [ -f "$cand" ] || exit 0

# The sidecar carries both the agent type and the human-written task description.
desc=""
meta="${cand%.jsonl}.meta.json"
if [ -f "$meta" ]; then
  [ "$atype" = "subagent" ] &&
    { t=$(jq -r '.agentType // .agent_type // empty' "$meta" 2>/dev/null); [ -n "$t" ] && atype="$t"; }
  desc=$(jq -r '.description // empty' "$meta" 2>/dev/null)
fi

[ -z "$summary" ] && summary=$(sj_last_assistant_text "$cand")
[ -z "$summary" ] && summary="(no report captured)"

sj_init || exit 0

# Title: prefer the sidecar's task description — it is a purpose-written phrase.
# Slicing the report's first 120 chars yields things like
# "## Token cost of journaling **Per session…** | Cost | Tokens |", which is
# unskimmable in a list. Fall back to the report's first real sentence.
title="$desc"
if [ -z "$title" ]; then
  title=$(printf '%s' "$summary" | sj_summarize_line 120)
fi
[ -z "$title" ] && title="finished"

SJ_AGENT="$atype" sj_append "subagent" "subagent" "[$atype] $title" "$summary" || true
sj_meta_touch || true

exit 0
