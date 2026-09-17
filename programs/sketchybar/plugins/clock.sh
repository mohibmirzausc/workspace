#!/usr/bin/env bash
# Time item. 12-hour clock, NO AM/PM suffix -- "8:20" for both 8:20am and
# 8:20pm. The meridiem is redundant on a machine you are sitting in front of
# and it costs ~3 characters of bar width next to the notch, which is the
# scarce resource here.
#
# Still branches on $NAME: the `date` item was removed from the bar, but the
# branch is kept so an ad-hoc `--set date script=clock.sh` still works rather
# than silently falling through to the wrong format.
set -u
case "$NAME" in
  date)
    sketchybar --set "$NAME" label="$(date '+%A %Y-%m-%d')"
    ;;
  *)
    # %l is 12-hour space-padded; strip the pad so the item hugs its text.
    sketchybar --set "$NAME" label="$(date '+%l:%M' | sed 's/^ *//')"
    ;;
esac
