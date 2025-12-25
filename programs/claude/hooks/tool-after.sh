#!/bin/bash

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
