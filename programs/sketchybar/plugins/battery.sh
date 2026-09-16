#!/usr/bin/env bash
# Battery percentage with a level glyph, colored TEXT (lavender normally, red
# under 20% on battery). No background.
set -u
info=$(pmset -g batt 2>/dev/null)
pct=$(echo "$info" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
[ -n "${pct:-}" ] || { sketchybar --set "$NAME" drawing=off; exit 0; }

charging=""
echo "$info" | grep -q "AC Power" && charging="yes"

if [ -n "$charging" ]; then icon=$'\uf0e7'          # bolt
elif [ "$pct" -ge 90 ]; then icon=$'\uf240'         # full
elif [ "$pct" -ge 65 ]; then icon=$'\uf241'
elif [ "$pct" -ge 40 ]; then icon=$'\uf242'
elif [ "$pct" -ge 15 ]; then icon=$'\uf243'
else icon=$'\uf244'; fi                             # empty

color="${COLOR_LAVENDER:-0xffb4befe}"
[ "$pct" -le 20 ] && [ -z "$charging" ] && color="${COLOR_RED:-0xfff38ba8}"

sketchybar --set "$NAME" drawing=on \
  icon="$icon" icon.color="$color" \
  label="${pct}%" label.color="$color"
