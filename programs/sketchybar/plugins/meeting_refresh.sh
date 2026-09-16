#!/usr/bin/env bash
# Background refresher for the "next meeting" item. Writes one line to the cache:
#   none | "H:MM AM/PM|Title"     (next timed event later TODAY)
#
# Recurring-event handling: Calendar.app AppleScript returns a recurring event's
# ORIGINAL occurrence date from `start date`, not today's -- so filtering by that
# date shows the wrong day. BUT the `whose start date ...` filter *does* match by
# the today occurrence, and recurring events keep their wall-clock time, so we
# take today's date + the event's time-of-day to reconstruct today's occurrence.
# (EventKit would expand occurrences natively but is blocked by MDM on this Mac;
# synthetic clicks / AXPress are blocked too.)
set -u
CAL_MATCH="${WM_MEETING_CAL:-mechanical-orchard.com}"
CACHE_DIR="$HOME/.cache/sketchybar"
CACHE="$CACHE_DIR/nextmeeting"
mkdir -p "$CACHE_DIR"

result=$(osascript - "$CAL_MATCH" <<'AS'
on run argv
  set calMatch to item 1 of argv
  set nowD to (current date)
  set todayStart to nowD - (time of nowD)
  set todayEnd to todayStart + 86399
  set bestStart to missing value
  set bestTitle to ""
  tell application "Calendar"
    try
      set gcal to (first calendar whose title contains calMatch)
    on error
      return "none"
    end try
    set evs to (every event of gcal whose start date is greater than or equal to todayStart and start date is less than or equal to todayEnd)
    repeat with e in evs
      set msd to start date of e
      set med to end date of e
      set sTOD to (time of msd)
      set eTOD to (time of med)
      set occStart to todayStart + sTOD
      set occEnd to todayStart + eTOD
      -- skip all-day (span 0 or >= ~23h) and events already ended today
      if ((eTOD - sTOD) > 0 and (eTOD - sTOD) < 82800 and occEnd > nowD) then
        if (bestStart is missing value or occStart < bestStart) then
          set bestStart to occStart
          set bestTitle to (summary of e)
        end if
      end if
    end repeat
  end tell
  if bestStart is missing value then return "none"
  set t to (time of bestStart)
  set h24 to (t div 3600)
  set m to ((t mod 3600) div 60)
  set ampm to "AM"
  set h12 to h24
  if h24 = 0 then set h12 to 12
  if h24 is 12 then set ampm to "PM"
  if h24 > 12 then
    set h12 to (h24 - 12)
    set ampm to "PM"
  end if
  set mm to text -2 thru -1 of ("0" & m)
  return ((h12 as string) & ":" & mm & " " & ampm & "|" & bestTitle)
end run
AS
)

[ -z "${result:-}" ] && result="none"
tmp="$CACHE.tmp.$$"
printf '%s' "$result" > "$tmp" && mv "$tmp" "$CACHE"
command -v sketchybar >/dev/null 2>&1 && sketchybar --trigger meeting_refreshed >/dev/null 2>&1 || true
