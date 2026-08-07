#!/usr/bin/env bash
# Regressions for bugs found by executing the code rather than reading it.
# Each of these shipped at some point; none is hypothetical.
set -uo pipefail
. "$(dirname "$0")/assert.sh"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/programs/claude/hooks/lib/session-journal-common.sh"
H="$ROOT/programs/claude/hooks"

setup_sandbox
trap teardown_sandbox EXIT
. "$LIB"
echo ENABLED >"$SJ_STATE_FILE"

# --- Locking: give up fast, steal only what is provably stale ----------------
# Two separate requirements, and an earlier version got the tradeoff wrong in
# both directions:
#   1. A 3000-iteration cap with `sleep 0.001` stalled 18-26s (process spawn
#      dominates), which is unacceptable in a hook that runs every turn.
#   2. Stealing purely on a timeout removed a LIVE holder's lock mid-critical-
#      section — three writers were observed holding it at once, and meta.json
#      (a read-modify-write) silently lost updates.
d=$(sj_dir)
mkdir -p "$d"
sj_init >/dev/null

# A FRESH lock belongs to a live holder: do NOT steal it, and do not stall.
mkdir "$d/.lock"
before=$(wc -l <"$d/entries.txt")
start=$(date +%s)
sj_append progress agent "must not appear" ""
elapsed=$(($(date +%s) - start))
[ "$elapsed" -le 5 ] || fail "waited ${elapsed}s on a live lock; must give up fast"
assert_eq "$(wc -l <"$d/entries.txt")" "$before" "must not write while another holder has the lock"
[ -d "$d/.lock" ] || fail "a live holder's lock must not be stolen"

# An OLD lock is presumed abandoned and IS stolen, so a crash cannot wedge the
# journal forever.
touch -t 202001010000 "$d/.lock"
start=$(date +%s)
sj_append progress agent "after stale lock" ""
elapsed=$(($(date +%s) - start))
[ "$elapsed" -le 5 ] || fail "stale-lock recovery took ${elapsed}s"
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .title)" "after stale lock" "entry written after stealing a stale lock"
[ -d "$d/.lock" ] && fail "lock left behind after steal"

# An unwritable journal dir is a permission error, not contention: bail at once
# rather than burning the full wait deadline on every hook.
if [ "$(id -u)" -ne 0 ]; then
  chmod 500 "$d"
  start=$(date +%s)
  sj_append progress agent "unwritable" "" 2>/dev/null
  elapsed=$(($(date +%s) - start))
  chmod 700 "$d"
  [ "$elapsed" -le 1 ] || fail "unwritable dir stalled ${elapsed}s; must fail immediately"
fi

# --- Blank lines in the edit buffer must not crash the Stop hook -------------
# `grep -c .` prints "0" AND exits 1 on no match, producing "0\n0".
buf="$SJ_RUNTIME_DIR/$(sj_wsid8)"
mkdir -p "$buf"
printf '\n\n' >"$buf/files.txt"
before=$(wc -l <"$d/entries.txt")
err=$(printf '{"session_id":"s1"}' | bash "$H/session-journal-stop.sh" 2>&1 >/dev/null)
case "$err" in
  *"integer expression"*) fail "blank buffer crashed the stop hook: $err" ;;
esac
assert_eq "$(wc -l <"$d/entries.txt")" "$before" "whitespace-only buffer writes nothing"

# --- Repo paths containing shell/sed metacharacters --------------------------
weird="$SANDBOX/we|ird&repo"
mkdir -p "$weird"
(
  export CMUX_AGENT_LAUNCH_CWD="$weird"
  export CMUX_WORKSPACE_ID="bbbbbbbb-0000-0000-0000-000000000000"
  . "$LIB"
  mkdir -p "$SJ_RUNTIME_DIR/$(sj_wsid8)"
  printf '%s/a.ts\n%s/b.ts\n' "$weird" "$weird" >"$SJ_RUNTIME_DIR/$(sj_wsid8)/files.txt"
  printf '{"session_id":"s1"}' | bash "$H/session-journal-stop.sh" >/dev/null 2>&1
  wd=$(sj_dir)
  [ -f "$wd/entries.txt" ] || fail "no journal created for a path with metacharacters"
  body=$(tail -1 "$wd/entries.txt" | jq -r .body)
  case "$body" in
    *"a.ts"*) ;;
    *) fail "file list mangled for weird path: [$body]" ;;
  esac
  # The repo prefix must actually have been stripped.
  case "$body" in
    "$weird"*) fail "prefix not stripped: [$body]" ;;
  esac
) || exit 1

# --- Branch names with HTML metacharacters must not corrupt the page ---------
# sed treats & in replacement text as "the whole match", so escaping to `a&amp;b`
# and feeding it to sed yields `a{{BRANCH}}amp;b`. We use awk instead.
repo2="$SANDBOX/repo2"
mkdir -p "$repo2"
git -C "$repo2" init -q -b 'main' 2>/dev/null
git -C "$repo2" commit -q --allow-empty -m init 2>/dev/null
git -C "$repo2" checkout -q -b 'feat/a&b<x>' 2>/dev/null
(
  export CMUX_AGENT_LAUNCH_CWD="$repo2"
  export CMUX_WORKSPACE_ID="cccccccc-0000-0000-0000-000000000000"
  . "$LIB"
  sj_init >/dev/null || fail "init failed on a branch with & and <"
  p="$(sj_dir)/index.html"
  assert_file_exists "$p"
  grep -q '{{' "$p" && fail "unsubstituted placeholder after weird branch"
  grep -q 'a&amp;b' "$p" || fail "ampersand not escaped correctly in page"
  grep -q '&lt;x&gt;' "$p" || fail "angle brackets not escaped in page"
) || exit 1

# --- Commitless repo: branch resolution must not emit multi-line garbage -----
# `git rev-parse --abbrev-ref HEAD` prints "HEAD" AND exits 128 on an unborn
# branch, so a `||` fallback concatenates into "HEAD\nnogit".
repo3="$SANDBOX/repo3"
mkdir -p "$repo3"
git -C "$repo3" init -q -b main 2>/dev/null
(
  export CMUX_AGENT_LAUNCH_CWD="$repo3"
  export CMUX_WORKSPACE_ID="dddddddd-0000-0000-0000-000000000000"
  . "$LIB"
  b=$(sj_branch_name)
  assert_eq "$b" "main" "unborn branch resolves cleanly"
  case "$b" in *$'\n'*) fail "branch name contains a newline" ;; esac
  s=$(sj_slug)
  case "$s" in *$'\n'*) fail "slug contains a newline" ;; esac
  sj_init >/dev/null || fail "init failed on a commitless repo"
) || exit 1

# --- Detached HEAD -----------------------------------------------------------
git -C "$repo2" commit -q --allow-empty -m second 2>/dev/null
sha=$(git -C "$repo2" rev-parse --short HEAD)
git -C "$repo2" checkout -q --detach 2>/dev/null
(
  export CMUX_AGENT_LAUNCH_CWD="$repo2"
  export CMUX_WORKSPACE_ID="eeeeeeee-0000-0000-0000-000000000000"
  . "$LIB"
  assert_eq "$(sj_branch_name)" "$sha" "detached HEAD falls back to the short sha"
) || exit 1

# --- Non-hex workspace id must still yield a usable, unique discriminator ----
a=$(CMUX_WORKSPACE_ID="zzzzzzzz-wxyz" sj_wsid8)
b=$(CMUX_WORKSPACE_ID="wwwwwwww-wxyz" sj_wsid8)
assert_eq "${#a}" "8" "wsid8 is always 8 chars"
[ "$a" != "$b" ] || fail "non-hex ids collided: both -> $a"

# --- meta.json must not be rewritten when nothing changed --------------------
# meta.json IS inside the gallery server's fs.watch filter, so a needless write
# broadcasts an SSE reload to every open tab (the R8 reload storm).
unset CMUX_PANEL_ID
export SJ_SESSION_ID="fixed-session"
d=$(sj_dir)
sj_meta_touch
m1=$(stat -f %m "$d/meta.json")
sleep 1
sj_meta_touch
sleep 1
sj_meta_touch
m2=$(stat -f %m "$d/meta.json")
assert_eq "$m1" "$m2" "no-op touch must not rewrite (empty pane id is not a change)"

# --- Journals are owner-only -------------------------------------------------
# They hold user prompts, agent reasoning, filenames and commit subjects, which
# may be client-confidential. umask 022 would otherwise make them world-readable.
jd=$(sj_dir)
assert_eq "$(stat -f %Lp "$jd")" "700" "journal dir is owner-only"
for f in index.html entries.txt meta.json; do
  assert_eq "$(stat -f %Lp "$jd/$f")" "600" "$f is owner-only"
done

# --- Temp files must not be predictable, and must not collide ----------------
# "$dir/meta.json.tmp.$$" collided across concurrent subshells (intermittent
# `mv: No such file or directory`) and was a symlink-follow target.
# Match an ASSIGNMENT, not the comments that explain why $$ was removed.
grep -nE '^[[:space:]]*(local[[:space:]]+)?tmp=.*\$\$' "$LIB" &&
  fail "predictable \$\$ temp name still assigned"
grep -q 'mktemp' "$LIB" || fail "mktemp not used for temp files"

# Hammer meta writes from parallel writers; no mv errors, no torn file, no litter.
err=$(
  for i in $(seq 1 8); do
    (
      . "$LIB"
      for j in $(seq 1 12); do SJ_SESSION_ID="p$i-$j" sj_meta_touch; done
    ) &
  done
  wait
  2>&1
)
case "$err" in
  *"No such file or directory"*) fail "temp-file race under concurrent meta writes: $err" ;;
esac
jq -e . "$jd/meta.json" >/dev/null || fail "meta.json torn under concurrent writers"
assert_eq "$(find "$jd" -name '.meta.json.*' -o -name 'meta.json.tmp*' | wc -l | tr -d ' ')" "0" "no temp litter"

# --- Every hook must exit 0 even with jq missing ------------------------------
# A non-zero hook surfaces as an error inside the user's Claude session.
# session-journal-start.sh previously ended on a bare `jq -n`, so its status
# became the hook's: exit 127 when jq was absent.
JQLESS=$(mktemp -d)
mkdir -p "$JQLESS/bin"
for c in bash cat date git mkdir rmdir stat printf sed awk grep tr cut head tail sort wc find basename dirname shasum mktemp mv rm chmod touch sleep id; do
  p=$(command -v "$c" 2>/dev/null) && ln -sf "$p" "$JQLESS/bin/$c" 2>/dev/null
done
for h in start tool subagent stop prompt; do
  printf '{"session_id":"x"}' |
    env -i HOME="$JQLESS" PATH="$JQLESS/bin" bash "$H/session-journal-$h.sh" >/dev/null 2>&1 ||
    fail "$h must exit 0 when jq is missing"
done
rm -rf "$JQLESS"

echo "test-edge-cases passed"
