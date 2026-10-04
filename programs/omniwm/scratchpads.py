#!/usr/bin/env python3
"""Keep OmniWM's scratchpad slots across an OmniWM restart.

Caps+Shift+S/T/E/C put the focused window in scratchpad slot 1-4 and
Caps+S/T/E/C toggle the slot. Which window is in which slot is chosen by
hand (one "master" Chrome window on C, never the other Chrome windows), so
no app rule can rebuild it. OmniWM 0.7.4 keeps the slots only in memory
([scratchpads] in settings.toml holds labels, nothing else), so every
OmniWM quit, crash or upgrade empties them. The windows outlive OmniWM; the
slots do not. This puts them back.

  daemon   launchd agent. Saves the slots to STATE_FILE whenever they change
           and, when it sees a new OmniWM, assigns each saved window back to
           its slot, then puts focus and every display's workspace back.
  status   print the saved slots, the live ones, and what a restore would do.
  restore  restore the saved slots now (idempotent: a window already in its
           slot is left alone).

WHICH WINDOW IS WHICH. OmniWM's window id (ow_<base64>) is base64url of
"<session token>:<app pid>:<window id>" (IPCWindowOpaqueID in OmniWMIPC/
IPCWindowModels.swift). The session token is a fresh UUID per OmniWM launch
(IPCServer.init), so the id itself goes stale on a restart, but the other
two halves do not: the pid is the app's, and the window id is the
WindowServer's CGWindowID (kCGWindowNumber; checked against
CGWindowListCopyWindowInfo), which lives as long as the window. OmniWM keys
its own restart restore catalog the same way: pid + windowId + bundleId
(PersistedWindowRestoreIdentity). So the key is

  1. bundle id + pid + window id. Exact. A pid reused by another app fails
     the bundle check.
  2. bundle id + title, ONLY if the app process that had the saved pid is
     gone (the app itself restarted, e.g. after a reboot; a pid reused by
     another process is told apart by the app's saved start time), only once
     the app has been up APP_SETTLE seconds (so all its windows have come
     back and stopped loading), and only if exactly one window of that app,
     in a slot or not, has that title. Two Chrome windows called "New Tab"
     are skipped and logged, never guessed. If the saved process is still
     running, a missing window was closed: no fallback.

Apps without a bundle id (Minecraft's "java") use "name:<app name>".

WHEN TO SAVE, AND WHEN NOT TO. OmniWM's lifetime is its pid plus start time
(as in triage's inventory.omniwm_instance). Within one lifetime the live slots
are the truth, so a slot the user empties is saved empty. Across lifetimes
the file is the truth until the restore has run: nothing is written for a new
OmniWM before that, and nothing at all while OmniWM is unreachable or
answering protocol_mismatch (an upgrade under a running app), nor from an
empty window list. A saved window that vanishes from OmniWM's list is kept
for VANISH_GRACE seconds before it is dropped (an unassign: UNASSIGN_GRACE),
so the last answers of an OmniWM that is quitting cannot wipe the file.
Windows not found at restore stay "pending" for PENDING_GRACE seconds (apps
reopen their windows slowly after a reboot), then are dropped and logged. A
slot the user fills by hand after a restart (even before the restore runs)
is theirs: whatever is still pending for it is dropped.

HOW A RESTORE ASSIGNS. There is no IPC call that assigns a given window, only
`command scratchpad assign <n>`, which acts on the focused window. And assign
TOGGLES: a window already in slot n is released from it (WMController+
ScratchpadCommands.assignWindowToScratchpad). So for each window: re-read the
live state, skip it if it is in any slot already (a slot the user filled since
the restart wins), `window focus` it, wait until OmniWM reports it focused,
re-read once more and re-check the focus, assign, and check the result.
Slots hold several windows (ScratchpadState.membersBySlot), so assigning
never evicts another member. An assigned window is hidden unless its slot is
the one showing, as with the hotkey. If the user's click or hotkey moved the
focus in the last instant and the assign hit another window, the restore
stops: a window wrongly put in the slot is kept out of the file, and a member
wrongly toggled out is queued to go back. Afterwards each display gets its
workspace back and the window that had focus is refocused (unless it is now
hidden in a scratchpad: focusing it would reveal the slot), but only if the
user didn't switch workspace or focus during the restore themselves.
"""

import base64
import calendar
import fcntl
import json
import os
import select
import shutil
import signal
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
STATE_FILE = os.environ.get("OMNIWM_SCRATCHPADS_STATE") or os.path.join(
    HOME, ".local", "state", "omniwm-scratchpads.json")
VERSION = 1

# Debounce, as in programs/cmux/attention.py: refresh QUIET after the last
# event of a burst, never later than MAX_WAIT after the first.
QUIET, MAX_WAIT = 1.5, 10.0
# Safety refresh when no event arrives (and the only refresh while the event
# stream is down, e.g. during a protocol_mismatch).
SAFETY = 30.0
# A new OmniWM must have been up this long before a restore: it admits the
# existing windows over its first seconds.
SETTLE = 8.0
# The title fallback waits until the matched app has been up this long, so
# a reopening app has brought back every window before one is picked.
APP_SETTLE = 20.0
VANISH_GRACE = 10.0
PENDING_GRACE = 30 * 60.0
FOCUS_TIMEOUT = 2.0
RETRY_AFTER = 30.0
MAX_ATTEMPTS = 3
SLOW_RETRY = 5 * 60.0
UNASSIGN_GRACE = 3.0
FIELDS = "id,pid,window-id,app,title,workspace,scratchpad-index,is-visible"


def find(name, fallback):
    return os.environ.get(name.upper().replace("-", "_") + "_BIN") or shutil.which(name) or fallback


OMNIWMCTL = find("omniwmctl", "/opt/homebrew/bin/omniwmctl")


def log(*parts):
    print(time.strftime("%H:%M:%S"), "omniwm-scratchpads:", *parts, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# omniwmctl
# ---------------------------------------------------------------------------

class Unavailable(Exception):
    """OmniWM can't be asked right now. mismatch is the version payload when
    omniwmctl and the running app disagree on protocol (brew upgraded the cask
    under a running app; omniwmctl is a symlink into the new .app), else None."""

    def __init__(self, why, mismatch=None):
        super().__init__(why)
        self.mismatch = mismatch


class Rejected(Exception):
    """OmniWM answered, but refused the request (not_found, stale_window_id...)."""

    def __init__(self, code):
        super().__init__(code)
        self.code = code


def run_ctl(args, timeout=5.0):
    """(exit code, stdout) of omniwmctl. Replaced by the tests."""
    out = subprocess.run([OMNIWMCTL, *args], capture_output=True, text=True,
                         timeout=timeout, stdin=subprocess.DEVNULL)
    return out.returncode, out.stdout


def ctl(*args, timeout=5.0):
    """The payload of a successful omniwmctl call.

    Raises Unavailable when OmniWM can't be reached or speaks another
    protocol, Rejected when it answered no."""
    try:
        code, out = run_ctl([*args, "--json"], timeout)
    except (OSError, subprocess.SubprocessError) as exc:
        raise Unavailable(f"omniwmctl failed: {exc}")
    try:
        doc = json.loads(out)
    except ValueError:
        doc = None
    if not isinstance(doc, dict):
        if "protocol_mismatch" in (out or ""):
            raise Unavailable("protocol_mismatch", mismatch={})
        raise Unavailable(f"omniwmctl exited {code} without JSON")
    if doc.get("code") == "protocol_mismatch":
        result = doc.get("result")
        payload = result.get("payload") if isinstance(result, dict) else None
        raise Unavailable("protocol_mismatch", mismatch=payload if isinstance(payload, dict) else {})
    if doc.get("source") == "cli":
        # omniwmctl's own failure: transport_failure (no socket, OmniWM not
        # running or IPC off), invalid_arguments, internal_error.
        raise Unavailable(f"omniwmctl: {doc.get('code')}")
    if not doc.get("ok"):
        raise Rejected(str(doc.get("code")))
    result = doc.get("result")
    payload = result.get("payload") if isinstance(result, dict) else None
    return payload if isinstance(payload, dict) else {}


def decode_id(oid):
    """(pid, window id) from an ow_ id, or None."""
    if not isinstance(oid, str) or not oid.startswith("ow_"):
        return None
    raw = oid[3:]
    try:
        text = base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)).decode()
        _, pid, wid = text.rsplit(":", 2)
        return int(pid), int(wid)
    except (ValueError, UnicodeDecodeError):
        return None


def norm_window(w):
    app = w.get("app") if isinstance(w.get("app"), dict) else {}
    ws = w.get("workspace") if isinstance(w.get("workspace"), dict) else {}
    pid, wid = w.get("pid"), w.get("windowId")
    if not (type(pid) is int and type(wid) is int):
        ids = decode_id(w.get("id"))
        if ids is None:
            return None
        pid, wid = ids
    slot = w.get("scratchpadIndex")
    return {"id": w.get("id"), "pid": pid, "windowId": wid,
            "bundleId": app.get("bundleId") or None, "app": app.get("name") or None,
            "title": w.get("title") if isinstance(w.get("title"), str) else "",
            "slot": slot if type(slot) is int else None,
            "workspace": ws.get("number"), "visible": w.get("isVisible") is True}


def windows():
    got = ctl("query", "windows", "--fields", FIELDS).get("windows")
    if not isinstance(got, list):
        raise Unavailable("query windows: no window list")
    return [n for n in (norm_window(w) for w in got if isinstance(w, dict)) if n]


def focused():
    """(pid, window id) of the focused managed window, or None."""
    w = ctl("query", "focused-window").get("window")
    if not isinstance(w, dict):
        return None
    if type(w.get("pid")) is int and decode_id(w.get("id")):
        return decode_id(w.get("id"))
    return None


def displays():
    """[(display id, workspace number, is current)] in OmniWM's order."""
    out = []
    for d in ctl("query", "displays").get("displays") or []:
        if not isinstance(d, dict):
            continue
        ws = d.get("activeWorkspace") if isinstance(d.get("activeWorkspace"), dict) else {}
        if isinstance(d.get("id"), str) and type(ws.get("number")) is int:
            out.append((d["id"], ws["number"], d.get("isCurrent") is True))
    return out


# ---------------------------------------------------------------------------
# OmniWM's lifetime, and other processes
# ---------------------------------------------------------------------------

def _ps_env():
    # lstart prints local time: pinned to UTC so a timezone change doesn't
    # read as a restart; C for its format.
    return dict(os.environ, LC_ALL="C", LANG="C", TZ="UTC0")


def started_at(pid):
    """Start time of pid as (lstart text, epoch seconds), or None."""
    try:
        text = subprocess.run(["/bin/ps", "-o", "lstart=", "-p", str(pid)], capture_output=True,
                              text=True, env=_ps_env(), timeout=5).stdout.strip()
        return text, calendar.timegm(time.strptime(text, "%a %b %d %H:%M:%S %Y"))
    except (OSError, ValueError, OverflowError, subprocess.SubprocessError):
        return None


def omniwm_instance():
    """This user's OmniWM as {"pid", "started", "epoch"}, or None when there
    isn't exactly one (or ps can't say)."""
    try:
        pids = subprocess.run(["/usr/bin/pgrep", "-x", "-U", str(os.getuid()), "OmniWM"],
                              capture_output=True, text=True, env=_ps_env(), timeout=5).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return None
    if len(pids) != 1 or not pids[0].isdigit():
        return None
    s = started_at(int(pids[0]))
    return {"pid": int(pids[0]), "started": s[0], "epoch": s[1]} if s else None


def same_instance(a, b):
    return bool(a and b) and a.get("pid") == b.get("pid") and a.get("started") == b.get("started")


def pid_alive(pid, started=None):
    """Is the process that had pid still running? With its start time, a
    reused pid (likely after a reboot) reads as not running."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except (OSError, OverflowError, ValueError):
        pass  # EPERM: it exists
    if type(started) not in (int, float):
        return True
    s = started_at(pid)
    # ps prints whole seconds
    return s is None or abs(s[1] - started) <= 2


def app_age(pid, now):
    s = started_at(pid)
    return None if s is None else now - s[1]


# ---------------------------------------------------------------------------
# Pure pieces (tested in test_scratchpads.py)
# ---------------------------------------------------------------------------

def app_key(w):
    if w.get("bundleId"):
        return w["bundleId"]
    return "name:" + w["app"] if w.get("app") else None


def key(w):
    return (w["pid"], w["windowId"])


ENTRY_KEYS = ("pid", "windowId", "bundleId", "app", "title", "appStarted")


def entry_of(w, app_started=None):
    e = {"pid": w["pid"], "windowId": w["windowId"], "bundleId": w.get("bundleId"),
         "app": w.get("app"), "title": w.get("title") or ""}
    if app_started is not None:
        e["appStarted"] = app_started
    return e


def describe(e):
    return f"{e.get('app') or e.get('bundleId') or '?'} {e.get('title')!r} (pid {e.get('pid')}, window {e.get('windowId')})"


def live_slots(wins, app_started=lambda pid: None, skip=()):
    """{"n": [entry, ...]} from a window list, members in window-id order.
    skip: window keys left out (a stray a stopped restore put in a slot)."""
    out = {}
    for w in sorted(wins, key=key):
        if w["slot"] is not None and key(w) not in skip:
            out.setdefault(str(w["slot"]), []).append(entry_of(w, app_started(w["pid"])))
    return out


def match(e, wins, alive, age):
    """Find saved entry e among the live windows.

    Returns (outcome, window, why): ("found", w, how) or ("missing", None,
    why), ("ambiguous", None, why), ("wait", None, why). alive(pid, started) says if
    the process that had pid (started at epoch `started`, if known) still
    runs; age(pid) is how long the process now at pid has run, or None."""
    ak = app_key(e)
    for w in wins:
        if key(w) == (e.get("pid"), e.get("windowId")) and app_key(w) == ak:
            return "found", w, "same window"
    if ak is None:
        return "missing", None, "not found, and it has no app to match by"
    if type(e.get("pid")) is int and alive(e["pid"], e.get("appStarted")):
        return "missing", None, "not found while its app is still running: closed"
    title = e.get("title") or ""
    if not title:
        return "missing", None, "its app restarted and it has no title to match by"
    cands = [w for w in wins if app_key(w) == ak and w.get("title") == title]
    if not cands:
        return "missing", None, "its app restarted and no window has its title"
    # Judged only once the app has settled: windows that are still loading
    # can share a title for a moment.
    ages = [age(w["pid"]) for w in cands]
    if any(a is None or a < APP_SETTLE for a in ages):
        return "wait", None, "its app restarted moments ago; waiting for all its windows"
    if len(cands) > 1:
        return "ambiguous", None, f"its app restarted and {len(cands)} of its windows are titled {title!r}"
    return "found", cands[0], "same app and title (the app restarted)"


def plan(entries, wins, alive, age):
    """What a restore does for each (slot, entry) pair.

    Returns [(slot, entry, outcome, window, why)] where outcome is one of
      in-place  the window is in this slot already
      taken     it is in another slot (put there since the restart: it wins)
      assign    found, in no slot: assign it
      missing / ambiguous / wait   from match()
    Two entries landing on one window (two saved slots, or a title that
    fits two saved windows) are both ambiguous: no guessing."""
    rows = []
    for slot, e in entries:
        outcome, w, why = match(e, wins, alive, age)
        if outcome == "found":
            if w["slot"] == slot:
                outcome = "in-place"
            elif w["slot"] is not None:
                outcome, why = "taken", f"it is in slot {w['slot']} now"
            else:
                outcome = "assign"
        rows.append([slot, e, outcome, w, why])
    claims = {}
    for r in rows:
        if r[3] is not None:
            claims.setdefault(key(r[3]), []).append(r)
    for rs in claims.values():
        if len({r[0] for r in rs}) > 1:
            for r in rs:
                if r[2] == "assign":
                    r[2], r[3], r[4] = "ambiguous", None, "two saved slots point at this window"
        else:
            for r in rs[1:]:  # the same window saved twice in one slot
                r[2] = "in-place" if rs[0][2] == "in-place" else "duplicate"
    return [tuple(r) for r in rows]


def entries_of(slots):
    """[(slot int, entry)] from {"n": [entry]}, slot order."""
    out = []
    for s, es in sorted((slots or {}).items(), key=lambda kv: int(kv[0]) if str(kv[0]).isdigit() else 0):
        if not str(s).isdigit() or not isinstance(es, list):
            continue
        for e in es:
            if isinstance(e, dict) and type(e.get("pid")) is int and type(e.get("windowId")) is int:
                out.append((int(s), e))
    return out


class Debounce:
    """Trailing-edge debounce with a cap and a safety refresh, as in
    programs/cmux/attention.py. wake_at() asks for an earlier refresh (a new
    OmniWM settling, a pending retry coming due)."""

    def __init__(self, now):
        self.first = self.last = None
        self.safety = now

    def event(self, now):
        self.last = now
        if self.first is None:
            self.first = now

    def wake_at(self, when):
        self.safety = min(self.safety, when)

    def deadline(self):
        if self.first is None:
            return self.safety
        return min(self.safety, self.last + QUIET, self.first + MAX_WAIT)

    def due(self, now):
        return now >= self.deadline()

    def done(self, now):
        self.first = self.last = None
        self.safety = now + SAFETY


# ---------------------------------------------------------------------------
# State file
# ---------------------------------------------------------------------------

def load_state(path=None):
    """The state file, {} if there is none. Raises OSError if it can't be
    read; a corrupt one is moved aside (kept for a look) and reads as {}."""
    path = path or STATE_FILE
    try:
        with open(path) as f:
            doc = json.load(f)
    except FileNotFoundError:
        return {}
    except ValueError as exc:
        aside = f"{path}.corrupt-{int(time.time())}"
        try:
            os.replace(path, aside)
            log(f"{path} is not JSON ({exc}); moved it to {aside}")
        except OSError:
            pass
        return {}
    return doc if isinstance(doc, dict) else {}


def write_state(doc, path=None):
    path = path or STATE_FILE
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(doc, f, indent=2, sort_keys=True)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


class Lock:
    """One restorer at a time: the daemon and a hand-run `restore`."""

    def __init__(self, path=None):
        self.path = (path or STATE_FILE) + ".lock"
        self.fd = None

    def __enter__(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self.fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o644)
        try:
            fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(self.fd)
            self.fd = None
            return False
        return True

    def __exit__(self, *_):
        if self.fd is not None:
            fcntl.flock(self.fd, fcntl.LOCK_UN)
            os.close(self.fd)
            self.fd = None


# ---------------------------------------------------------------------------
# Restore
# ---------------------------------------------------------------------------

class Aborted(Exception):
    """The restore stopped part way through.

    strays: keys of windows OmniWM put in the slot instead of ours (focus
    moved between the check and the assign). lost: windows (as listed just
    before the assign) that the assign toggled OUT of the slot, because the
    focus had moved onto a member of that slot."""

    def __init__(self, why, strays=(), lost=(), slot=None):
        super().__init__(why)
        self.strays, self.lost, self.slot = list(strays), list(lost), slot


def sleep(s):
    time.sleep(s)


def assign_one(slot, e, alive, age, inst, instance):
    """Assign the window saved as e to slot. Returns (outcome, why, window
    key or None).

    Every check is against a fresh read, since the user may be pressing
    hotkeys meanwhile. Raises Aborted when OmniWM changed under us, or the
    assign hit another window."""
    wins = windows()
    (_, _, outcome, w, why), = plan([(slot, e)], wins, alive, age)
    if outcome != "assign":
        return outcome, why, key(w) if w else None
    try:
        ctl("window", "focus", w["id"])
    except Rejected as exc:
        return "failed", f"focusing it was refused ({exc.code})", key(w)
    deadline = time.monotonic() + FOCUS_TIMEOUT
    while focused() != key(w):
        if time.monotonic() >= deadline:
            return "failed", "focus did not land on it", key(w)
        sleep(0.05)
    if not same_instance(instance(), inst):
        raise Aborted("OmniWM restarted mid-restore")
    listed = windows()
    before = {key(x): x["slot"] for x in listed}
    if before.get(key(w), "gone") is not None:
        # Gone, or put in a slot (by a hotkey) since the first read. Assigning
        # now would toggle it back out.
        if before.get(key(w)) == slot:
            return "in-place", "put back by hand meanwhile", key(w)
        return "taken", "it changed while being restored", key(w)
    if focused() != key(w):
        return "failed", "focus moved off it before the assign", key(w)
    try:
        ctl("command", "scratchpad", "assign", str(slot))
    except Rejected as exc:
        return "failed", f"assign was refused ({exc.code})", key(w)
    after = {key(x): x["slot"] for x in windows()}
    strays = [k for k, s in after.items() if s == slot and before.get(k) != slot and k != key(w)]
    lost = [x for x in listed if x["slot"] == slot and after.get(key(x)) != slot]
    if strays or lost:
        # Focus moved between the last check and the assign (a click, a
        # hotkey), and the assign hit that window instead: into the slot, or
        # out of it if it was a member already.
        what = (f"window {strays[0]} went into slot {slot} instead" if strays
                else f"{describe(lost[0])} was toggled out of slot {slot}")
        raise Aborted(f"{what} (focus moved during the restore); stopping", strays, lost, slot)
    if after.get(key(w)) != slot:
        return "failed", "it is not in the slot after assigning", key(w)
    return "assigned", "assigned", key(w)


def view_now():
    return displays(), focused()


def restore_view(view, last):
    """Put each display's workspace and the focused window back.

    view is what it was before the restore; last is what the restore itself
    left after its last step (None if unknown). If the live view differs
    from last, the user changed it meanwhile (Caps+7, a click), and theirs
    wins: nothing is put back."""
    before_displays, before_focus = view
    try:
        now, now_focus = view_now()
    except (Unavailable, Rejected):
        return
    if last is not None and (sorted(now) != sorted(last[0]) or now_focus != last[1]):
        log("you moved focus or switched workspace during the restore; leaving it as you left it")
        return
    now_ws = {d: n for d, n, _ in now}
    now_current = next((d for d, _, c in now if c), None)
    # Other displays first, then the one that was current, then the window.
    # Switching to a workspace also makes its display the current one, so the
    # current display's workspace is re-selected whenever anything moved.
    moved = False
    for d, n, current in before_displays:
        if not current and d in now_ws and now_ws[d] != n:
            moved = switch(n, d) or moved
    for d, n, current in before_displays:
        if current and d in now_ws and (moved or now_ws[d] != n or now_current != d):
            switch(n, d)
    if before_focus is None:
        return
    try:
        wins = windows()
    except (Unavailable, Rejected):
        return
    w = next((x for x in wins if key(x) == before_focus), None)
    if w is None or (w["slot"] is not None and not w["visible"]):
        return  # closed, or now hidden in a scratchpad: focusing it would reveal the slot
    try:
        ctl("window", "focus", w["id"])
    except (Unavailable, Rejected) as exc:
        log(f"could not refocus {describe(w)}: {exc}")


def switch(n, display):
    try:
        ctl("command", "switch-workspace", str(n))
        return True
    except (Unavailable, Rejected) as exc:
        log(f"could not put workspace {n} back on {display}: {exc}")
        return False


def restore(entries, alive, age, inst, instance=None, report=None, results=None):
    """Restore [(slot, entry)] and return results, {(slot, pid, wid):
    (outcome, why, live window key)}.

    results is filled as it goes, so a caller that passes its own dict
    still has the finished part when this raises Unavailable or Aborted from
    the middle. The view is put back whenever anything was tried."""
    instance, report = instance or omniwm_instance, report or log
    results = {} if results is None else results
    todo = []
    for s, e, outcome, w, why in plan(entries, windows(), alive, age):
        if outcome == "assign":
            todo.append((s, e))
        else:
            results[(s, e["pid"], e["windowId"])] = (outcome, why, key(w) if w else None)
    if not todo:
        return results
    view, last = view_now(), None
    try:
        for s, e in todo:
            last = None
            outcome, why, wk = assign_one(s, e, alive, age, inst, instance)
            results[(s, e["pid"], e["windowId"])] = (outcome, why, wk)
            report(f"slot {s}: {describe(e)}: {why}")
            last = view_now()
    finally:
        try:
            restore_view(view, last)
        except (Unavailable, Rejected):
            pass
    return results


# ---------------------------------------------------------------------------
# The daemon's bookkeeping
# ---------------------------------------------------------------------------

class Keeper:
    """Saves the live slots, and restores the saved ones on a new OmniWM.

    lifetime    the OmniWM instance this has reconciled the file with; until
                then (a new OmniWM) nothing is written.
    pending     {(slot, pid, wid): {"slot", "entry", "since", "attempts",
                "next"}}: saved windows not yet back in their slot.
    ours        live window keys this restore put back (or found in place),
                or that were already saved: a slot member NOT in it was put
                there by hand since the restart, and the user's choice for
                that slot wins over what is still pending for it.
    quarantine  {window key: slot}: windows a stopped restore put in a slot
                by mistake, kept out of the file until that window moves.
    vanished    {(slot, pid, wid): (since, grace)} for held().
    """

    def __init__(self, path=None, instance=omniwm_instance, alive=pid_alive, age=None,
                 clock=time.time, started=started_at):
        self.path = path or STATE_FILE
        self.instance = instance
        self.alive = alive
        self.clock = clock
        self.age = age or (lambda pid: app_age(pid, self.clock()))
        self.started = started
        self.lifetime = None
        self.restored = False
        self.pending = {}
        self.vanished = {}
        self.saved_slots = {}
        self.ours = set()
        self.quarantine = {}
        self.app_starts = {}
        self.logged = set()
        self.down = None  # why OmniWM was last unreachable, logged once

    # -- logging ------------------------------------------------------------

    def once(self, tag, *parts):
        if tag not in self.logged:
            self.logged.add(tag)
            log(*parts)

    def unreachable(self, why, mismatch=None):
        if self.down == why:
            return
        self.down = why
        if mismatch is not None:
            log(f"omniwmctl cannot talk to the running OmniWM (app {mismatch.get('appVersion', '?')}, "
                f"protocol {mismatch.get('protocolVersion', '?')}): OmniWM was upgraded; restart it. "
                "The saved slots are kept and restored once it restarts.")
        else:
            log(f"OmniWM unreachable ({why}); keeping the saved slots.")

    # -- one refresh --------------------------------------------------------

    def tick(self):
        """One refresh. Returns when it next wants to run (epoch), or None."""
        inst = self.instance()
        if inst is None:
            self.unreachable("not running")
            return None
        try:
            wins = windows()
        except Unavailable as exc:
            self.unreachable(str(exc), exc.mismatch)
            return None
        if self.down is not None:
            log("OmniWM reachable again.")
            self.down = None
        if not same_instance(inst, self.lifetime):
            try:
                self.begin(inst)
            except OSError as exc:
                self.once(("read",), f"cannot read {self.path}: {exc}; waiting")
                return None
        now = self.clock()
        self.expire(now)
        if not self.restored:
            ready = inst["epoch"] + SETTLE
            if now < ready:
                return ready
            self.claim(wins, initial=True)
            ran, wins = self.run_restore(inst, wins, initial=True)
            if not ran:
                return now + 2.0
            self.restored = True
            if wins is None:
                return self.next_wake(now)
        elif self.retry_due(wins, now):
            _, wins = self.run_restore(inst, wins, initial=False)
            if wins is None:
                return self.next_wake(now)
        self.claim(wins, initial=False)
        if not same_instance(self.instance(), inst):
            return None  # restarted while we looked: the next tick begins again
        self.save(inst, wins, now)
        return self.next_wake(now)

    def next_wake(self, now):
        nxt = [p["next"] for p in self.pending.values() if p["next"] > now]
        nxt += [t + g for t, g in self.vanished.values() if t + g > now]
        return min(nxt) if nxt else None

    def begin(self, inst):
        doc = load_state(self.path)
        self.lifetime, self.vanished, self.ours, self.logged = inst, {}, set(), set()
        self.quarantine = {}
        now = self.clock()
        slots = doc.get("slots") if isinstance(doc.get("slots"), dict) else {}
        pending = doc.get("pending") if isinstance(doc.get("pending"), dict) else {}
        self.pending, self.saved_slots = {}, {}
        if same_instance(doc.get("omniwm"), inst):
            # The daemon restarted, OmniWM didn't: the live slots are already
            # right, and what the file holds was this lifetime's state (so
            # it counts as ours). Only carry on with what was still pending.
            self.saved_slots = slots
            self.ours = {(e["pid"], e["windowId"]) for _, e in entries_of(slots)}
            self.restored = True
            for s, e in entries_of(pending):
                since = e.get("since") if isinstance(e.get("since"), (int, float)) else now
                self.add_pending(s, e, since)
            log(f"OmniWM pid {inst['pid']} as before; {len(self.pending)} pending.")
            return
        # A new OmniWM: every saved window is pending until it is back.
        self.restored = False
        for s, e in entries_of(slots) + entries_of(pending):
            self.add_pending(s, e, now)
        if doc:
            log(f"new OmniWM (pid {inst['pid']}, started {inst['started']} UTC); "
                f"{len(self.pending)} saved window(s) to restore.")
        else:
            log(f"OmniWM pid {inst['pid']}; nothing saved yet.")

    def add_pending(self, s, e, since):
        e = {k: e.get(k) for k in ENTRY_KEYS if e.get(k) is not None or k in ("bundleId", "app")}
        self.pending[(s, e["pid"], e["windowId"])] = {"slot": s, "entry": e, "since": since,
                                                      "attempts": 0, "next": 0.0}

    def retry_due(self, wins, now):
        """Is a pending window findable now, with its retry time come?"""
        due = [(p["slot"], p["entry"]) for p in self.pending.values() if p["next"] <= now]
        return any(r[2] in ("assign", "in-place", "taken")
                   for r in plan(due, wins, self.alive, self.age))

    def run_restore(self, inst, wins, initial):
        """Restore the due pending windows. Returns (ran, windows after):
        ran is False when another restore held the lock; the windows are
        None if OmniWM went away or the restore was stopped (nothing is
        saved then)."""
        now = self.clock()
        due = {k: p for k, p in self.pending.items() if p["next"] <= now}
        entries = [(p["slot"], p["entry"]) for p in due.values()]
        results, stopped = {}, False
        with Lock(self.path) as got:
            if not got:
                log("another restore is running; trying again shortly")
                return False, wins
            try:
                restore(entries, self.alive, self.age, inst, self.instance, results=results)
            except Unavailable as exc:
                self.unreachable(str(exc), exc.mismatch)
                stopped = True
            except (Aborted, Rejected) as exc:
                log(f"restore stopped: {exc}")
                stopped = True
                self.stopped(exc, now)
        for k, p in due.items():
            if k not in results and stopped:
                p["next"] = now + RETRY_AFTER  # not reached: try again later
        self.record(results, now, initial)
        if stopped:
            return True, None
        try:
            return True, windows()
        except Unavailable as exc:
            self.unreachable(str(exc), exc.mismatch)
            return True, None

    def stopped(self, exc, now):
        """After an Aborted: keep a stray out of the file, and queue a window
        the assign toggled out of its slot to be put back."""
        for k in getattr(exc, "strays", ()):
            self.quarantine[k] = exc.slot
            log(f"slot {exc.slot}: window {k} was put there by mistake; it is not saved "
                "there unless you move it. To take it out, show the slot, focus it and "
                "press the slot's Caps+Shift chord")
        for w in getattr(exc, "lost", ()):
            e = entry_of(w, self.app_start(w["pid"]))
            self.add_pending(exc.slot, e, now)
            self.ours.discard(key(w))
            log(f"slot {exc.slot}: {describe(e)} was toggled out by mistake; will put it back")

    def record(self, results, now, initial):
        for k, (outcome, why, wk) in results.items():
            p = self.pending.get(k)
            if p is None:
                continue
            e, s = p["entry"], p["slot"]
            if outcome in ("assigned", "in-place", "duplicate"):
                if wk is not None:
                    self.ours.add(wk)
                del self.pending[k]
                if outcome == "in-place" and not initial:
                    log(f"slot {s}: {describe(e)} is back in place")
            elif outcome == "taken":
                del self.pending[k]
                log(f"slot {s}: skipped {describe(e)}: {why} (your choice since the restart wins)")
            elif outcome == "ambiguous":
                del self.pending[k]
                log(f"slot {s}: skipped {describe(e)}: {why}")
            elif outcome == "failed":
                p["attempts"] += 1
                if p["attempts"] >= MAX_ATTEMPTS:
                    # Keep it until the pending grace runs out, but stop
                    # stealing focus every RETRY_AFTER for it.
                    p["next"] = now + SLOW_RETRY
                    self.once(("failing",) + k, f"slot {s}: {describe(e)} failed {p['attempts']} times "
                              f"({why}); retrying every {SLOW_RETRY / 60:.0f} min")
                else:
                    p["next"] = now + RETRY_AFTER
            else:  # missing, wait
                self.once(("missing",) + k, f"slot {s}: {describe(e)} {why}; "
                          f"will keep looking for {PENDING_GRACE / 60:.0f} min")

    def claim(self, wins, initial):
        """Settle pending windows against the live slots, without acting.

        A pending window already in its slot is ours. Then, for a slot whose
        live members include one that is not ours (and not a mistake of
        ours), the user filled it by hand since the restart: their choice
        wins, and the rest still pending for it is dropped. On the first
        pass that also covers a slot filled before the restore ran."""
        rows = plan([(p["slot"], p["entry"]) for p in self.pending.values()], wins, self.alive, self.age)
        for s, e, outcome, w, _ in rows:
            if outcome in ("in-place", "duplicate") and w is not None:
                self.ours.add(key(w))
                self.pending.pop((s, e["pid"], e["windowId"]), None)
        if not initial and not self.restored:
            return
        hand = {w["slot"] for w in wins
                if w["slot"] is not None and key(w) not in self.ours
                and self.quarantine.get(key(w)) != w["slot"]}
        for k, p in list(self.pending.items()):
            if p["slot"] in hand:
                del self.pending[k]
                log(f"slot {p['slot']}: dropped {describe(p['entry'])}: "
                    f"you filled slot {p['slot']} by hand since the restart")

    def expire(self, now):
        for k, p in list(self.pending.items()):
            if now - p["since"] >= PENDING_GRACE:
                del self.pending[k]
                log(f"slot {p['slot']}: dropped {describe(p['entry'])}: "
                    f"not back within {PENDING_GRACE / 60:.0f} min")

    def app_start(self, pid):
        """Epoch the app at pid started, cached (a running pid keeps it)."""
        if pid not in self.app_starts:
            s = self.started(pid)
            self.app_starts[pid] = s[1] if s else None
        return self.app_starts[pid]

    def save(self, inst, wins, now):
        """Write the live slots, holding back losses that look like OmniWM's
        rather than the user's (see held())."""
        if not wins:
            return  # no windows at all is OmniWM starting or stopping, not a state to keep
        live_pids = {w["pid"] for w in wins}
        self.app_starts = {p: v for p, v in self.app_starts.items() if p in live_pids}
        for k, s in list(self.quarantine.items()):
            w = next((x for x in wins if key(x) == k), None)
            if w is None or w["slot"] != s:
                del self.quarantine[k]
        slots = live_slots(wins, self.app_start, skip=set(self.quarantine))
        for s, e in self.held(wins, now):
            slots.setdefault(str(s), []).append(e)
        pending = {}
        for p in sorted(self.pending.values(), key=lambda p: (p["slot"], p["entry"]["windowId"])):
            pending.setdefault(str(p["slot"]), []).append(dict(p["entry"], since=p["since"]))
        try:
            old = load_state(self.path)
        except OSError as exc:
            self.once(("read",), f"cannot read {self.path}: {exc}; not saving")
            return
        if (same_instance(old.get("omniwm"), inst) and old.get("slots") == slots
                and old.get("pending") == pending):
            self.saved_slots = slots
            return
        if summary(slots) != summary(self.saved_slots) or not same_instance(old.get("omniwm"), inst):
            log("saved:", summary(slots) or "no slots", f"(+{len(self.pending)} pending)" if pending else "")
        try:
            write_state({"version": VERSION, "omniwm": {"pid": inst["pid"], "started": inst["started"]},
                         "savedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
                         "slots": slots, "pending": pending}, self.path)
        except OSError as exc:
            log(f"cannot write {self.path}: {exc}")
            return
        self.saved_slots = slots

    def held(self, wins, now):
        """Saved members that left their slot but are kept for now.

        A window gone from OmniWM's list is kept for VANISH_GRACE: closed
        windows go after that, while an OmniWM that is quitting is a new
        instance by then, so its last answers never reach the file. A single
        window still listed but in no slot is the user's unassign and goes
        after UNASSIGN_GRACE, a re-check that OmniWM is still the same one;
        several at once (no hotkey does that) get the longer grace."""
        present = {key(w): w for w in wins}
        lost = []
        for s, e in entries_of(self.saved_slots):
            w = present.get((e["pid"], e["windowId"]))
            if w is None:
                lost.append((s, e, "gone"))
            elif w["slot"] is None:
                lost.append((s, e, "unassigned"))
            else:
                self.vanished.pop((s, e["pid"], e["windowId"]), None)
        unassigned = sum(1 for *_, why in lost if why == "unassigned")
        keep, seen = [], set()
        for s, e, why in lost:
            k = (s, e["pid"], e["windowId"])
            seen.add(k)
            grace = UNASSIGN_GRACE if why == "unassigned" and unassigned < 2 else VANISH_GRACE
            since, _ = self.vanished.setdefault(k, (now, grace))
            if now - since < grace:
                keep.append((s, e))
        for k in [k for k in self.vanished if k not in seen]:
            del self.vanished[k]
        return keep


def summary(slots):
    return "; ".join(f"{s}={', '.join((e.get('app') or '?') + ' ' + repr(e.get('title')) for e in es)}"
                     for s, es in sorted(slots.items(), key=lambda kv: int(kv[0])))


# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------

def daemon():
    if not os.access(OMNIWMCTL, os.X_OK):
        # Exit 0: KeepAlive.SuccessfulExit = false leaves the agent stopped
        # rather than respawning it every 10s on a machine without OmniWM.
        log(f"omniwmctl not found at {OMNIWMCTL}; idle.")
        return 0

    def stop(*_):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop)

    keeper = Keeper()
    proc, buf, backoff, started = None, b"", 1.0, 0.0
    tick = Debounce(time.monotonic())
    try:
        while True:
            if proc is None and time.monotonic() >= started + backoff:
                try:
                    proc = subprocess.Popen(
                        [OMNIWMCTL, "subscribe", "windows-changed,display-changed",
                         "--reconnect", "--no-send-initial", "--format", "ndjson"],
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
                    started, buf = time.monotonic(), b""
                    tick.event(started)
                except OSError as exc:
                    log("cannot start omniwmctl subscribe:", exc)
                    started, backoff = time.monotonic(), min(backoff * 2, 60)
            wait = max(0.0, tick.deadline() - time.monotonic())
            if proc is None:
                wait = min(wait, max(0.0, started + backoff - time.monotonic()))
                select.select([], [], [], wait)
            else:
                ready, _, _ = select.select([proc.stdout], [], [], wait)
                if ready:
                    chunk = os.read(proc.stdout.fileno(), 1 << 20)
                    if not chunk:
                        code = proc.wait()
                        proc = None
                        # --reconnect rides out OmniWM restarting; it exits on
                        # a protocol mismatch. The SAFETY poll covers the gap.
                        backoff = 1.0 if time.monotonic() - started > 60 else min(backoff * 2, 60)
                        started = time.monotonic()
                        tick.event(started)
                        if code:
                            log(f"omniwmctl subscribe exited ({code}); retrying in {backoff:.0f}s")
                        continue
                    buf += chunk
                    *lines, buf = buf.split(b"\n")
                    if len(buf) > 1 << 22:
                        buf = b""
                    if any(b'"event"' in line for line in lines):
                        tick.event(time.monotonic())
            now = time.monotonic()
            if tick.due(now):
                try:
                    want = keeper.tick()
                except Exception as exc:  # malformed output must not kill the daemon
                    log("refresh failed:", repr(exc))
                    want = None
                tick.done(time.monotonic())
                if want is not None:
                    tick.wake_at(time.monotonic() + max(0.5, want - time.time()))
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()


def saved_entries(doc):
    """Every (slot, entry) in a state file, slots then pending, deduplicated."""
    seen, out = set(), []
    for s, e in entries_of(doc.get("slots")) + entries_of(doc.get("pending")):
        k = (s, e["pid"], e["windowId"])
        if k not in seen:
            seen.add(k)
            out.append((s, e))
    return out


def read_or_report():
    try:
        return load_state()
    except OSError as exc:
        print(f"cannot read {STATE_FILE}: {exc}")
        return None


def status():
    doc = read_or_report()
    if doc is None:
        return 1
    inst = omniwm_instance()
    print(f"state file: {STATE_FILE}")
    if doc:
        o = doc.get("omniwm") or {}
        print(f"saved {doc.get('savedAt', '?')} under OmniWM pid {o.get('pid')} (started {o.get('started')} UTC)")
    else:
        print("nothing saved yet")
    print(f"OmniWM now: " + (f"pid {inst['pid']} (started {inst['started']} UTC)" if inst else "not running")
          + (", same as saved" if same_instance(doc.get("omniwm"), inst) else ""))
    try:
        wins = windows()
    except Unavailable as exc:
        print(f"OmniWM unreachable: {exc}" + (" (upgraded but not restarted: restart OmniWM)"
                                               if exc.mismatch is not None else ""))
        return 1
    live = live_slots(wins)
    print("live slots:", summary(live) or "none")
    now = time.time()
    rows = plan(saved_entries(doc), wins, pid_alive, lambda pid: app_age(pid, now))
    for s, e, outcome, _, why in rows:
        print(f"  slot {s}: {describe(e)}: {outcome}" + (f" ({why})" if outcome != "in-place" else ""))
    return 0


def restore_now():
    doc = read_or_report()
    if doc is None:
        return 1
    entries = saved_entries(doc)
    if not entries:
        print(f"nothing saved in {STATE_FILE}")
        return 0
    inst = omniwm_instance()
    if inst is None:
        print("OmniWM is not running")
        return 1
    now = time.time()
    with Lock() as got:
        if not got:
            print("the daemon is restoring right now; try again in a few seconds")
            return 1
        try:
            results = restore(entries, pid_alive, lambda pid: app_age(pid, now), inst,
                              report=lambda *p: print(*p))
        except Unavailable as exc:
            print(f"OmniWM unreachable: {exc}" + (" (upgraded but not restarted: restart OmniWM)"
                                                   if exc.mismatch is not None else ""))
            return 1
        except (Aborted, Rejected) as exc:
            print(f"stopped: {exc}")
            return 1
    for (s, pid, wid), (outcome, why, _) in sorted(results.items()):
        if outcome not in ("assigned",):
            print(f"slot {s}: pid {pid} window {wid}: {outcome} ({why})")
    return 0


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "daemon":
        return daemon()
    if cmd == "status":
        return status()
    if cmd == "restore":
        return restore_now()
    print("usage: omniwm-scratchpads daemon|status|restore", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
