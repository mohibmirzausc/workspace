#!/usr/bin/env bash
# "Next meeting" item. Reads a background-refreshed cache (see
# meeting_refresh.sh); never runs the slow Calendar.app query inline.
#
# - click:            open Calendar to today
# - otherwise (tick / meeting_refreshed): render cache, and if the cache is
#   stale, spawn a single background refresh (non-blocking).
set -u
PLUGINS="${CONFIG_DIR:-$HOME/.config/sketchybar}/plugins"
CACHE_DIR="$HOME/.cache/sketchybar"
CACHE="$CACHE_DIR/nextmeeting"
LOCK="$CACHE_DIR/nextmeeting.lock"
STALE_SECS=300
mkdir -p "$CACHE_DIR"

cal_icon=''
peach="${COLOR_PEACH:-0xfffab387}"   # colored text

if [ "${1:-}" = "click" ]; then
  open -a Calendar
  exit 0
fi

# Single-flight background refresh when the cache is missing or stale. The
# mkdir lock is released by the refresher subshell; guard against a stale lock
# older than 5 min (a crashed refresh).
now=$(date +%s)
mtime=0; [ -f "$CACHE" ] && mtime=$(stat -f %m "$CACHE" 2>/dev/null || echo 0)
if [ ! -f "$CACHE" ] || [ $((now - mtime)) -ge "$STALE_SECS" ]; then
  if [ -d "$LOCK" ]; then
    lage=$(( now - $(stat -f %m "$LOCK" 2>/dev/null || echo "$now") ))
    [ "$lage" -ge "$STALE_SECS" ] && rmdir "$LOCK" 2>/dev/null
  fi
  if mkdir "$LOCK" 2>/dev/null; then
    ( "$PLUGINS/meeting_refresh.sh"; rmdir "$LOCK" 2>/dev/null ) >/dev/null 2>&1 &
  fi
fi

line=""
[ -f "$CACHE" ] && line=$(cat "$CACHE" 2>/dev/null)

if [ -z "$line" ]; then
  sketchybar --set "$NAME" icon="$cal_icon" icon.color="${COLOR_DIM:-0xff7f849c}" \
    label="…" label.color="${COLOR_DIM:-0xff7f849c}"
  exit 0
fi
if [ "$line" = "none" ]; then
  sketchybar --set "$NAME" icon="$cal_icon" icon.color="${COLOR_DIM:-0xff7f849c}" \
    label="No meetings" label.color="${COLOR_DIM:-0xff7f849c}"
  exit 0
fi

when="${line%%|*}"
title="${line#*|}"
sketchybar --set "$NAME" icon="$cal_icon" icon.color="$peach" \
  label="$when  $title" label.color="$peach"
