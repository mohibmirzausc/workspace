#!/bin/sh
# Hang up: quit Tandem and Tuple.
#
# Neither app can be asked to leave a call directly. Both are unscriptable
# (NSAppleScriptEnabled false), neither exposes a leave/end-call menu item, and
# both are opaque to the Accessibility API -- measured: Tandem's window reports
# zero AXChildren even after AXManualAccessibility is forced on (it is Electron,
# whose web contents are never bridged to AX), and Tuple exposes no AX window at
# all. So there is no button to press; quitting the app is the only lever.
#
# SIGTERM first: both apps tear the call down cleanly and reconnect fine on
# relaunch. SIGKILL only for a process that ignores TERM, so a wedged app still
# dies rather than leaving the camera light on.
#
# pkill -x matches the main binary exactly. Tandem runs 9 processes (Electron
# helpers) and Tuple 3; the helpers exit with their parent, and an unanchored
# match would also hit this script's own command line.
for app in Tandem Tuple; do
  pkill -x "$app" 2>/dev/null || continue

  # Escalate only if it is still alive after a moment.
  n=0
  while [ "$n" -lt 20 ]; do
    pgrep -x "$app" >/dev/null 2>&1 || break
    sleep 0.1
    n=$((n + 1))
  done
  pgrep -x "$app" >/dev/null 2>&1 && pkill -9 -x "$app" 2>/dev/null
done

exit 0
