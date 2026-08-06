#!/usr/bin/env bash
# Enable-flag resolution: env var > per-repo marker > state file > default off.
set -uo pipefail
. "$(dirname "$0")/assert.sh"
LIB="$(cd "$(dirname "$0")/../../programs/claude/hooks/lib" && pwd)/session-journal-common.sh"

setup_sandbox
trap teardown_sandbox EXIT
. "$LIB"

# 1. Default: no state file -> disabled, and the file is seeded so it exists after.
sj_enabled && fail "should be disabled by default"
assert_file_exists "$SJ_STATE_FILE" "seeded on first check"
assert_eq "$(cat "$SJ_STATE_FILE")" "DISABLED" "seed value"

# 2. State file ENABLED -> enabled.
echo ENABLED >"$SJ_STATE_FILE"
sj_enabled || fail "should be enabled via state file"

# 3. Env var 0 overrides an ENABLED state file.
SESSION_JOURNAL=0 sj_enabled && fail "env 0 must override state file"

# 4. Env var 1 overrides a DISABLED state file.
echo DISABLED >"$SJ_STATE_FILE"
SESSION_JOURNAL=1 sj_enabled || fail "env 1 must override state file"

# 5. Per-repo opt-out beats an ENABLED state file.
echo ENABLED >"$SJ_STATE_FILE"
touch "$CMUX_AGENT_LAUNCH_CWD/.no-session-journal"
sj_enabled && fail ".no-session-journal must disable"
rm "$CMUX_AGENT_LAUNCH_CWD/.no-session-journal"

# 6. Per-repo opt-in beats a DISABLED state file.
echo DISABLED >"$SJ_STATE_FILE"
touch "$CMUX_AGENT_LAUNCH_CWD/.session-journal"
sj_enabled || fail ".session-journal must enable"
rm "$CMUX_AGENT_LAUNCH_CWD/.session-journal"

# 7. Env var still wins over a per-repo marker.
touch "$CMUX_AGENT_LAUNCH_CWD/.session-journal"
SESSION_JOURNAL=0 sj_enabled && fail "env must outrank repo marker"

# 8. Whitespace/newlines in the state file are tolerated.
rm "$CMUX_AGENT_LAUNCH_CWD/.session-journal"
printf '  ENABLED  \n' >"$SJ_STATE_FILE"
sj_enabled || fail "must tolerate surrounding whitespace"

# 9. Garbage in the state file is treated as disabled, not as enabled.
printf 'banana\n' >"$SJ_STATE_FILE"
sj_enabled && fail "unrecognized state must be treated as disabled"

echo "test-enabled passed"
