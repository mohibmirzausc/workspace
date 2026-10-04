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
  2. bundle id + title, ONLY if the saved pid is no longer running (the app
     itself restarted, e.g. after a reboot), only once that app has been up
     APP_SETTLE seconds (so all its windows have come back), and only if
     exactly one unassigned window of that app has that title. Two Chrome
     windows called "New Tab" are skipped and logged, never guessed. If the
     saved pid is still running, a missing window was closed: no fallback.

Apps without a bundle id (Minecraft's "java") use "name:<app name>".

WHEN TO SAVE, AND WHEN NOT TO. OmniWM's lifetime is its pid plus start time
(as in triage's inventory.omniwm_instance). Within one lifetime the live slots
are the truth, so a slot the user empties is saved empty. Across lifetimes
the file is the truth until the restore has run: nothing is written for a new
OmniWM before that, and nothing at all while OmniWM is unreachable or
answering protocol_mismatch (an upgrade under a running app). A saved window
that vanishes from OmniWM's list is kept for VANISH_GRACE seconds before it is
dropped, so the last answers of an OmniWM that is quitting cannot wipe the
file. Windows not found at restore stay "pending" for PENDING_GRACE seconds
(apps reopen their windows slowly after a reboot), then are dropped and
logged.

HOW A RESTORE ASSIGNS. There is no IPC call that assigns a given window, only
`command scratchpad assign <n>`, which acts on the focused window. And assign
TOGGLES: a window already in slot n is released from it (WMController+
ScratchpadCommands.assignWindowToScratchpad). So for each window: re-read the
live state, skip it if it is in any slot already (a slot the user filled since
the restart wins), `window focus` it, wait until OmniWM reports it focused,
re-read once more, assign, and check the result. Slots hold several windows
(ScratchpadState.membersBySlot), so assigning never evicts another member. An
assigned window is hidden unless its slot is the one showing, as with the
hotkey. Afterwards each display gets its workspace back and the window that
had focus is refocused, unless it is now hidden in a scratchpad (focusing it
would reveal the slot).
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


def pid_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except (OSError, OverflowError, ValueError):
        return True  # EPERM: it exists
    return True


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


def entry_of(w):
    return {"pid": w["pid"], "windowId": w["windowId"], "bundleId": w.get("bundleId"),
            "app": w.get("app"), "title": w.get("title") or ""}


def describe(e):
    return f"{e.get('app') or e.get('bundleId') or '?'} {e.get('title')!r} (pid {e.get('pid')}, window {e.get('windowId')})"


def live_slots(wins):
    """{"n": [entry, ...]} from a window list, members in window-id order."""
    out = {}
    for w in sorted(wins, key=key):
        if w["slot"] is not None:
            out.setdefault(str(w["slot"]), []).append(entry_of(w))
    return out


def match(e, wins, alive, age):
    """Find saved entry e among the live windows.

    Returns (outcome, window, why): ("found", w, how) or ("missing", None,
    why), ("ambiguous", None, why), ("wait", None, why). alive(pid) says if
    a process is running; age(pid) is how long it has been, or None."""
    ak = app_key(e)
    for w in wins:
        if key(w) == (e.get("pid"), e.get("windowId")) and app_key(w) == ak:
            return "found", w, "same window"
    if ak is None:
        return "missing", None, "not found, and it has no app to match by"
    if type(e.get("pid")) is int and alive(e["pid"]):
        return "missing", None, "not found while its app is still running: closed"
    title = e.get("title") or ""
    if not title:
        return "missing", None, "its app restarted and it has no title to match by"
    cands = [w for w in wins if app_key(w) == ak and w.get("title") == title]
    if not cands:
        return "missing", None, "its app restarted and no window has its title"
    if len(cands) > 1:
        return "ambiguous", None, f"its app restarted and {len(cands)} of its windows are titled {title!r}"
    a = age(cands[0]["pid"])
    if a is None or a < APP_SETTLE:
        return "wait", None, "its app restarted moments ago; waiting for all its windows"
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
    path = path or STATE_FILE
    try:
        with open(path) as f:
            doc = json.load(f)
    except FileNotFoundError:
        return {}
    except (OSError, ValueError) as exc:
        log(f"cannot read {path}: {exc}; starting from nothing")
        return {}
    return doc if isinstance(doc, dict) else {}


def write_state(doc, path=None):
    path = path or STATE_FILE
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(doc, f, indent=2, sort_keys=True)
        f.write("\n")
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
    pass


def sleep(s):
    time.sleep(s)


def assign_one(slot, e, alive, age, inst, instance):
    """Assign the window saved as e to slot. Returns (outcome, why).

    Every check is against a fresh read, since the user may be pressing
    hotkeys meanwhile. Raises Aborted when OmniWM changed under us."""
    wins = windows()
    (_, _, outcome, w, why), = plan([(slot, e)], wins, alive, age)
    if outcome != "assign":
        return outcome, why
    try:
        ctl("window", "focus", w["id"])
    except Rejected as exc:
        return "failed", f"focusing it was refused ({exc.code})"
    deadline = time.monotonic() + FOCUS_TIMEOUT
    while focused() != key(w):
        if time.monotonic() >= deadline:
            return "failed", "focus did not land on it"
        sleep(0.05)
    if not same_instance(instance(), inst):
        raise Aborted("OmniWM restarted mid-restore")
    before = {key(x): x["slot"] for x in windows()}
    if before.get(key(w), "gone") is not None:
        # Gone, or put in a slot (by a hotkey) since the first read. Assigning
        # now would toggle it back out.
        if before.get(key(w)) == slot:
            return "in-place", "put back by hand meanwhile"
        return "taken", "it changed while being restored"
    try:
        ctl("command", "scratchpad", "assign", str(slot))
    except Rejected as exc:
        return "failed", f"assign was refused ({exc.code})"
    after = {key(x): x["slot"] for x in windows()}
    strays = [k for k, s in after.items() if s == slot and before.get(k) != slot and k != key(w)]
    if strays:
        # Focus moved between the check and the assign (a click, a hotkey),
        # and OmniWM assigned that window instead.
        raise Aborted(f"slot {slot} got window {strays[0]} instead (focus moved); "
                      "stopping. Fix it with the hotkeys if that is wrong")
    if after.get(key(w)) != slot:
        return "failed", "it is not in the slot after assigning"
    return "assigned", "assigned"


def restore_view(view, wins):
    """Put each display's workspace and the focused window back."""
    before_displays, before_focus = view
    try:
        now = displays()
    except (Unavailable, Rejected):
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


def restore(entries, alive, age, inst, instance=None, report=None):
    """Restore [(slot, entry)]. Returns {(slot, pid, wid): (outcome, why)}.

    Raises Unavailable/Aborted from the middle; the view is put back
    whenever anything was assigned."""
    instance, report = instance or omniwm_instance, report or log
    results, todo = {}, []
    for s, e, outcome, _, why in plan(entries, windows(), alive, age):
        if outcome == "assign":
            todo.append((s, e))
        else:
            results[(s, e["pid"], e["windowId"])] = (outcome, why)
    if not todo:
        return results
    view = (displays(), focused())
    try:
        for s, e in todo:
            outcome, why = assign_one(s, e, alive, age, inst, instance)
            results[(s, e["pid"], e["windowId"])] = (outcome, why)
            report(f"slot {s}: {describe(e)}: {why}")
    finally:
        try:
            restore_view(view, windows())
        except (Unavailable, Rejected):
            pass
    return results


# ---------------------------------------------------------------------------
# The daemon's bookkeeping
# ---------------------------------------------------------------------------

class Keeper:
    """Saves the live slots, and restores the saved ones on a new OmniWM.

    lifetime  the OmniWM instance this has reconciled the file with; until
              then (a new OmniWM) nothing is written.
    pending   {(slot, pid, wid): {"slot", "entry", "since", "attempts",
              "next"}}: saved windows not yet back in their slot.
    vanished  {(slot, pid, wid): when first seen out of its slot}, for
              held().
    """

    def __init__(self, path=None, instance=omniwm_instance, alive=pid_alive, age=None,
                 clock=time.time):
        self.path = path or STATE_FILE
        self.instance = instance
        self.alive = alive
        self.clock = clock
        self.age = age or (lambda pid: app_age(pid, self.clock()))
        self.lifetime = None
        self.restored = False
        self.pending = {}
        self.vanished = {}
        self.saved_slots = {}
        self.ours = set()
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
            self.begin(inst)
        now = self.clock()
        if not self.restored:
            ready = inst["epoch"] + SETTLE
            if now < ready:
                return ready
            wins = self.run_restore(inst, wins, initial=True)
            if wins is None:
                return None
            self.restored = True
        elif self.retry_due(wins, now):
            wins = self.run_restore(inst, wins, initial=False)
            if wins is None:
                return None
        self.expire(wins, now)
        if not same_instance(self.instance(), inst):
            return None  # restarted while we looked: the next tick begins again
        self.save(inst, wins, now)
        nxt = [p["next"] for p in self.pending.values() if p["next"] > now]
        nxt += [t + VANISH_GRACE for t in self.vanished.values() if t + VANISH_GRACE > now]
        return min(nxt) if nxt else None

    def begin(self, inst):
        doc = load_state(self.path)
        self.lifetime, self.vanished, self.ours, self.logged = inst, {}, set(), set()
        now = self.clock()
        slots = doc.get("slots") if isinstance(doc.get("slots"), dict) else {}
        pending = doc.get("pending") if isinstance(doc.get("pending"), dict) else {}
        self.pending, self.saved_slots = {}, {}
        if same_instance(doc.get("omniwm"), inst):
            self.saved_slots = slots
            # The daemon restarted, OmniWM didn't: the live slots are already
            # right. Only carry on with what was still pending.
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
        e = {k: e.get(k) for k in ("pid", "windowId", "bundleId", "app", "title")}
        self.pending[(s, e["pid"], e["windowId"])] = {"slot": s, "entry": e, "since": since,
                                                      "attempts": 0, "next": 0.0}

    def retry_due(self, wins, now):
        """Is a pending window findable now, with its retry time come?"""
        due = [(p["slot"], p["entry"]) for p in self.pending.values() if p["next"] <= now]
        return any(r[2] in ("assign", "in-place", "taken")
                   for r in plan(due, wins, self.alive, self.age))

    def run_restore(self, inst, wins, initial):
        """Restore the due pending windows. Returns the live windows after,
        or None if OmniWM went away (nothing is saved then)."""
        now = self.clock()
        due = {k: p for k, p in self.pending.items() if p["next"] <= now}
        entries = [(p["slot"], p["entry"]) for p in due.values()]
        with Lock(self.path) as got:
            if not got:
                log("another restore is running; trying again shortly")
                for p in due.values():
                    p["next"] = now + 2.0
                return wins
            try:
                results = restore(entries, self.alive, self.age, inst, self.instance)
            except Unavailable as exc:
                self.unreachable(str(exc), exc.mismatch)
                return None
            except (Aborted, Rejected) as exc:
                log(f"restore stopped: {exc}")
                for p in due.values():
                    p["next"] = now + RETRY_AFTER
                return None
        for k, (outcome, why) in results.items():
            p = self.pending.get(k)
            if p is None:
                continue
            e, s = p["entry"], p["slot"]
            if outcome in ("assigned", "in-place", "duplicate"):
                self.ours.add(k)
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
                p["next"] = now + RETRY_AFTER
                if p["attempts"] >= MAX_ATTEMPTS:
                    del self.pending[k]
                    log(f"slot {s}: gave up on {describe(e)} after {MAX_ATTEMPTS} tries: {why}")
            else:  # missing, wait
                self.once(("missing",) + k, f"slot {s}: {describe(e)} {why}; "
                          f"will keep looking for {PENDING_GRACE / 60:.0f} min")
        try:
            return windows()
        except Unavailable as exc:
            self.unreachable(str(exc), exc.mismatch)
            return None

    def expire(self, wins, now):
        live = live_slots(wins)
        for k, p in list(self.pending.items()):
            s = p["slot"]
            hand = [e for e in live.get(str(s), []) if (s, e["pid"], e["windowId"]) not in self.ours]
            if self.restored and hand:
                del self.pending[k]
                log(f"slot {s}: dropped {describe(p['entry'])}: you filled slot {s} by hand since the restart")
            elif now - p["since"] >= PENDING_GRACE:
                del self.pending[k]
                log(f"slot {s}: dropped {describe(p['entry'])}: not found within {PENDING_GRACE / 60:.0f} min")

    def save(self, inst, wins, now):
        """Write the live slots, holding back losses that look like OmniWM's
        rather than the user's (see held())."""
        if not wins:
            return  # no windows at all is OmniWM starting or stopping, not a state to keep
        slots = live_slots(wins)
        for s, e in self.held(wins, now):
            slots.setdefault(str(s), []).append(e)
        pending = {}
        for p in sorted(self.pending.values(), key=lambda p: (p["slot"], p["entry"]["windowId"])):
            pending.setdefault(str(p["slot"]), []).append(dict(p["entry"], since=p["since"]))
        old = load_state(self.path)
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
        window still listed but in no slot is the user's unassign and goes at
        once; several at once (no hotkey does that) are held the same way."""
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
            if why == "unassigned" and unassigned < 2:
                self.vanished.pop(k, None)
                continue
            if now - self.vanished.setdefault(k, now) < VANISH_GRACE:
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


def status():
    doc = load_state()
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
    doc = load_state()
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
        except Aborted as exc:
            print(f"stopped: {exc}")
            return 1
    for (s, pid, wid), (outcome, why) in sorted(results.items()):
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
