#!/usr/bin/env bash
# Recolour the focus border when the focused window is a scratchpad.
#
# JankyBorders knows nothing about scratchpads, so the colour is pushed from
# outside: this runs on wm_focus_changed and re-invokes `borders`, which
# messages the running instance rather than starting a second one.
#
# A focused scratchpad reports isFocused=true AND isScratchpad=true -- but
# also isVisible=true and hiddenReason=null, so only isScratchpad
# distinguishes it. (Verified with `omniwmctl command scratchpad toggle`.)
set -u

BORDERS="${WM_BORDERS_BIN:-borders}"
command -v "$BORDERS" >/dev/null 2>&1 || exit 0
command -v omniwmctl   >/dev/null 2>&1 || exit 0

normal="${WM_BORDER_COLOR:-0xffcba6f7}"
scratch="${WM_BORDER_COLOR_SCRATCH:-0xfff9e2af}"

# Exit status, not stdout: a failed query must not read as "not a scratchpad"
# and repaint mid-toggle.
if ! json=$(omniwmctl query windows --format json 2>/dev/null); then
  exit 0
fi

# Prints "1" only for a focused scratchpad; anything unexpected -> normal.
is_scratch=$(printf '%s' "$json" | /usr/bin/python3 -c '
import json, sys
try:
    ws = json.load(sys.stdin)["result"]["payload"]["windows"]
except Exception:
    sys.exit(0)
for w in ws:
    if w.get("isFocused") and w.get("isScratchpad"):
        print("1")
        break
' 2>/dev/null)

if [ "$is_scratch" = "1" ]; then
  "$BORDERS" active_color="$scratch" >/dev/null 2>&1 &
else
  "$BORDERS" active_color="$normal" >/dev/null 2>&1 &
fi
exit 0
