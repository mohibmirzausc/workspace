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
# Built from helpers/window-titles.swift by a home-manager activation script.
CGTITLES="${CGTITLES_BIN:-$HOME/.config/sketchybar/helpers/window-titles}"

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
  # OmniWM serves a STALE window title. Renaming a cmux tab (or any app's
  # window) updates the real title immediately, but `omniwmctl query windows`
  # keeps returning the old one -- so a renamed session kept showing its old
  # agent-output title on the bar.
  #
  # The CoreGraphics helper prints the LIVE title per window, keyed by
  # kCGWindowNumber, which is the same id as OmniWM's windowId. That is a
  # stable join: matching on the title itself cannot work, since a rename
  # changes it by definition and several cmux windows share one title.
  #
  # Earlier approach (asking cmux for its own tree) is gone: cmux exposes no
  # OS window id, its `key`/`active` flags point at the window the CLI was
  # invoked from rather than the focused one, and its window order does not
  # line up with OmniWM's.
  local titlemap="$CACHE/cg_titles.tsv"
  : > "$titlemap"
  [ -x "$CGTITLES" ] && "$CGTITLES" > "$titlemap" 2>/dev/null

  # The python is written to a temp file and run as `python3 FILE`, rather
  # than `python3 -c "..."` or a heredoc. Both alternatives are broken here:
  #   -c "..."   bash expands $, backticks and backslashes inside a
  #              double-quoted string, mangling regex escapes (\w, \u2014)
  #              before python sees them.
  #   <<'PY'     a heredoc BECOMES stdin, so the piped omniwmctl JSON never
  #              arrives and json.load reads the script text instead.
  # A quoted heredoc into a temp file keeps the text verbatim AND leaves
  # stdin free for the pipe.
  local pyf; pyf="$CACHE/win_parse.py"
  cat > "$pyf" <<'PY'
import sys, json, re, os

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
d = d.get('result', {}).get('payload', d) if isinstance(d, dict) else d
ws = d if isinstance(d, list) else d.get('windows', [])

def wsname(w):
    x = w.get('workspace')
    return x.get('rawName') if isinstance(x, dict) else x

# Only the CURRENT workspace's windows, left-to-right by frame position.
cur = next((wsname(w) for w in ws if w.get('isFocused')), None)
if cur is None:
    sys.exit(0)
cw = [w for w in ws if wsname(w) == cur]
cw.sort(key=lambda w: (w.get('frame') or {}).get('x', 0))

# ---- live window titles ---------------------------------------------------
# windowId -> current title, from CoreGraphics (see the helper note above).
# OmniWM's own title field goes stale on rename, so this wins when present.
LIVE = {}
try:
    with open(os.environ['CG_TITLES'], 'r') as fh:
        for line in fh:
            num, _, name = line.rstrip('\n').partition('\t')
            if num.isdigit() and name:
                LIVE[int(num)] = name
except Exception:
    pass

# Raw window titles are often not worth their width: Slack/Calendar just
# repeat the app name, cmux reports the literal "Terminal", agent panes leak
# markdown and emoji, and many apps append their own name as a suffix.
APP_SUFFIX_SEPS = (' - ', '\u2014', '\u2013', ' | ')
PLACEHOLDERS = ('terminal', 'window', 'untitled')

def clean(title, app):
    t = (title or '').replace('\t', ' ').replace('\n', ' ').strip()
    for sep in APP_SUFFIX_SEPS:
        if sep in t:
            head, _, tail = t.rpartition(sep)
            if head and tail.strip().lower().startswith(app.strip().lower()[:6]):
                t = head.strip()
    t = re.sub(r'\*\*|`|^#+\s*', '', t)
    # Leading emoji/symbol runs render as tofu and eat the first characters.
    t = re.sub(r'^[^\w(\[]+', '', t).strip()
    low = t.strip().lower()
    if not t or low == app.strip().lower() or low in PLACEHOLDERS:
        return ''
    return t

for w in cw:
    a = w.get('app') or {}
    an = (a.get('name') if isinstance(a, dict) else a) or '?'
    raw = LIVE.get(w.get('windowId')) or w.get('title')
    t = clean(raw, an)
    print('\t'.join([str(w.get('id', '')), an,
                     ('1' if w.get('isFocused') else '0'), t]))
PY
  rows=$(omniwmctl query windows --format json 2>/dev/null \
    | CG_TITLES="$titlemap" python3 "$pyf")

  local ids=() apps=() focs=() titles=() fidx=0 i=0
  while IFS=$'\t' read -r id app foc title; do
    [ -n "$id" ] || continue
    ids+=("$id"); apps+=("$app"); focs+=("$foc"); titles+=("$title")
    [ "$foc" = "1" ] && fidx=$i
    i=$((i+1))
  done <<< "$rows"

  local n="${#ids[@]}"
  if [ "$n" -eq 0 ]; then hide_all; return; fi

  # Sliding window of up to MAXW items that ALWAYS contains the focused index.
  #
  # The old math was `start = fidx - 1` (one item of left context). That is
  # off-by-one at MAXW=1: with 5 windows and the focused one at index 2 it
  # yielded start=1, end=2 -- rendering the window BEFORE the focused one and
  # excluding the focused window entirely. Symptom was the pill showing
  # "Google Chrome" while cmux was clearly focused.
  #
  # Centre the window on fidx instead, then clamp into range. At MAXW=1 this
  # degenerates to exactly [fidx, fidx+1), which is what "show the focused
  # window" should mean.
  local start=0 end="$n"
  if [ "$n" -gt "$MAXW" ]; then
    start=$(( fidx - (MAXW - 1) / 2 ))
    [ "$start" -lt 0 ] && start=0
    local ms=$(( n - MAXW ))
    [ "$start" -gt "$ms" ] && start="$ms"
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
      # "App - Title", or just "App" when the title added nothing (clean()
      # returns empty for titles that echo the app name or are placeholders
      # like "Terminal"). The app name goes in the LABEL rather than relying
      # on the icon: the sketchybar-app-font ligature is a PUA glyph and
      # those render as literal text in this setup, so an icon-only pill
      # would be unidentifiable.
      pill="${apps[$j]}"
      [ -n "${titles[$j]}" ] && pill="${apps[$j]} - ${titles[$j]}"
      if [ "${focs[$j]}" = "1" ]; then
        sketchybar --set "win.$k" drawing=on icon.drawing=off \
          label="$pill" label.color="$ONACC" label.font="$FONT:${WM_BAR_FONT_BOLD:-Regular}:13.0" \
          background.drawing=on background.color="$ACC" \
          click_script="omniwmctl window focus ${ids[$j]}" >/dev/null 2>&1
      else
        sketchybar --set "win.$k" drawing=on icon.drawing=off \
          label="$pill" label.color="$DIM" label.font="$FONT:Regular:13.0" \
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
