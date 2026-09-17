#!/usr/bin/env bash
# Battery percentage as compact colored TEXT. No background, no icon.
#
# The level GLYPHS are deliberately gone. Nerd Font private-use-area
# codepoints set from the config render as literal "" text in this
# setup (see HANDOFF-sketchybar-glyphs.md), so a battery glyph here was
# costing width and showing garbage. The percentage already carries the
# information; charging state is carried by colour plus a "+" prefix, both
# of which are plain ASCII and always render.
set -u
info=$(pmset -g batt 2>/dev/null)
pct=$(echo "$info" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
[ -n "${pct:-}" ] || { sketchybar --set "$NAME" drawing=off; exit 0; }

charging=""
echo "$info" | grep -q "AC Power" && charging="yes"

# Colour IS the status indicator now that the glyph is gone:
#   green  charging
#   red    <=20% on battery
#   normal otherwise
color="${COLOR_LAVENDER:-0xffb4befe}"
label="${pct}%"
if [ -n "$charging" ]; then
  color="${COLOR_TEAL:-0xff94e2d5}"
  label="+${pct}%"
elif [ "$pct" -le 20 ]; then
  color="${COLOR_RED:-0xfff38ba8}"
fi

sketchybar --set "$NAME" drawing=on \
  icon.drawing=off \
  label="$label" label.color="$color"
