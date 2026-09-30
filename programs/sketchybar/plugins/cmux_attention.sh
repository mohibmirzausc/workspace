#!/usr/bin/env bash
# "Sessions that need you" items: attn.need (red bell: count of Claude
# sessions waiting for input, then the Caps keys of the workspaces holding
# them) and attn.done (check: finished with an unread notification). Each is
# hidden at zero.
#
# Renders ~/.cache/cmux-attention/state.json, which the cmux-attention
# launchd agent keeps current (programs/cmux/attention.py) and announces with
# cmux_attention_changed. Runs as attn.need's script and sets BOTH items, so
# one event costs one process.
#
# A state file older than STALE_SECS hides both items: the agent rewrites it
# at least every 30s, so an old file means the agent is dead, and a stale
# "needs you" is worse than none. update_freq on the item re-checks this.
set -u
STATE="${CMUX_ATTENTION_DIR:-$HOME/.cache/cmux-attention}/state.json"
STALE_SECS=120
RED="${COLOR_RED:-0xfff38ba8}"
FG="${COLOR_FG:-0xffcdd6f4}"

hide() {
  sketchybar --set attn.need drawing=off --set attn.done drawing=off >/dev/null 2>&1
  exit 0
}

[ -f "$STATE" ] || hide
# Numeric guard before arithmetic; see the stat note in wm_window_list.sh.
mt=$(/usr/bin/stat -f %m "$STATE" 2>/dev/null)
case "$mt" in (*[!0-9]*|'') hide ;; esac
[ $(( $(date +%s) - mt )) -gt "$STALE_SECS" ] && hide

# Fields joined with 0x1F rather than tab: tab is IFS whitespace, so `read`
# would collapse an empty keys field and shift the counts (the bridge.sh
# note has the details). Keys are workspace keys built by attention.py, but
# control characters are stripped anyway so a newline cannot split the row.
row=$(jq -r '[.need.count, .need.keys, .done.count, .done.keys]
             | map(. // "" | tostring | gsub("[\u0000-\u001f]"; " "))
             | join("\u001f")' "$STATE" 2>/dev/null) || hide
IFS=$'\x1f' read -r need_n need_keys done_n done_keys <<< "$row"
case "${need_n:-}" in (*[!0-9]*|'') need_n=0 ;; esac
case "${done_n:-}" in (*[!0-9]*|'') done_n=0 ;; esac

args=()
if [ "$need_n" -gt 0 ]; then
  args+=(--set attn.need drawing=on icon.color="$RED" label.color="$RED"
    label="$need_n${need_keys:+ $need_keys}")
else
  args+=(--set attn.need drawing=off)
fi
if [ "$done_n" -gt 0 ]; then
  args+=(--set attn.done drawing=on icon.color="$FG" label.color="$FG"
    label="$done_n${done_keys:+ $done_keys}")
else
  args+=(--set attn.done drawing=off)
fi
sketchybar "${args[@]}" >/dev/null 2>&1
