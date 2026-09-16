#!/usr/bin/env bash
# Shows which window manager is driving the bar. Click opens the keymap doc.
#
# The palette variables come from the sketchybar launchd agent's environment
# (set in ../default.nix), which plugins inherit; the defaults here are the
# same values, so the plugin still looks right if run by hand.
set -u
# Click opens OmniWM's command palette -- upstream opened a `wm-keys-open`
# keymap doc from its own repo, which does not exist in this setup.
if [ "${1:-}" = "click" ]; then
  /opt/homebrew/bin/omniwmctl command open-command-palette 2>/dev/null
  exit 0
fi
# Upstream fell back to `wm status` (its own multi-backend wrapper). Here the
# backend is always OmniWM, so fall back to that name directly.
sketchybar --set "$NAME" label="${WM_BACKEND:-omniwm}"
