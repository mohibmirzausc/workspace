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

# --- Stale lock must not stall a hook ----------------------------------------
# A 3000-iteration cap with `sleep 0.001` took ~18-26s in practice, because
# process spawn dominates. That is unacceptable inside a per-turn Stop hook.
d=$(sj_dir)
mkdir -p "$d"
sj_init >/dev/null
mkdir "$d/.lock" # simulate a holder that crashed without unlocking
start=$(date +%s)
sj_append progress agent "after stale lock" ""
end=$(date +%s)
elapsed=$((end - start))
[ "$elapsed" -le 5 ] || fail "stale-lock recovery took ${elapsed}s; must be a few seconds"
assert_eq "$(tail -1 "$d/entries.txt" | jq -r .title)" "after stale lock" "entry written after steal"
[ -d "$d/.lock" ] && fail "lock left behind after steal"

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

echo "test-edge-cases passed"
