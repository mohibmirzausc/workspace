#!/bin/bash

# SessionStart hook: idempotently ensure today's agent work-log note exists.
#
# Creates ~/src/notes/Daily/<YYYY-MM-DD>.md with a header and an empty log
# section if (and only if) it doesn't already exist. This guarantees the daily
# note is present before Claude does any work, rather than relying on the model
# to remember to create it (see ~/.claude/CLAUDE.md, section 2).
#
# Safe to run every session: if the note already exists it does nothing, so it
# never clobbers a day's accumulated log.

set -euo pipefail

NOTES_DIR="$HOME/src/notes"
DAILY_DIR="$NOTES_DIR/Daily"

# If the vault isn't present on this machine, do nothing (don't fail the session).
[ -d "$NOTES_DIR" ] || exit 0

TODAY="$(date +%Y-%m-%d)"
NOTE="$DAILY_DIR/$TODAY.md"

mkdir -p "$DAILY_DIR"

if [ ! -e "$NOTE" ]; then
  {
    printf '# %s\n\n' "$TODAY"
    printf '## Log\n\n'
  } > "$NOTE"
fi

exit 0
