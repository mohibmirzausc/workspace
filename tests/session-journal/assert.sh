#!/usr/bin/env bash
# Shared test helpers. Every test runs in an isolated sandbox HOME so nothing
# can touch the real ~/.claude or ~/html-pages.

setup_sandbox() {
  SANDBOX=$(mktemp -d)
  export HOME="$SANDBOX"
  export SJ_PAGES_DIR="$SANDBOX/html-pages"
  export SJ_STATE_FILE="$SANDBOX/.claude/session-journal-state"
  export SJ_RUNTIME_DIR="$SANDBOX/.claude/session-journal"
  mkdir -p "$SANDBOX/.claude" "$SJ_PAGES_DIR"

  export CMUX_WORKSPACE_ID="11111111-2222-3333-4444-555555555555"
  export CMUX_AGENT_LAUNCH_CWD="$SANDBOX/repo"
  mkdir -p "$CMUX_AGENT_LAUNCH_CWD"

  unset SESSION_JOURNAL
  unset CMUX_PANEL_ID
}

teardown_sandbox() {
  [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
  return 0
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "expected [$2] got [$1] ${3:-}"
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "[$1] does not contain [$2] ${3:-}" ;;
  esac
}

assert_file_exists() {
  [ -f "$1" ] || fail "missing file: $1 ${2:-}"
}

assert_valid_jsonl() {
  local f="$1" n=0 bad=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    n=$((n + 1))
    printf '%s' "$line" | jq -e . >/dev/null 2>&1 || bad=$((bad + 1))
  done <"$f"
  [ "$bad" -eq 0 ] || fail "$bad of $n lines in $f are not valid JSON"
}
