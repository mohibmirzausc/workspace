#!/usr/bin/env bash
# Shared script for the date and time items; branches on $NAME.
#   time -> 12-hour clock with AM/PM   (e.g. "8:45 PM")
#   date -> [Day of week] YYYY-MM-DD   (e.g. "Monday 2026-09-14")
set -u
case "$NAME" in
  time)
    # %l is 12-hour, space-padded; strip the leading space.
    sketchybar --set "$NAME" label="$(date '+%l:%M %p' | sed 's/^ *//')"
    ;;
  date)
    sketchybar --set "$NAME" label="$(date '+%A %Y-%m-%d')"
    ;;
  *)
    sketchybar --set "$NAME" label="$(date '+%A %Y-%m-%d  %l:%M %p' | sed 's/  */ /g')"
    ;;
esac
