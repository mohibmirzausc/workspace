#!/usr/bin/env bash
# Append: one valid JSON object per line, whatever the content.
set -uo pipefail
. "$(dirname "$0")/assert.sh"
LIB="$(cd "$(dirname "$0")/../../programs/claude/hooks/lib" && pwd)/session-journal-common.sh"

setup_sandbox
trap teardown_sandbox EXIT
. "$LIB"
echo ENABLED >"$SJ_STATE_FILE"

d=$(sj_dir)
mkdir -p "$d"
f="$d/entries.txt"

sj_append "decision" "agent" "Picked bash" "Because hooks must start fast"

assert_file_exists "$f"
assert_eq "$(wc -l <"$f" | tr -d ' ')" "1" "one line"
assert_valid_jsonl "$f"
assert_eq "$(jq -r .kind <"$f")" "decision"
assert_eq "$(jq -r .source <"$f")" "agent"
assert_eq "$(jq -r .title <"$f")" "Picked bash"
assert_eq "$(jq -r .body <"$f")" "Because hooks must start fast"
assert_eq "$(jq -r .workspace_id <"$f")" "$CMUX_WORKSPACE_ID"
assert_eq "$(jq -r .agent <"$f")" "main" "defaults to main"
[ -n "$(jq -r .ts <"$f")" ] || fail "timestamp missing"

# Embedded newlines, quotes and tabs must not break one-entry-per-line.
sj_append "progress" "agent" 'Title with "quotes" and \backslash' 'line1
line2	tabbed
line3 "quoted"'
assert_eq "$(wc -l <"$f" | tr -d ' ')" "2" "multiline body is still one line"
assert_valid_jsonl "$f"
body=$(tail -1 "$f" | jq -r .body)
assert_contains "$body" "line2" "newlines survive as JSON escapes"
assert_contains "$body" "line3" "all lines preserved"
assert_contains "$(tail -1 "$f" | jq -r .title)" 'quotes' "quotes survive"

# Oversized bodies are truncated, never dropped and never corrupting.
sj_append "progress" "agent" "big" "$(head -c 20000 </dev/zero | tr '\0' 'x')"
assert_valid_jsonl "$f"
last=$(tail -1 "$f")
blen=$(printf '%s' "$last" | jq -r .body | wc -c | tr -d ' ')
[ "$blen" -le 4200 ] || fail "body not truncated: $blen bytes"
assert_contains "$(printf '%s' "$last" | jq -r .body)" "truncated" "truncation marker present"

# Session/pane/agent context is carried through when set.
SJ_SESSION_ID="sess-1" CMUX_PANEL_ID="pane-1" SJ_AGENT="Explore" \
  sj_append "subagent" "subagent" "did a thing" ""
last=$(tail -1 "$f")
assert_eq "$(printf '%s' "$last" | jq -r .session_id)" "sess-1"
assert_eq "$(printf '%s' "$last" | jq -r .pane_id)" "pane-1"
assert_eq "$(printf '%s' "$last" | jq -r .agent)" "Explore"

# Appending to a nonexistent journal dir fails soft rather than creating junk.
( SJ_PAGES_DIR="$SANDBOX/nope"; sj_append "progress" "agent" "x" "" )
[ -d "$SANDBOX/nope" ] && fail "must not create a stray pages dir"

# The lock is always released, even across many sequential appends.
for i in 1 2 3; do sj_append "progress" "agent" "seq$i" ""; done
[ -d "$d/.lock" ] && fail "lock left behind"

echo "test-append passed"
