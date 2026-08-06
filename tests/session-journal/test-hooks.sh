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
# The subject is read from git, not parsed out of the command string, so any
# invocation form works and a FAILED commit logs nothing.
git -C "$CMUX_AGENT_LAUNCH_CWD" init -q -b main 2>/dev/null
git -C "$CMUX_AGENT_LAUNCH_CWD" config user.email t@t 2>/dev/null
git -C "$CMUX_AGENT_LAUNCH_CWD" config user.name t 2>/dev/null
git -C "$CMUX_AGENT_LAUNCH_CWD" commit -q --allow-empty -m "feat: a thing" 2>/dev/null

printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"git commit -m \\"feat: a thing\\""}}' |
  bash "$H/session-journal-tool.sh"
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .kind)" "commit"
assert_contains "$(tail -1 "$d/entries.txt" | jq -r .title)" "feat: a thing" "subject read from git"

# The same HEAD must not be logged twice (the hook can fire more than once).
before=$(wc -l <"$d/entries.txt")
printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"git commit -m \\"feat: a thing\\""}}' |
  bash "$H/session-journal-tool.sh"
assert_eq "$(wc -l <"$d/entries.txt")" "$before" "same HEAD not logged twice"

# A FAILED commit leaves HEAD unchanged, so nothing new is written.
before=$(wc -l <"$d/entries.txt")
printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"git commit -m \\"never landed\\""}}' |
  bash "$H/session-journal-tool.sh"
assert_eq "$(wc -l <"$d/entries.txt")" "$before" "failed commit must not be logged"

# A new commit IS logged, whatever quoting the command used.
git -C "$CMUX_AGENT_LAUNCH_CWD" commit -q --allow-empty -m "fix: quoted" 2>/dev/null
printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"git commit -F /tmp/msg"}}' |
  bash "$H/session-journal-tool.sh"
assert_contains "$(tail -1 "$d/entries.txt" | jq -r .title)" "fix: quoted" "works regardless of -m quoting"

before=$(wc -l <"$d/entries.txt")
printf '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls -la"}}' |
  bash "$H/session-journal-tool.sh"
assert_eq "$(wc -l <"$d/entries.txt")" "$before" "ordinary bash must not be logged"

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

# Transcript fallback. VERIFIED LIVE: `transcript_path` points at the PARENT
# session's transcript, so a naive read captures the parent's narration instead
# of the subagent's report. The subagent's own transcript lives beside it under
# subagents/agent-<id>.jsonl. This asserts we prefer the right one.
tr_file="$SANDBOX/transcript.jsonl"
printf '%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"PARENT narration, must not be captured"}]}}' \
  >"$tr_file"
mkdir -p "$SANDBOX/subagents"
printf '%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"first"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"THE SUBAGENT REPORT"}]}}' \
  >"$SANDBOX/subagents/agent-abc123.jsonl"
printf '{"agentType":"Explore","description":"probe"}' \
  >"$SANDBOX/subagents/agent-abc123.meta.json"

printf '{"session_id":"s1","transcript_path":"%s"}' "$tr_file" |
  bash "$H/session-journal-subagent.sh" >/dev/null
last=$(tail -1 "$d/entries.txt")
assert_contains "$(printf '%s' "$last" | jq -r .body)" "THE SUBAGENT REPORT" "reads the subagent's own transcript"
printf '%s' "$last" | jq -r .body | grep -q "PARENT narration" &&
  fail "captured the parent transcript instead of the subagent's"
assert_eq "$(printf '%s' "$last" | jq -r .agent)" "Explore" "agent type recovered from the meta sidecar"

# An explicit agent_id selects that exact transcript, not merely the newest.
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"OLDER SPECIFIC ONE"}]}}' \
  >"$SANDBOX/subagents/agent-older.jsonl"
touch -t 202001010000 "$SANDBOX/subagents/agent-older.jsonl"
printf '{"session_id":"s1","agent_type":"Plan","agent_id":"older","transcript_path":"%s"}' "$tr_file" |
  bash "$H/session-journal-subagent.sh" >/dev/null
assert_contains "$(tail -1 "$d/entries.txt" | jq -r .body)" "OLDER SPECIFIC ONE" "agent_id wins over recency"

# Parent transcript is still the last resort when no subagents dir exists.
rm -rf "$SANDBOX/subagents"
printf '{"session_id":"s1","agent_type":"Plan","transcript_path":"%s"}' "$tr_file" |
  bash "$H/session-journal-subagent.sh" >/dev/null
assert_contains "$(tail -1 "$d/entries.txt" | jq -r .body)" "PARENT narration" "falls back to parent as last resort"

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
printf '%s' "$out" | grep -q "logged no reasoning" && fail "must not nudge when reasoning exists"

# --- UserPromptSubmit --------------------------------------------------------
# Prompts are the best index of what a session was doing, but only a truncated
# first line is stored — these land in ~/html-pages as plaintext.
export CMUX_WORKSPACE_ID="11111111-2222-3333-4444-555555555555"
d=$("$H/session-journal" path)
printf '{"session_id":"s1","prompt":"Fix the auth bug in the login flow"}' |
  bash "$H/session-journal-prompt.sh" >/dev/null
last=$(tail -1 "$d/entries.txt")
assert_eq "$(printf '%s' "$last" | jq -r .kind)" "prompt"
assert_contains "$(printf '%s' "$last" | jq -r .title)" "Fix the auth bug" "prompt captured"

# Only the FIRST line, and no body: we index the session, not archive it.
printf '{"session_id":"s1","prompt":"first line here\\nsecond line\\nthird line"}' |
  bash "$H/session-journal-prompt.sh" >/dev/null
last=$(tail -1 "$d/entries.txt")
assert_contains "$(printf '%s' "$last" | jq -r .title)" "first line here"
printf '%s' "$last" | jq -r .title | grep -q "second line" && fail "must store only the first line"
assert_eq "$(printf '%s' "$last" | jq -r .body)" "" "prompt body must stay empty"

# Long prompts are capped at ~120 chars.
long=$(head -c 400 </dev/zero | tr '\0' 'z')
printf '{"session_id":"s1","prompt":"%s"}' "$long" |
  bash "$H/session-journal-prompt.sh" >/dev/null
tlen=$(tail -1 "$d/entries.txt" | jq -r .title | wc -c | tr -d ' ')
[ "$tlen" -le 130 ] || fail "prompt title not truncated: $tlen chars"

# Leading blank lines are skipped rather than producing an empty entry.
printf '{"session_id":"s1","prompt":"\\n\\n   \\nreal content"}' |
  bash "$H/session-journal-prompt.sh" >/dev/null
assert_contains "$(tail -1 "$d/entries.txt" | jq -r .title)" "real content" "skips blank lines"

# An empty prompt writes nothing at all.
before=$(wc -l <"$d/entries.txt")
printf '{"session_id":"s1","prompt":""}' | bash "$H/session-journal-prompt.sh" >/dev/null
assert_eq "$(wc -l <"$d/entries.txt")" "$before" "empty prompt writes nothing"

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
for h in start tool subagent stop prompt; do
  echo 'not json at all' | bash "$H/session-journal-$h.sh" >/dev/null 2>&1 ||
    fail "$h must survive malformed stdin"
  printf '' | bash "$H/session-journal-$h.sh" >/dev/null 2>&1 ||
    fail "$h must survive empty stdin"
done

echo "test-hooks passed"
