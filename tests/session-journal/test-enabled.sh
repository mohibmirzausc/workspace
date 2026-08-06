#!/usr/bin/env bash
# Enable-flag resolution: env var > per-repo marker > state file > default off.
set -uo pipefail
. "$(dirname "$0")/assert.sh"
LIB="$(cd "$(dirname "$0")/../../programs/claude/hooks/lib" && pwd)/session-journal-common.sh"

setup_sandbox
trap teardown_sandbox EXIT
. "$LIB"

# 1. Default: no state file -> ENABLED, and the file is seeded so it exists after.
# Journaling is on by default because the point is monitoring many parallel
# sessions the user never individually configures.
sj_enabled || fail "should be enabled by default"
assert_file_exists "$SJ_STATE_FILE" "seeded on first check"
assert_eq "$(cat "$SJ_STATE_FILE")" "ENABLED" "seed value"

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

# 9. Only an explicit DISABLED turns it off. A garbled or partially-written
# state file must not silently stop journaling.
printf 'banana\n' >"$SJ_STATE_FILE"
sj_enabled || fail "unrecognized state should stay enabled"
printf '' >"$SJ_STATE_FILE"
sj_enabled || fail "empty state file should stay enabled"
printf 'DISABLED\n' >"$SJ_STATE_FILE"
sj_enabled && fail "explicit DISABLED must turn it off"

# 10. The per-repo opt-out is the escape hatch for client work, and must beat
# the enabled-by-default global.
printf 'ENABLED\n' >"$SJ_STATE_FILE"
touch "$CMUX_AGENT_LAUNCH_CWD/.no-session-journal"
sj_enabled && fail ".no-session-journal must win over the default"
rm "$CMUX_AGENT_LAUNCH_CWD/.no-session-journal"

# 11. Same when there is no state file at all (fresh machine, client repo).
rm -f "$SJ_STATE_FILE"
touch "$CMUX_AGENT_LAUNCH_CWD/.no-session-journal"
sj_enabled && fail ".no-session-journal must win on a fresh machine"
rm "$CMUX_AGENT_LAUNCH_CWD/.no-session-journal"

echo "test-enabled passed"
