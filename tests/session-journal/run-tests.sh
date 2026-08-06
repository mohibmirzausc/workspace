#!/usr/bin/env bash
# Runs every test-*.sh in this directory and reports pass/fail.
# No test framework dependency — these are plain bash scripts that exit non-zero
# on failure, so they run anywhere bash and jq exist.
set -uo pipefail
cd "$(dirname "$0")"

pass=0
fail=0
filter="${1:-}"

for t in test-*.sh; do
  [ -e "$t" ] || continue
  if [ -n "$filter" ]; then
    case "$t" in *"$filter"*) ;; *) continue ;; esac
  fi
  out=$(bash "$t" 2>&1)
  rc=$?
  if [ $rc -eq 0 ]; then
    pass=$((pass + 1))
    printf '  ok   %s\n' "$t"
  else
    fail=$((fail + 1))
    printf '  FAIL %s\n' "$t"
    printf '%s\n' "$out" | sed 's/^/       /'
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
