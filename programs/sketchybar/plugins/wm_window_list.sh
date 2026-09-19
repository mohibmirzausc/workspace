#!/usr/bin/env bash
# Fill the pre-created "windows" island with the windows of the CURRENT OmniWM
# workspace: up to MAXW pills showing the window/session TITLE, focused
# highlighted,
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
# icon_map.sh is deliberately NOT sourced. Pills show the session name with
# icon.drawing=off, so __icon_map was never called -- the only two references
# to it were its own fallback definition and a comment saying it is unused.
# Sourcing it also cost a `cd ... && pwd` subshell whose `pwd` wrote "write
# error: Broken pipe" into the log whenever the script's stdout was already
# closed.

CACHE="$HOME/.cache/sketchybar"; LOCK="$CACHE/win.lock"; PENDING="$CACHE/win.pending"
mkdir -p "$CACHE"
# Slot count. sketchybarrc creates win.0..N-1 from this SAME variable with the
# same clamp, so the two cannot drift -- which they did when both hardcoded
# `0 1 2`: raising WM_WIN_MAX past the created slots silently dropped windows
# AND hid the overflow "..." (right_more is `end < n`, which came out false).
#
# The ceiling is a width limit, not an arbitrary one: past ~4 pills the island
# reaches the notch at 663pt on this panel. See the budget in sketchybarrc.
MAXW="${WM_WIN_MAX:-3}"
case "$MAXW" in (*[!0-9]*|'') MAXW=3 ;; esac
[ "$MAXW" -lt 1 ] && MAXW=1
[ "$MAXW" -gt 4 ] && MAXW=4

# How many win.N items the RUNNING bar actually has. Asked rather than
# assumed, because it can legitimately differ from MAXW -- sketchybarrc built
# them from whatever WM_WIN_MAX was set when the bar last loaded. Used only to
# bound the hide loops; `--set` on a missing item logs an error every render.
# Counted from a variable, not a pipe. `... | grep -c` makes grep stop
# reading once it has counted, so sketchybar gets SIGPIPE on the rest of its
# output and logs "write error: Broken pipe" -- 19 such lines in one session.
# Only fires when the write blocks (output > pipe buffer), which is why it
# looked intermittent.
_bar_q=$(sketchybar --query bar 2>/dev/null || true)
SLOTS=$(printf '%s' "$_bar_q" | grep -c '"win\.[0-9]*"' 2>/dev/null || echo "$MAXW")
unset _bar_q
case "$SLOTS" in (*[!0-9]*|''|0) SLOTS="$MAXW" ;; esac
# No FG here: pills are either focused (ONACC on an ACC background) or
# unfocused (DIM), so the normal foreground colour is never used. Nor
# APPFONT -- the app-icon glyph was dropped when the pill started showing
# the session name, so the pills set icon.drawing=off and the label font
# comes from sketchybarrc's --default.
DIM="${COLOR_DIM:-0xff7f849c}"
ACC="${COLOR_ACCENT:-0xffcba6f7}"; ONACC="${COLOR_ON_ACCENT:-0xff1e1e2e}"
BG="${COLOR_BG:-0xee1e1e2e}"; FONT="${WM_BAR_FONT:-Menlo}"
# Built from helpers/window-titles.swift by a home-manager activation script.
CGTITLES="${CGTITLES_BIN:-$HOME/.config/sketchybar/helpers/window-titles}"

# ---- single-flight with coalescing ----
# Clear anything at $LOCK that is not a live lock. Tested against -e AND -L so
# a dangling symlink is handled too: with only `[ -d ]`, a symlink there made
# the staleness check skip, mkdir fail, and the script exit 0 forever.
if [ -e "$LOCK" ] || [ -L "$LOCK" ]; then
  if [ ! -d "$LOCK" ]; then
    rm -f "$LOCK" 2>/dev/null
  else
    # Validate numeric before arithmetic. `stat` failing (or being GNU stat,
    # which prints a filesystem dump for -f) otherwise feeds a word into
    # $(( )), which `set -u` turns into "File: unbound variable" and aborts
    # the script BEFORE the trap below is installed -- leaking the very lock
    # this block exists to reap. That deadlocked the island in production.
    lmt=$(/usr/bin/stat -f %m "$LOCK" 2>/dev/null)
    case "$lmt" in (*[!0-9]*|'') lmt=0 ;; esac
    age=$(( $(date +%s) - lmt ))
    [ "$age" -ge 8 ] && rmdir "$LOCK" 2>/dev/null
  fi
fi
if ! mkdir "$LOCK" 2>/dev/null; then : > "$PENDING"; exit 0; fi
# Cover the signals that actually happen: launchd sends SIGTERM on every
# rebuild/restart, which EXIT alone does not catch, leaking the lock.
# (SIGKILL cannot be trapped -- the staleness check above is the net for that.)
trap 'rmdir "$LOCK" 2>/dev/null; rm -f "$CACHE/win_parse.py.$$" 2>/dev/null' EXIT INT TERM HUP

# Batched for the same reason as render(): one process instead of SLOTS+3.
hide_all() {
  local -a args=(--set win.lell drawing=off)
  local i=0
  while [ "$i" -lt "$SLOTS" ]; do
    args+=(--set "win.$i" drawing=off)
    i=$((i+1))
  done
  args+=(--set win.rell drawing=off)
  args+=(--set window_group background.drawing=off)
  sketchybar "${args[@]}" >/dev/null 2>&1
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
  # Written to a temp file and mv'd into place, never `cat >` directly:
  # `cat >` truncates in place, so a concurrent run reading the file mid-write
  # gets a partial script and dies with SyntaxError (observed in the log).
  # The lock normally prevents overlap, but the 8s stale-lock breaker above
  # can admit a second instance while the first is still writing. mv within
  # the same filesystem is atomic, so a reader sees either the old complete
  # file or the new one.
  local pyf tmpf; pyf="$CACHE/win_parse.py"; tmpf="$pyf.$$"
  cat > "$tmpf" <<'PY'
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
#
# Tiebreak on (x, y, id), not x alone. Stacked windows legitimately share an
# x -- three of five on workspace 1 here all report x=1511 -- and Python's
# sort is stable, so ties fell back to OmniWM's array order, which is not
# positional and can vary between queries. That made the pill order (and
# which side shows the overflow "...") flip between renders with nothing
# having moved. id is the final key purely to make the order total.
cur = next((wsname(w) for w in ws if w.get('isFocused')), None)
if cur is None:
    sys.exit(0)

# Workspace membership is NOT enough: a window sent to a scratchpad keeps the
# workspace it came from, so it kept appearing as a pill for a window that is
# not on screen. OmniWM reports these as
#   isScratchpad=true, isVisible=false, hiddenReason="scratchpad"
#
# Filter on isVisible rather than isScratchpad -- it is the more general
# property and covers every not-on-screen case with one test. Observed
# hiddenReason values across all windows here: "scratchpad" (2),
# "workspace-inactive" (4), None (3), and isVisible=false lines up exactly
# with the first two.
#
# `is not False` rather than a truthiness check on purpose: if a future
# OmniWM omits the field, absent should mean "show it" rather than silently
# emptying the island.
cw = [w for w in ws
      if wsname(w) == cur and w.get('isVisible') is not False]

# Never let the filter empty the island out from under the focused window.
# If focus is on something the visibility test rejected -- e.g. a scratchpad
# toggled open, if OmniWM ever reports one as isVisible=false while focused --
# fall back to showing it, since a pill for the window you are typing in is
# strictly more useful than an empty island. Could not reproduce that state
# via `omniwmctl command toggle-scratchpad` here, so this is a guard rather
# than a fix for an observed bug.
if not any(w.get('isFocused') for w in cw):
    focused = [w for w in ws if w.get('isFocused')]
    if focused:
        cw = focused
def pos(w):
    f = w.get('frame') or {}
    return (f.get('x', 0), f.get('y', 0), str(w.get('id', '')))
cw.sort(key=pos)

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
  mv -f "$tmpf" "$pyf" 2>/dev/null || { rm -f "$tmpf"; return; }

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

  # ONE sketchybar invocation for the whole render. Each `sketchybar --set`
  # is a separate ~85ms process, and a render touches 6-8 items, so doing
  # them one at a time cost ~300ms of pure process spawn. Batching the same
  # six updates measured 305ms -> 75ms. args[] accumulates and is flushed
  # once at the end of this function.
  local -a args=()
  args+=(--set window_group background.drawing=on background.color="$BG")
  if [ "$left_more" = "1" ]; then
    args+=(--set win.lell drawing=on)
  else
    args+=(--set win.lell drawing=off)
  fi

  local j slice=$(( end - start ))
  local k=0
  while [ "$k" -lt "$MAXW" ]; do
    j=$(( start + k ))
    if [ "$k" -lt "$slice" ] && [ "$j" -lt "$n" ]; then
      # No icon lookup: pills set icon.drawing=off and show the session
      # name, so the sketchybar-app-font ligature map is not consulted.
      # The SESSION/window title alone -- no "App - " prefix. The title is
      # what distinguishes one window from another; the app name is the same
      # across every cmux pill and just eats characters.
      #
      # Falls back to the app name only when there is no usable title at all:
      # clean() returns empty for titles that merely echo the app ("Slack")
      # or are placeholders ("Terminal"), and a blank pill would be worse
      # than a redundant one.
      pill="${titles[$j]:-${apps[$j]}}"
      if [ "${focs[$j]}" = "1" ]; then
        args+=(--set "win.$k" drawing=on icon.drawing=off
          label="$pill" label.color="$ONACC" label.font="$FONT:${WM_BAR_FONT_BOLD:-Regular}:13.0"
          background.drawing=on background.color="$ACC"
          click_script="omniwmctl window focus ${ids[$j]}")
      else
        args+=(--set "win.$k" drawing=on icon.drawing=off
          label="$pill" label.color="$DIM" label.font="$FONT:Regular:13.0"
          background.drawing=off
          click_script="omniwmctl window focus ${ids[$j]}")
      fi
    else
      args+=(--set "win.$k" drawing=off)
    fi
    k=$((k+1))
  done

  # Hide any slot ABOVE the current MAXW. sketchybarrc creates win.0..MAXW-1
  # from the same variable, so normally there are none -- but a plugin run
  # with a smaller WM_WIN_MAX than the bar was loaded with (a hand-run, or an
  # agent env edited without restarting sketchybar) would otherwise leave the
  # extra pills drawn with stale contents.
  #
  # Bounded by the items that ACTUALLY EXIST, not by the clamp ceiling:
  # `--set` on a missing item is NOT a silent no-op, it logs
  # "Set: Item not found 'win.N'" on every render. $SLOTS is discovered once
  # from the bar itself rather than assumed.
  while [ "$k" -lt "$SLOTS" ]; do
    args+=(--set "win.$k" drawing=off)
    k=$((k+1))
  done

  if [ "$right_more" = "1" ]; then
    args+=(--set win.rell drawing=on)
  else
    args+=(--set win.rell drawing=off)
  fi

  sketchybar "${args[@]}" >/dev/null 2>&1
}

while : ; do
  rm -f "$PENDING"
  render
  [ -f "$PENDING" ] || break
done
