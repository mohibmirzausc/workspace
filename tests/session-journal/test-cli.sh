#!/usr/bin/env bash
# The session-journal CLI end to end.
set -uo pipefail
. "$(dirname "$0")/assert.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLI="$ROOT/programs/claude/hooks/session-journal"

setup_sandbox
trap teardown_sandbox EXIT

# When disabled, add is a silent no-op that still exits 0 — a failing hook would
# surface as an error inside the user's Claude session.
# (Journaling is ENABLED by default, so disable explicitly to test this path.)
echo DISABLED >"$SJ_STATE_FILE"
"$CLI" add --kind decision --title "should not appear" || fail "must exit 0 when disabled"
assert_eq "$(find "$SJ_PAGES_DIR" -name entries.txt | wc -l | tr -d ' ')" "0" "nothing written when disabled"

# Validation happens even while disabled, so typos surface immediately.
"$CLI" add --kind bogus --title x 2>/dev/null && fail "invalid --kind must fail"
"$CLI" add --title "no kind" 2>/dev/null && fail "missing --kind must fail"
"$CLI" add --kind decision 2>/dev/null && fail "missing --title must fail"

echo ENABLED >"$SJ_STATE_FILE"

"$CLI" init || fail "init failed"
d=$("$CLI" path)
assert_file_exists "$d/index.html" "index.html must exist or the gallery skips the dir"
assert_file_exists "$d/entries.txt"
assert_file_exists "$d/meta.json"

# Every placeholder substituted.
grep -q '{{' "$d/index.html" && fail "unsubstituted placeholder left in page"
grep -q 'session-journal:workspace-id' "$d/index.html" || fail "missing marker meta tag"
grep -q "$CMUX_WORKSPACE_ID" "$d/index.html" || fail "workspace id not embedded in page"
grep -q 'Session journal' "$d/index.html" || fail "gallery stamp missing"

# The page must not SUBSCRIBE to the server's SSE reload stream: doing so would
# hard-reload the page on every append. (The template mentions EventSource in a
# comment explaining exactly this, so match construction, not the bare word.)
grep -qE 'new[[:space:]]+EventSource' "$d/index.html" && fail "page must not construct an EventSource"
grep -q 'reload-events' "$d/index.html" && fail "page must not hit the SSE endpoint"

# init is idempotent and must not clobber existing entries.
"$CLI" add --kind progress --title "first"
"$CLI" init
assert_eq "$(wc -l <"$d/entries.txt" | tr -d ' ')" "1" "init preserved entries"

"$CLI" add --kind decision --title "chose X" --body "because Y"
assert_eq "$(wc -l <"$d/entries.txt" | tr -d ' ')" "2"
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .title)" "chose X"
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .body)" "because Y"
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .source)" "agent" "defaults to agent"

# Body from stdin, for long text.
echo "streamed body" | "$CLI" add --kind progress --title "from stdin" --body-stdin
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .body)" "streamed body"

# --source override, used by the hooks.
"$CLI" add --kind files --title "hooked" --source hook
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .source)" "hook"

# add auto-creates the journal without an explicit init.
rm -rf "$d"
"$CLI" add --kind progress --title "autocreate"
assert_file_exists "$d/index.html" "add must auto-init"
assert_eq "$(wc -l <"$d/entries.txt" | tr -d ' ')" "1"

# tail is bounded: the file is never pruned, so unbounded reads are a bug.
for i in 1 2 3 4 5; do "$CLI" add --kind progress --title "e$i"; done
assert_eq "$("$CLI" tail -n 2 | wc -l | tr -d ' ')" "2" "tail -n 2 returns 2"
assert_eq "$("$CLI" tail | wc -l | tr -d ' ')" "6" "default tail returns all 6 (< 20)"

"$CLI" status | grep -q ENABLED || fail "status should report ENABLED"
echo DISABLED >"$SJ_STATE_FILE"
"$CLI" status | grep -q DISABLED || fail "status should report DISABLED"

# Disabled mid-flight: further adds are dropped.
before=$(wc -l <"$d/entries.txt")
"$CLI" add --kind progress --title "must not appear"
assert_eq "$(wc -l <"$d/entries.txt")" "$before" "no writes once disabled"

# Unknown subcommand exits non-zero with usage.
"$CLI" bogus 2>/dev/null && fail "unknown subcommand must fail"

echo "test-cli passed"
