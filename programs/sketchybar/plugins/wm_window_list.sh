#!/usr/bin/env bash
# Fill the pre-created "windows" island with the windows of the CURRENT OmniWM
# workspace: up to MAXW pills (app icon + title, ~20 chars), focused highlighted,
# and a clickable "…" on each overflow side. Click a pill to focus that window.
#
# The items (win.lell, win.0..2, win.rell, bracket window_group) are PRE-CREATED
# in sketchybarrc in a fixed order and never added/removed here -- we only --set
# their content + drawing. That keeps their left-to-right order and the island
# background stable (runtime add/remove used to scramble order and drop the bg).
#
# Single-flight + coalescing so event bursts (workspace switch, spawning many
# windows) never overlap. OmniWM-specific; hides the island on other backends.
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$SELF_DIR/icon_map.sh" ] && . "$SELF_DIR/icon_map.sh" || __icon_map() { icon_result=":default:"; }

CACHE="$HOME/.cache/sketchybar"; LOCK="$CACHE/win.lock"; PENDING="$CACHE/win.pending"
mkdir -p "$CACHE"
MAXW="${WM_WIN_MAX:-3}"
FG="${COLOR_FG:-0xffcdd6f4}"; DIM="${COLOR_DIM:-0xff7f849c}"
ACC="${COLOR_ACCENT:-0xffcba6f7}"; ONACC="${COLOR_ON_ACCENT:-0xff1e1e2e}"
BG="${COLOR_BG:-0xee1e1e2e}"; FONT="${WM_BAR_FONT:-Menlo}"
APPFONT="sketchybar-app-font:Regular:12.0"

# ---- single-flight with coalescing ----
if [ -d "$LOCK" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
  [ "$age" -ge 8 ] && rmdir "$LOCK" 2>/dev/null
fi
if ! mkdir "$LOCK" 2>/dev/null; then : > "$PENDING"; exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

hide_all() {
  local i
  sketchybar --set win.lell drawing=off >/dev/null 2>&1
  for i in 0 1 2; do sketchybar --set "win.$i" drawing=off >/dev/null 2>&1; done
  sketchybar --set win.rell drawing=off >/dev/null 2>&1
  sketchybar --set window_group background.drawing=off >/dev/null 2>&1
}

render() {
  local backend
  backend="${WM_BACKEND:-$(wm status 2>/dev/null | awk '/^backend:/{print $2}')}"
  if [ "$backend" != "omniwm" ] || ! command -v omniwmctl >/dev/null 2>&1; then hide_all; return; fi

  local rows
  rows=$(omniwmctl query windows --format json 2>/dev/null | python3 -c "
import sys, json
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
d=d.get('result',{}).get('payload',d) if isinstance(d,dict) else d
ws=d if isinstance(d,list) else d.get('windows',[])
def wsname(w):
    x=w.get('workspace'); return x.get('rawName') if isinstance(x,dict) else x
cur=next((wsname(w) for w in ws if w.get('isFocused')),None)
if cur is None: sys.exit(0)
cw=[w for w in ws if wsname(w)==cur]
cw.sort(key=lambda w:(w.get('frame') or {}).get('x',0))
for w in cw:
    a=w.get('app') or {}; an=(a.get('name') if isinstance(a,dict) else a) or '?'
    t=(w.get('title') or '').replace('\t',' ').replace('\n',' ').strip()
    print('\t'.join([str(w.get('id','')),an,('1' if w.get('isFocused') else '0'),t]))
")

  local ids=() apps=() focs=() titles=() fidx=0 i=0
  while IFS=$'\t' read -r id app foc title; do
    [ -n "$id" ] || continue
    ids+=("$id"); apps+=("$app"); focs+=("$foc"); titles+=("$title")
    [ "$foc" = "1" ] && fidx=$i
    i=$((i+1))
  done <<< "$rows"

  local n="${#ids[@]}"
  if [ "$n" -eq 0 ]; then hide_all; return; fi

  # sliding window of up to MAXW around the focused index
  local start=0 end="$n"
  if [ "$n" -gt "$MAXW" ]; then
    start=$(( fidx - 1 )); [ "$start" -lt 0 ] && start=0
    local ms=$(( n - MAXW )); [ "$start" -gt "$ms" ] && start="$ms"
    end=$(( start + MAXW ))
  fi
  local left_more=0 right_more=0
  [ "$start" -gt 0 ] && left_more=1
  [ "$end" -lt "$n" ] && right_more=1

  sketchybar --set window_group background.drawing=on background.color="$BG" >/dev/null 2>&1
  [ "$left_more" = "1" ] && sketchybar --set win.lell drawing=on >/dev/null 2>&1 || sketchybar --set win.lell drawing=off >/dev/null 2>&1

  local k j slice=$(( end - start ))
  for k in 0 1 2; do
    j=$(( start + k ))
    if [ "$k" -lt "$slice" ] && [ "$j" -lt "$n" ]; then
      icon_result=":default:"; __icon_map "${apps[$j]}"
      case "${apps[$j]}" in cmux) icon_result=":terminal:" ;; Zen) icon_result=":firefox:" ;; esac
      if [ "${focs[$j]}" = "1" ]; then
        sketchybar --set "win.$k" drawing=on icon="$icon_result" icon.font="$APPFONT" icon.color="$ONACC" \
          label="${titles[$j]:-${apps[$j]}}" label.color="$ONACC" label.font="$FONT:${WM_BAR_FONT_BOLD:-Regular}:13.0" \
          background.drawing=on background.color="$ACC" \
          click_script="omniwmctl window focus ${ids[$j]}" >/dev/null 2>&1
      else
        sketchybar --set "win.$k" drawing=on icon="$icon_result" icon.font="$APPFONT" icon.color="$FG" \
          label="${titles[$j]:-${apps[$j]}}" label.color="$DIM" label.font="$FONT:Regular:13.0" \
          background.drawing=off \
          click_script="omniwmctl window focus ${ids[$j]}" >/dev/null 2>&1
      fi
    else
      sketchybar --set "win.$k" drawing=off >/dev/null 2>&1
    fi
  done

  [ "$right_more" = "1" ] && sketchybar --set win.rell drawing=on >/dev/null 2>&1 || sketchybar --set win.rell drawing=off >/dev/null 2>&1
}

while : ; do
  rm -f "$PENDING"
  render
  [ -f "$PENDING" ] || break
done
