#!/usr/bin/env bash
# Stop: flush the coalesced file-edit buffer, then nudge if the turn produced
# work but no reasoning.
#
# The nudge is load-bearing: it is one of three mechanisms (context injection,
# skill, nudge) that keep the journal useful without the human instructing each
# session. Tune its threshold if it proves noisy; do not delete it.
set -uo pipefail

SJ_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/session-journal-common.sh
. "$SJ_HOOK_DIR/lib/session-journal-common.sh"

sj_enabled || exit 0

payload=$(cat 2>/dev/null || printf '{}')
SJ_SESSION_ID=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SJ_SESSION_ID" ] && SJ_SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
export SJ_SESSION_ID

buf="$SJ_RUNTIME_DIR/$(sj_wsid8)"
touched=0

if [ -s "$buf/files.txt" ]; then
  files=$(sort -u "$buf/files.txt" 2>/dev/null)
  n=$(printf '%s\n' "$files" | grep -c . || true)
  if [ "${n:-0}" -gt 0 ]; then
    sj_init || exit 0
    root=$(sj_repo_root)
    # Relative paths are far easier to scan than absolute ones.
    short=$(printf '%s\n' "$files" | sed "s|^${root}/||" | head -25)
    if [ "$n" -gt 25 ]; then
      short=$(printf '%s\n… and %d more' "$short" "$((n - 25))")
    fi
    sj_append "files" "hook" "Touched $n file(s)" "$short" || true
    touched=1
  fi
  rm -f "$buf/files.txt"
fi

# Nudge only when there was substantive work AND no model-authored reasoning
# anywhere in the recent window, and at most once every 10 minutes.
if [ "$touched" -eq 1 ]; then
  f="$(sj_dir)/entries.txt"
  recent_agent=$(tail -40 "$f" 2>/dev/null |
    jq -rs '[ .[] | select(.source == "agent") ] | length' 2>/dev/null || printf '0')
  [ -z "$recent_agent" ] && recent_agent=0

  last_nudge=$(cat "$buf/last-nudge" 2>/dev/null || printf '0')
  case "$last_nudge" in
    '' | *[!0-9]*) last_nudge=0 ;;
  esac
  now=$(date +%s)

  if [ "$recent_agent" -eq 0 ] && [ $((now - last_nudge)) -gt 600 ]; then
    mkdir -p "$buf" 2>/dev/null
    printf '%s\n' "$now" >"$buf/last-nudge" 2>/dev/null || true
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "Stop",
        additionalContext: (
          "SESSION JOURNAL: you changed files this turn but logged no reasoning. " +
          "Add one entry explaining WHY, so the human can review it later:\n" +
          "  session-journal add --kind decision --title \"<claim>\" --body \"<why, alternatives>\""
        )
      }
    }'
    exit 0
  fi
fi

exit 0
