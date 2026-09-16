#!/usr/bin/env bash
# Highlight the workspace pill matching WM_WORKSPACE.
#
# Invoked for every space.N item on wm_workspace_changed, so each item decides
# for itself whether it is the active one. $NAME is "space.<n>". The active
# pill gets a filled mauve background with dark (base) text/icon for contrast;
# inactive pills are dim with no background.
set -u
n="${NAME#space.}"
active="${WM_WORKSPACE:-}"

if [ -n "$active" ] && [ "$n" = "$active" ]; then
  # active: dark glyph on the filled mauve circle for contrast
  sketchybar --set "$NAME" \
    icon.color="${COLOR_ON_ACCENT:-0xff1e1e2e}" \
    background.drawing=on \
    background.color="${COLOR_ACCENT:-0xffcba6f7}"
else
  # inactive: light Flamingo glyph, no circle
  sketchybar --set "$NAME" \
    icon.color="${COLOR_FLAMINGO:-0xfff2cdcd}" \
    background.drawing=off
fi
