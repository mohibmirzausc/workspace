#!/bin/sh
# Warn when OmniWM is running but omniwmctl can't talk to it. Run by
# darwin.nix's postActivation, as the user, after the Homebrew step.
#
# That happens when brew upgrades the OmniWM cask under a running app:
# omniwmctl is a symlink into the NEW .app, and it fails every call against
# the old one, in a different way per release:
#   0.7.3 -> 0.7.4: error: protocol_mismatch (server protocol 16, app 0.7.3)
#   0.7.4 -> 0.7.5: omniwmctl: Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"
# so the trigger is "running, but ping doesn't answer pong", not any one
# message. That silently breaks everything that drives OmniWM: Karabiner's
# Caps+F5 and Caps+6, the sketchybar bridge, the cmux-attention locations,
# triage. Warn only; restarting OmniWM here could reshuffle windows
# mid-session. Not running at all is not this problem, so says nothing.
#
# Always exits 0: activation runs under set -e. Overridable for the tests:
# OMNIWMCTL, TIMEOUT (a coreutils timeout; ping is bounded so a hung app
# cannot stall activation), and pgrep via PATH.
ctl="${OMNIWMCTL:-/opt/homebrew/bin/omniwmctl}"
[ -x "$ctl" ] || exit 0
pgrep -x -U "$(id -u)" OmniWM >/dev/null 2>&1 || exit 0
out="$(${TIMEOUT:-timeout} 5 "$ctl" ping 2>&1)"
[ "$out" = pong ] && exit 0
printf '\033[1;33mwarning: OmniWM is running but omniwmctl cannot reach it (%s).\033[0m\n' \
  "$(printf '%s' "${out:-no answer}" | head -n 1)" >&2
echo "warning: if OmniWM was just upgraded, restart it (quit it from its menu bar icon, then reopen); until then omniwmctl, Caps+F5/Caps+6, the bar and triage fail." >&2
exit 0
