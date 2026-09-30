#!/bin/bash

# Beep when Claude stops or asks a question (settings.json: Stop,
# AskUserQuestion, SessionEnd).
#
# Not inside cmux. cmux hooks Claude Code itself and already plays its
# notification sound ("Funk", programs/cmux.nix) with a banner that says
# where the session is, so this beep only doubled it -- and with a dozen
# sessions the bare system beep says nothing about which one. Outside cmux
# (plain Ghostty, SSH) nothing else alerts, so the beep stays there.
# CMUX_WORKSPACE_ID is set in every cmux terminal and inherited by Claude
# and its hooks.
[ -n "${CMUX_WORKSPACE_ID:-}" ] && exit 0

# Read state file (default to ENABLED)
STATE_FILE="$HOME/.claude/beep-state"
if [ -f "$STATE_FILE" ]; then
  state=$(cat "$STATE_FILE")
else
  state="ENABLED"
  echo "ENABLED" > "$STATE_FILE"
fi

# Exit if muted
[ "$state" != "ENABLED" ] && exit 0

# Detect environment and beep accordingly
if [ -z "$SSH_CONNECTION" ] && [[ "$OSTYPE" == "darwin"* ]]; then
  # Local macOS: use osascript beep
  printf '\a'
  osascript -e 'beep 1' >/dev/null 2>&1 &
else
  # SSH or Linux: use terminal bell character
  printf '\a'
fi
