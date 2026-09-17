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

# Level glyph by charge, or a bolt while charging.
#
# These are the nf-fa (Font Awesome) battery glyphs, which live in the BMP
# private-use area, NOT the nf-md ones at U+F0079.. -- that matters:
# bash 3.2 (what macOS ships, and what runs these plugins) supports the
# 4-hex-digit $'\uXXXX' escape but NOT the 8-digit $'\UXXXXXXXX' form. It
# passes \U through as literal text, so an nf-md glyph came out as the
# 10-character string "\U000f0080" and even corrupted `sketchybar --query`
# output into invalid JSON. Anything above U+FFFF is unreachable from here.
if [ -n "$charging" ]; then icon=$'\xef\x83\xa7'          # bolt
elif [ "$pct" -ge 88 ]; then icon=$'\xef\x89\x80'         # battery-full
elif [ "$pct" -ge 63 ]; then icon=$'\xef\x89\x81'         # three-quarters
elif [ "$pct" -ge 38 ]; then icon=$'\xef\x89\x82'         # half
elif [ "$pct" -ge 13 ]; then icon=$'\xef\x89\x83'         # quarter
else icon=$'\xef\x89\x84'; fi                             # empty

# Colour carries urgency; the glyph carries level.
color="${COLOR_LAVENDER:-0xffb4befe}"
if [ -n "$charging" ]; then
  color="${COLOR_TEAL:-0xff94e2d5}"
elif [ "$pct" -le 20 ]; then
  color="${COLOR_RED:-0xfff38ba8}"
fi

sketchybar --set "$NAME" drawing=on \
  icon="$icon" icon.color="$color" \
  icon.font="${WM_BAR_FONT:-Menlo}:Regular:15.0" \
  icon.padding_left=6 icon.padding_right=2 \
  label="${pct}%" label.color="$color"
