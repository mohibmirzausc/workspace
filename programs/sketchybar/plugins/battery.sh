#!/usr/bin/env bash
# Battery level glyph + percentage as coloured text. No background.
#
# GLYPHS ARE RAW UTF-8 BYTE ESCAPES ($'\xf3\xb0...'), never $'\uXXXX'. Apple ships
# bash 3.2.57, which predates the \u/\U escapes (added in bash 4.2) and passes
# them through as literal text -- that was the real cause of the bar showing
# "\uf242" instead of a glyph. \xNN escapes work in 3.2, including for the
# 4-byte sequences these above-BMP nf-md codepoints need (verified).
#
# VERIFICATION TRAP: `sketchybar --query` re-escapes a private-use codepoint
# as "\uf242" in its JSON, and json.loads decodes it right back to one
# codepoint -- so a BROKEN value inspects as correct. Check the raw query
# bytes, or just look at the bar.
#
# The glyphs are the nf-md set (U+F0079..F0084), chosen by RENDERING them and
# looking, not from a cheatsheet: this font's PUA layout does not match the
# published maps (U+F376+, where nf-mdi battery icons are documented to live,
# is LibreOffice icons in DepartureMono).
set -u
info=$(pmset -g batt 2>/dev/null)
pct=$(echo "$info" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
[ -n "${pct:-}" ] || { sketchybar --set "$NAME" drawing=off; exit 0; }

charging=""
echo "$info" | grep -q "AC Power" && charging="yes"

# Glyph: a battery-with-bolt while charging, otherwise a level ramp.
if [ -n "$charging" ]; then icon=$'\xf3\xb0\x82\x84'
elif [ "$pct" -ge 95 ]; then icon=$'\xf3\xb0\x81\xb9'
elif [ "$pct" -ge 80 ]; then icon=$'\xf3\xb0\x82\x83'
elif [ "$pct" -ge 60 ]; then icon=$'\xf3\xb0\x82\x81'
elif [ "$pct" -ge 40 ]; then icon=$'\xf3\xb0\x81\xbf'
elif [ "$pct" -ge 20 ]; then icon=$'\xf3\xb0\x81\xbd'
elif [ "$pct" -ge 10 ]; then icon=$'\xf3\xb0\x81\xbb'
else icon=$'\xf3\xb0\x81\xba'; fi

# Colour: graduated warning as the charge falls, so a glance at the colour is
# enough. Charging always reads green regardless of level -- the state matters
# more than the number once it is going back up.
if [ -n "$charging" ]; then
  color="${COLOR_GREEN:-0xffa6e3a1}"
elif [ "$pct" -le 10 ]; then
  color="${COLOR_RED:-0xfff38ba8}"
elif [ "$pct" -le 20 ]; then
  color="${COLOR_PEACH:-0xfffab387}"
elif [ "$pct" -le 35 ]; then
  color="${COLOR_YELLOW:-0xfff9e2af}"
else
  color="${COLOR_LAVENDER:-0xffb4befe}"
fi

sketchybar --set "$NAME" drawing=on \
  icon="$icon" icon.color="$color" \
  icon.font="${WM_BAR_FONT:-Menlo}:Regular:15.0" \
  icon.padding_left=6 icon.padding_right=2 \
  label="${pct}%" label.color="$color"
