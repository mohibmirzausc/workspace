#!/usr/bin/env bash
# Focused window title, from the WM bridge. Blank when the backend does not
# report one (rift's focused_window_changed carries only a window id).
set -u
if [ -z "${WM_TITLE:-}" ]; then
  sketchybar --set "$NAME" label.drawing=off
else
  sketchybar --set "$NAME" label.drawing=on label="${WM_TITLE}"
fi
