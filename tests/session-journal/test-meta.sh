#!/usr/bin/env bash
# meta.json: read-modify-write from many writers. A torn file here degrades
# SILENTLY (the server falls back to title-only extraction), so this is the
# concurrency path that actually matters.
set -uo pipefail
. "$(dirname "$0")/assert.sh"
LIB="$(cd "$(dirname "$0")/../../programs/claude/hooks/lib" && pwd)/session-journal-common.sh"

setup_sandbox
trap teardown_sandbox EXIT
. "$LIB"
echo ENABLED >"$SJ_STATE_FILE"

d=$(sj_dir)
mkdir -p "$d"
m="$d/meta.json"

sj_meta_init
assert_file_exists "$m"
jq -e . "$m" >/dev/null || fail "meta.json is not valid JSON"
assert_eq "$(jq -r .kind "$m")" "session-journal" "discovery marker"
assert_eq "$(jq -r .style "$m")" "Session journal" "gallery style"
assert_eq "$(jq -r .cmux_workspace_id "$m")" "$CMUX_WORKSPACE_ID" "workspace marker"
assert_eq "$(jq -r .date "$m")" "$(date +%F)" "date present for gallery sorting"
[ "$(jq -r '.session_ids|type' "$m")" = "array" ] || fail "session_ids must be an array"

# init is idempotent: a second call must not reset accumulated state.
SJ_SESSION_ID="keeper" sj_meta_touch
sj_meta_init
assert_eq "$(jq -r '.session_ids|length' "$m")" "1" "init did not clobber existing meta"

# Session ids accumulate and dedupe (autoResumeAgentSessions restarts sessions).
SJ_SESSION_ID="aaa" sj_meta_touch
SJ_SESSION_ID="bbb" sj_meta_touch
SJ_SESSION_ID="aaa" sj_meta_touch
assert_eq "$(jq -r '.session_ids|length' "$m")" "3" "ids accumulate, deduped (keeper,aaa,bbb)"

# Pane ids likewise, and an empty pane id must not become an "" element.
CMUX_PANEL_ID="p1" SJ_SESSION_ID="aaa" sj_meta_touch
CMUX_PANEL_ID="" SJ_SESSION_ID="aaa" sj_meta_touch
assert_eq "$(jq -r '.pane_ids|length' "$m")" "1" "empty pane id not recorded"
assert_eq "$(jq -r '.pane_ids[0]' "$m")" "p1"

# date tracks LAST-UPDATED so active journals float to the top of the gallery.
jq '.date="2020-01-01"' "$m" >"$m.x" && mv "$m.x" "$m"
SJ_SESSION_ID="ccc" sj_meta_touch
assert_eq "$(jq -r .date "$m")" "$(date +%F)" "date refreshed to today"

# No temp files left behind.
assert_eq "$(find "$d" -name 'meta.json.tmp*' | wc -l | tr -d ' ')" "0" "no tmp litter"

# Writes only when something actually changes: meta.json IS inside the server's
# fs.watch filter, so a needless write reloads every open gallery tab.
CMUX_PANEL_ID="p1" SJ_SESSION_ID="ccc" sj_meta_touch
before=$(stat -f %m "$m")
sleep 1
CMUX_PANEL_ID="p1" SJ_SESSION_ID="ccc" sj_meta_touch
after=$(stat -f %m "$m")
assert_eq "$before" "$after" "no-op touch must not rewrite the file"

# Concurrent meta updates must never produce a torn file.
for i in $(seq 1 8); do
  (
    . "$LIB"
    for j in $(seq 1 12); do
      SJ_SESSION_ID="s$i-$j" sj_meta_touch
    done
  ) &
done
wait

jq -e . "$m" >/dev/null || fail "meta.json torn by concurrent writers"
n=$(jq -r '.session_ids|length' "$m")
[ "$n" -ge 96 ] || fail "expected at least the 96 concurrent ids, got $n"
assert_eq "$(find "$d" -name 'meta.json.tmp*' | wc -l | tr -d ' ')" "0" "no tmp litter after concurrency"
[ -d "$d/.lock" ] && fail "lock left behind"

echo "test-meta passed ($n session ids)"
