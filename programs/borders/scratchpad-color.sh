#!/usr/bin/env bash
# Recolour the focused-window border to indicate whether that window is a
# scratchpad.
#
# JankyBorders has no idea what a scratchpad is -- it only knows the window
# server's focus. So the colour is driven from outside: this runs on
# wm_focus_changed (the bridge already emits it on every focus change, so no
# polling) and pushes a new active_color to the running borders instance.
#
# Re-running `borders <args>` does NOT start a second process. It messages the
# existing one, which is the documented way to change properties at runtime:
#   "A borders instance is already running ... To modify properties of the
#    running instance provide them as arguments."
#
# A focused scratchpad reports isFocused=true AND isScratchpad=true. Note it
# also reports isVisible=true and hiddenReason=null in that state -- only
# isScratchpad distinguishes it, which is why the test is on that field and
# not on visibility. (Verified with `omniwmctl command scratchpad toggle`; an
# older comment in wm_window_list.sh said this state was unreproducible.)
set -u

BORDERS="${WM_BORDERS_BIN:-borders}"
command -v "$BORDERS" >/dev/null 2>&1 || exit 0
command -v omniwmctl   >/dev/null 2>&1 || exit 0

normal="${WM_BORDER_COLOR:-0xffcba6f7}"
scratch="${WM_BORDER_COLOR_SCRATCH:-0xfff9e2af}"

# Exit status, not stdout, decides: a failed/absent query must not be read as
# "not a scratchpad" and silently repaint the border mid-toggle.
if ! json=$(omniwmctl query windows --format json 2>/dev/null); then
  exit 0
fi

# `is_scratch` prints "1" only for a window that is BOTH focused and a
# scratchpad. Anything unexpected in the payload yields empty -> normal colour.
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
