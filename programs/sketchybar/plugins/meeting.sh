#!/usr/bin/env bash
# "Next meeting" item. Reads a background-refreshed cache (see
# meeting_refresh.sh); never runs the slow Calendar.app query inline.
#
# - click:            open Google Calendar to today
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
  # Google Calendar, not Calendar.app. Calendar.app is only the local mirror
  # that meeting_refresh.sh scrapes (it is the one thing AppleScript can read);
  # the events themselves live in Google, and that is where you want to be to
  # actually act on one -- join, RSVP, reschedule.
  #
  # `open` with a URL hands off to the default browser, which keeps whatever
  # Google session is already signed in. No -a, so this does not force a
  # particular browser.
  open "${WM_CAL_URL:-https://calendar.google.com/calendar/r/day}"
  exit 0
fi

# Single-flight background refresh when the cache is missing or stale. The
# mkdir lock is released by the refresher subshell; guard against a stale lock
# older than 5 min (a crashed refresh).
now=$(date +%s)
# Force a numeric mtime. `stat` on a missing file can still emit a non-numeric
# word, and under `set -u` arithmetic on that fails with a confusing
# "File: unbound variable" (it parses the word as a variable name) -- which was
# flooding ~/Library/Logs/sketchybar.log on every tick.
mtime=0
if [ -f "$CACHE" ]; then
  mtime=$(/usr/bin/stat -f %m "$CACHE" 2>/dev/null)
  case "$mtime" in (*[!0-9]*|'') mtime=0 ;; esac
fi
if [ ! -f "$CACHE" ] || [ $((now - mtime)) -ge "$STALE_SECS" ]; then
  if [ -d "$LOCK" ]; then
    lmt=$(/usr/bin/stat -f %m "$LOCK" 2>/dev/null)
    case "$lmt" in (*[!0-9]*|'') lmt="$now" ;; esac
    lage=$(( now - lmt ))
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
