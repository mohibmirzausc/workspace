#!/usr/bin/env bash
# Window count for the active workspace/display.
#
# Most backends put a count in the event. paneru does not: its
# `windows_changed` event carries no window list at all, and only
# `on_screen_changed` does (the bridge derives WM_WINDOW_COUNT from it). This
# fallback covers the events that lack one, and the startup priming pass.
set -u
count="${WM_WINDOW_COUNT:-}"

if [ -z "$count" ] && [ "${WM_BACKEND:-}" = "paneru" ] && command -v paneru >/dev/null 2>&1; then
  # `query active` is a flat object with no window list; `query on-screen` is
  # the array of visible windows, spanning all displays -- so filter to the
  # active one.
  dpy=$(paneru query active --json 2>/dev/null | jq -r '.display_id // empty' 2>/dev/null)
  count=$(paneru query on-screen --json 2>/dev/null \
            | jq -r --arg dpy "${dpy:-}" \
                '[ .[] | select($dpy == "" or (.display_id | tostring) == $dpy) ] | length' \
                2>/dev/null)
  [ "$count" = "null" ] && count=""
fi

if [ -z "$count" ]; then
  sketchybar --set "$NAME" label.drawing=off
else
  sketchybar --set "$NAME" label.drawing=on \
    label="$count win$([ "$count" = "1" ] || echo s)"
fi
