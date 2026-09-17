#!/usr/bin/env bash
# $INFO is the app name, from sketchybar's built-in front_app_switched event.
set -u
[ "${SENDER:-}" = "front_app_switched" ] || exit 0
sketchybar --set "$NAME" label="${INFO:-}"
