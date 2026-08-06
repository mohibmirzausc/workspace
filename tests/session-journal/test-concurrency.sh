#!/usr/bin/env bash
# The test that justifies the mutex.
#
# flock(1) does not exist on macOS, so the lock is a mkdir directory. This test
# is the evidence that it actually holds under the real access pattern: several
# panes and subagents appending to one journal at once.
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

WRITERS=8
PER=40
EXPECTED=$((WRITERS * PER))

for w in $(seq 1 $WRITERS); do
  (
    . "$LIB"
    for i in $(seq 1 $PER); do
      sj_append "progress" "agent" "w$w-i$i" "$(head -c 400 </dev/zero | tr '\0' 'y')"
    done
  ) &
done
wait

got=$(wc -l <"$f" | tr -d ' ')
assert_eq "$got" "$EXPECTED" "no lost or duplicated writes"
assert_valid_jsonl "$f"

uniq=$(jq -r .title <"$f" | sort -u | wc -l | tr -d ' ')
assert_eq "$uniq" "$EXPECTED" "every entry distinct and intact"

[ -d "$d/.lock" ] && fail "lock left behind after concurrent writers"

echo "test-concurrency passed ($EXPECTED entries from $WRITERS writers)"
