#!/usr/bin/env bash
# Journal identity: stable, unique per workspace, safe as a directory name.
set -uo pipefail
. "$(dirname "$0")/assert.sh"
LIB="$(cd "$(dirname "$0")/../../programs/claude/hooks/lib" && pwd)/session-journal-common.sh"

setup_sandbox
trap teardown_sandbox EXIT
. "$LIB"

git -C "$CMUX_AGENT_LAUNCH_CWD" init -q -b main 2>/dev/null

assert_eq "$(sj_wsid8)" "11111111" "wsid8 is the first 8 chars of the workspace uuid"

slug=$(sj_slug)
assert_contains "$slug" "session-" "slug carries the session marker"
assert_contains "$slug" "11111111" "slug carries the workspace id"
assert_contains "$slug" "main" "slug carries the branch"
case "$slug" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-session-*) ;;
  *) fail "slug must start with a date: $slug" ;;
esac

assert_eq "$(sj_slug)" "$slug" "slug is stable across calls"

# THE collision case: same repo, same branch, same day, different workspace.
# This is exactly what the wsid8 suffix exists to prevent.
a=$(sj_slug)
b=$(CMUX_WORKSPACE_ID="99999999-0000-0000-0000-000000000000" sj_slug)
[ "$a" != "$b" ] || fail "distinct workspaces collided on: $a"

# Once the directory exists, the slug must resolve to it rather than re-dating.
mkdir -p "$SJ_PAGES_DIR/$slug"
assert_eq "$(sj_slug)" "$slug" "existing directory is reused"

# A slug found on disk must win even if today's date differs from creation date.
old="2020-01-01-session-repo-main-$(sj_wsid8)"
rm -rf "$SJ_PAGES_DIR/$slug"
mkdir -p "$SJ_PAGES_DIR/$old"
assert_eq "$(sj_slug)" "$old" "creation date preserved, no rotation"
rm -rf "$SJ_PAGES_DIR/$old"

# Branch names with slashes must not create nested directories.
git -C "$CMUX_AGENT_LAUNCH_CWD" checkout -q -b feature/foo/bar 2>/dev/null
s=$(sj_slug)
case "$s" in
  */*) fail "slug must not contain a slash: $s" ;;
esac
assert_contains "$s" "feature-foo-bar" "slashes flattened to dashes"

# Outside cmux entirely: still stable and still unique.
s1=$(env -u CMUX_WORKSPACE_ID bash -c ". '$LIB'; sj_slug")
s2=$(env -u CMUX_WORKSPACE_ID bash -c ". '$LIB'; sj_slug")
assert_eq "$s1" "$s2" "fallback identity is stable"
[ -n "$s1" ] || fail "fallback identity must not be empty"

# sj_dir is just the slug under the pages dir.
assert_eq "$(sj_dir)" "$SJ_PAGES_DIR/$(sj_slug)" "sj_dir composes correctly"

echo "test-identity passed"
