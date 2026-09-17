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
# cmux is a cask, so it is not on the launchd agent's PATH.
CMUX="${CMUX_BIN:-/Applications/cmux.app/Contents/Resources/bin/cmux}"

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
  # cmux windows title themselves with the AGENT'S LAST OUTPUT LINE, so
  # OmniWM reports things like "** WARNING:** Superpowers now uses..." for a
  # window whose actual identity is the tab name ("hyper key omni"). Ask cmux
  # for its own tree and build a title -> tab-name map, keyed on the window
  # title, which is the only field the two tools share (cmux does not expose
  # an OS window id).
  local cmuxmap="$CACHE/cmux_tabs.json"
  : > "$cmuxmap"
  if [ -x "$CMUX" ]; then
    "$CMUX" tree --all --json 2>/dev/null > "$CACHE/cmux_tree.json" || : > "$CACHE/cmux_tree.json"
  fi

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

# ---- cmux tab names -------------------------------------------------------
# cmux titles its OS windows with the agent's latest output line, which is
# useless in a 28-char pill. Its own tree exposes the WORKSPACE title (the tab
# name the user set: "hyper key omni", "runtimes bakeoff") and the surface
# title. Map raw-title -> tab-name; the window title is the only field cmux
# and OmniWM share, since cmux exposes no OS window id.
CMUX_TABS = {}

def _surfaces(node, out):
    if isinstance(node, dict):
        for sf in node.get('surfaces') or []:
            out.append(sf)
        for k in ('panes', 'layout', 'pane', 'children'):
            v = node.get(k)
            if isinstance(v, list):
                for i in v:
                    _surfaces(i, out)
            elif v:
                _surfaces(v, out)
    return out

_JUNK = re.compile(r'\*\*|^[^\w(\[]')

def _strip(t):
    t = re.sub(r'\*\*|`', '', t or '')
    return re.sub(r'^[^\w(\[]+', '', t).strip()

try:
    with open(os.environ['CMUX_TREE'], 'r') as fh:
        ct = json.load(fh)
    for w in ct.get('windows') or []:
        for x in w.get('workspaces') or []:
            if x.get('id') != w.get('selected_workspace_id'):
                continue
            tab = (x.get('title') or '').strip()
            out = []
            for pane in x.get('panes') or []:
                _surfaces(pane, out)
            sel = [sf.get('title') for sf in out if sf.get('selected')] \
                  or [sf.get('title') for sf in out]
            surf = (sel[0] if sel else '') or ''
            # Prefer the tab name the user chose; fall back to the surface
            # title when the tab name is itself agent output.
            pick = tab
            if not pick or _JUNK.search(pick):
                pick = _strip(surf) or pick
            pick = _strip(pick)
            if tab and pick:
                CMUX_TABS[tab] = pick
except Exception:
    pass
d = d.get('result', {}).get('payload', d) if isinstance(d, dict) else d
ws = d if isinstance(d, list) else d.get('windows', [])

def wsname(w):
    x = w.get('workspace')
    return x.get('rawName') if isinstance(x, dict) else x

cur = next((wsname(w) for w in ws if w.get('isFocused')), None)
if cur is None:
    sys.exit(0)
cw = [w for w in ws if wsname(w) == cur]
cw.sort(key=lambda w: (w.get('frame') or {}).get('x', 0))

# Raw window titles are often not worth their width: Slack/Calendar just
# repeat the app name, cmux reports the literal "Terminal", agent panes leak
# markdown and emoji, and many apps append their own name as a suffix.
APP_SUFFIX_SEPS = (' - ', '\u2014', '\u2013', ' | ')
PLACEHOLDERS = ('terminal', 'window', 'untitled')

def clean(title, app):
    t = (title or '').replace('\t', ' ').replace('\n', ' ').strip()
    # cmux: swap the agent-output title for the tab name.
    if app == 'cmux':
        mapped = CMUX_TABS.get(t) or CMUX_TABS.get(title or '')
        if mapped:
            return mapped
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
    t = clean(w.get('title'), an)
    print('\t'.join([str(w.get('id', '')), an,
                     ('1' if w.get('isFocused') else '0'), t]))
PY
  rows=$(omniwmctl query windows --format json 2>/dev/null \
    | CMUX_TREE="$CACHE/cmux_tree.json" python3 "$pyf")

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
