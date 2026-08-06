#!/usr/bin/env bash
# The four hooks, driven exactly as Claude Code drives them: JSON on stdin.
set -uo pipefail
. "$(dirname "$0")/assert.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
H="$ROOT/programs/claude/hooks"

setup_sandbox
trap teardown_sandbox EXIT
echo ENABLED >"$SJ_STATE_FILE"

# --- SessionStart ------------------------------------------------------------
out=$(printf '{"session_id":"s1","cwd":"%s","source":"startup"}' "$CMUX_AGENT_LAUNCH_CWD" |
  bash "$H/session-journal-start.sh")

d=$("$H/session-journal" path)
assert_file_exists "$d/index.html" "SessionStart must create the page"
assert_file_exists "$d/meta.json"

printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null ||
  fail "SessionStart must inject context"
assert_contains "$out" "session-journal add" "context shows the command"
assert_eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" "SessionStart"
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .kind)" "session"
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .session_id)" "s1" "session id from stdin"

# --- PostToolUse: edits are buffered, not logged one-by-one -------------------
for f in a.ts b.ts c.ts; do
  printf '{"session_id":"s1","tool_name":"Edit","tool_input":{"file_path":"%s/%s"}}' \
    "$CMUX_AGENT_LAUNCH_CWD" "$f" | bash "$H/session-journal-tool.sh"
done
assert_eq "$(wc -l <"$d/entries.txt" | tr -d ' ')" "1" "edits buffered, nothing written yet"

# Duplicate edits to one file collapse.
printf '{"session_id":"s1","tool_name":"Edit","tool_input":{"file_path":"%s/a.ts"}}' \
  "$CMUX_AGENT_LAUNCH_CWD" | bash "$H/session-journal-tool.sh"

# --- Stop flushes the buffer as ONE coalesced entry ---------------------------
printf '{"session_id":"s1"}' | bash "$H/session-journal-stop.sh" >/dev/null
last=$(tail -1 "$d/entries.txt")
assert_eq "$(printf '%s' "$last" | jq -r .kind)" "files"
assert_eq "$(printf '%s' "$last" | jq -r .source)" "hook"
assert_contains "$(printf '%s' "$last" | jq -r .title)" "3" "count in title, deduped"
assert_contains "$(printf '%s' "$last" | jq -r .body)" "a.ts" "body lists the files"
assert_contains "$(printf '%s' "$last" | jq -r .body)" "c.ts"
# Paths are relative to the repo root, not absolute.
printf '%s' "$last" | jq -r .body | grep -q "^$CMUX_AGENT_LAUNCH_CWD" &&
  fail "paths should be repo-relative"

# Buffer cleared: a second Stop with no activity adds nothing.
before=$(wc -l <"$d/entries.txt")
printf '{"session_id":"s1"}' | bash "$H/session-journal-stop.sh" >/dev/null
assert_eq "$(wc -l <"$d/entries.txt")" "$before" "no empty flush"

# --- PostToolUse: git commits are captured, ordinary commands are not ---------
printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"git commit -m \\"feat: a thing\\""}}' |
  bash "$H/session-journal-tool.sh"
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .kind)" "commit"
assert_contains "$(tail -1 "$d/entries.txt" | jq -r .title)" "feat: a thing" "subject extracted"

before=$(wc -l <"$d/entries.txt")
printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls -la"}}' |
  bash "$H/session-journal-tool.sh"
assert_eq "$(wc -l <"$d/entries.txt")" "$before" "ordinary bash must not be logged"

# Single-quoted commit messages work too.
printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"git commit -m '"'"'fix: quoted'"'"'"}}' |
  bash "$H/session-journal-tool.sh"
assert_contains "$(tail -1 "$d/entries.txt" | jq -r .title)" "fix: quoted"

# --- SubagentStop ------------------------------------------------------------
printf '{"session_id":"s1","agent_type":"Explore","result":"Found 3 call sites.\\nAll in tests."}' |
  bash "$H/session-journal-subagent.sh" >/dev/null
last=$(tail -1 "$d/entries.txt")
assert_eq "$(printf '%s' "$last" | jq -r .source)" "subagent"
assert_eq "$(printf '%s' "$last" | jq -r .agent)" "Explore"
assert_contains "$(printf '%s' "$last" | jq -r .title)" "Explore" "agent type in title"
assert_contains "$(printf '%s' "$last" | jq -r .body)" "Found 3 call sites" "report captured"

# Unknown payload shape must still produce an entry rather than vanishing.
printf '{"session_id":"s1"}' | bash "$H/session-journal-subagent.sh" >/dev/null
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .source)" "subagent" "degrades gracefully"

# Transcript fallback when no summary field is present.
tr_file="$SANDBOX/transcript.jsonl"
printf '%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"first"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"the final report"}]}}' \
  >"$tr_file"
printf '{"session_id":"s1","agent_type":"Plan","transcript_path":"%s"}' "$tr_file" |
  bash "$H/session-journal-subagent.sh" >/dev/null
assert_contains "$(tail -1 "$d/entries.txt" | jq -r .body)" "the final report" "transcript fallback"

# --- Nudge -------------------------------------------------------------------
# Fresh workspace with hook-only activity: Stop should nudge.
export CMUX_WORKSPACE_ID="aaaaaaaa-0000-0000-0000-000000000000"
printf '{"session_id":"s9","cwd":"%s","source":"startup"}' "$CMUX_AGENT_LAUNCH_CWD" |
  bash "$H/session-journal-start.sh" >/dev/null
printf '{"session_id":"s9","tool_name":"Edit","tool_input":{"file_path":"%s/x.ts"}}' \
  "$CMUX_AGENT_LAUNCH_CWD" | bash "$H/session-journal-tool.sh"
out=$(printf '{"session_id":"s9"}' | bash "$H/session-journal-stop.sh")
assert_contains "$out" "logged no reasoning" "nudge fires after silent work"

# With an agent entry present, no nudge.
"$H/session-journal" add --kind decision --title "reasoned about it"
printf '{"session_id":"s9","tool_name":"Edit","tool_input":{"file_path":"%s/y.ts"}}' \
  "$CMUX_AGENT_LAUNCH_CWD" | bash "$H/session-journal-tool.sh"
out=$(printf '{"session_id":"s9"}' | bash "$H/session-journal-stop.sh")
assert_contains "$out" "" ""
printf '%s' "$out" | grep -q "logged no reasoning" && fail "must not nudge when reasoning exists"

# --- Disabled ----------------------------------------------------------------
echo DISABLED >"$SJ_STATE_FILE"
before=$(wc -l <"$d/entries.txt")
printf '{"session_id":"s2"}' | bash "$H/session-journal-start.sh" >/dev/null || fail "must exit 0"
printf '{"session_id":"s2","tool_name":"Edit","tool_input":{"file_path":"/x"}}' |
  bash "$H/session-journal-tool.sh" || fail "must exit 0"
printf '{"session_id":"s2"}' | bash "$H/session-journal-subagent.sh" >/dev/null || fail "must exit 0"
printf '{"session_id":"s2"}' | bash "$H/session-journal-stop.sh" >/dev/null || fail "must exit 0"
assert_eq "$(wc -l <"$d/entries.txt")" "$before" "no writes when disabled"

# --- Malformed input must never crash a hook ---------------------------------
echo ENABLED >"$SJ_STATE_FILE"
for h in start tool subagent stop; do
  echo 'not json at all' | bash "$H/session-journal-$h.sh" >/dev/null 2>&1 ||
    fail "$h must survive malformed stdin"
  printf '' | bash "$H/session-journal-$h.sh" >/dev/null 2>&1 ||
    fail "$h must survive empty stdin"
done

echo "test-hooks passed"
