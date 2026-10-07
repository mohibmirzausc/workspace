#!/usr/bin/env python3
"""Which cmux session needs me, and where is it?

Around 16 Claude Code sessions run at once, each in its own cmux window,
spread over 10 OmniWM workspaces. cmux knows which of them are waiting; this
says WHERE they are, in the two places that matter:

  hook      cmux notification hook (notifications.hooks in cmux.json). Reads
            the policy JSON on stdin and prints it back with the OmniWM
            location in front of the subtitle:
                "Completed in dotfiles"  ->  "Caps+F1 dotfiles · Completed in dotfiles"
  daemon    launchd agent. Follows `cmux events`, keeps a state file current
            and pokes sketchybar, which draws a "needs you" count with the
            workspace keys that hold those sessions, and colours their pills.
  snapshot  compute the state once and print it (debugging).

Where a session is: cmux workspace -> the cmux window holding it -> that
window's OmniWM window -> OmniWM workspace. The last two hops are the triage
skill's title join (inventory.py; see its docstring for why titles, and why
a title shared by two windows is never guessed), imported rather than copied.

What "needs you" means: the session's agentLifecycle is needsInput in cmux's
own hook-session store, counting only a session that is still the ACTIVE one
for a workspace that still exists, run by a process that is still alive. The
store keeps dead sessions forever; without those three checks a session that
asked a question two days ago in a closed window counted as waiting.
"Finished" means an unread cmux notification on a workspace that is not
waiting. Focusing the pane marks it read, which is what clears it.

THE HOOK MUST NEVER BREAK A NOTIFICATION. If it fails, times out or prints bad
JSON, cmux falls back to the default AND posts a failure alert -- so every
path, including a watchdog alarm, prints the input back unchanged. It never
calls the cmux CLI (cmux is waiting on it); it reads the daemon's state file
and asks OmniWM, which answers in ~10ms, where that window is right now.
Notification text is untrusted and is only ever handled as a Python string.
"""

import json
import os
import re
import select
import shutil
import signal
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
STATE_DIR = os.environ.get("CMUX_ATTENTION_DIR") or os.path.join(HOME, ".cache", "cmux-attention")
STATE_FILE = os.path.join(STATE_DIR, "state.json")
SESSIONS_FILE = os.path.join(HOME, ".cmuxterm", "claude-hook-sessions.json")
SKETCHYBAR_EVENT = "cmux_attention_changed"

# Debounce: refresh this long after the LAST event of a burst, but never
# later than MAX_WAIT after the first, so a steady trickle still refreshes.
QUIET, MAX_WAIT = 0.4, 2.0
# Safety refresh. Catches what no cmux event reports: a window moved to
# another workspace, a workspace relabelled.
SAFETY = 30.0
# The hook's whole budget. cmux's timeout is set well above it in cmux.nix.
HOOK_BUDGET = 1
SEP = " · "
LABEL_CHARS = 24
KEYS_SHOWN = 3


def find(name, fallback):
    return os.environ.get(name.upper().replace("-", "_") + "_BIN") or shutil.which(name) or fallback


CMUX = find("cmux", "/opt/homebrew/bin/cmux")
OMNIWMCTL = find("omniwmctl", "/opt/homebrew/bin/omniwmctl")
SKETCHYBAR = find("sketchybar", "/opt/homebrew/bin/sketchybar")


def _import_inventory():
    """The triage skill's inventory module, or None.

    The copy next to this file is tried first: the repo layout in a checkout
    (and the tests), and the same layout in the store, where
    programs/cmux/default.nix copies the triage skill in beside it. The
    skill installed by home.nix at ~/.claude/skills/triage is the fallback.
    """
    here = os.path.dirname(os.path.realpath(__file__))
    for d in (os.environ.get("TRIAGE_DIR"),
              os.path.join(here, "..", "agents", "skills", "triage"),
              os.path.join(HOME, ".claude", "skills", "triage")):
        if not d or not os.path.isfile(os.path.join(d, "inventory.py")):
            continue
        sys.path.insert(0, d)
        try:
            import inventory
            if all(hasattr(inventory, f) for f in ("cmux_by_title", "match_title", "live_titles", "ws_number")):
                return inventory
        except Exception:
            pass
        sys.path.remove(d)
        sys.modules.pop("inventory", None)
        sys.modules.pop("state", None)
    return None


inventory = _import_inventory()


def log(*parts):
    print(time.strftime("%H:%M:%S"), "cmux-attention:", *parts, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# Pure pieces (tested in test_attention.py)
# ---------------------------------------------------------------------------

def key_for(n):
    """The Caps chord's key for OmniWM workspace n: 1-5 are digits, 6-10 are
    F1-F5, and 11 is 6 (programs/karabiner.nix)."""
    if type(n) is not int:
        return None
    if 1 <= n <= 5:
        return str(n)
    if 6 <= n <= 10:
        return f"F{n - 5}"
    if n == 11:
        return "6"
    return None


def clean(text, limit):
    """One line of at most `limit` characters: control characters (newlines,
    tabs, escapes) become spaces and runs of whitespace collapse."""
    t = re.sub(r"[\x00-\x1f\x7f-\x9f  ]", " ", str(text or ""))
    t = re.sub(r"\s+", " ", t).strip()
    return t if len(t) <= limit else t[:limit - 1].rstrip() + "…"


def project_label(n, display_name, raw_name):
    """The project part of a workspace label, or None.

    Triage labels workspaces "<key> <project>" ("F1 dotfiles", "2 alloc") so
    the bar shows which key reaches them; the key is already in the location,
    so only the project is kept. A label that is just the key ("F2"), or no
    label at all (displayName == rawName), has no project.
    """
    label = clean(display_name, 64)
    if not label or label == clean(raw_name, 64):
        return None
    head, _, rest = label.partition(" ")
    key = key_for(n)
    if key and head.lower() in (key.lower(), str(n)):
        label = rest.strip()
    return clean(label, LABEL_CHARS) or None


def location(n, label):
    """"Caps+F1 dotfiles", "Caps+3", or None for an unknown workspace."""
    key = key_for(n)
    if not key:
        return None
    return f"Caps+{key}" + (f" {label}" if label else "")


def prefix_subtitle(subtitle, where):
    """Put `where` in front of the subtitle, replacing any location an earlier
    pass (a re-posted notification) already put there."""
    sub = subtitle if isinstance(subtitle, str) else ""
    if sub.startswith("Caps+") and SEP in sub:
        sub = sub.split(SEP, 1)[1]
    return where + SEP + sub if sub else where


def workspace_labels(ow_workspaces):
    """{workspace number: project label or None}."""
    out = {}
    for ws in ow_workspaces or []:
        if isinstance(ws, dict) and type(ws.get("number")) is int:
            out[ws["number"]] = project_label(ws["number"], ws.get("displayName"), ws.get("rawName"))
    return out


def map_workspaces(tree, ow_windows, ow_workspaces, cg):
    """{cmux workspace id: {"window", "ow", "ws", "key", "label"}}.

    Every cmux workspace (sidebar tab) in a window is where its window is.
    "ow"/"ws" are None when the window cannot be placed: the title join is
    ambiguous or finds nothing, or inventory.py is not installed.
    """
    labels = workspace_labels(ow_workspaces)
    ow_windows = [w for w in ow_windows if isinstance(w, dict)] if isinstance(ow_windows, list) else []
    by_title = inventory.cmux_by_title(ow_windows, cg if isinstance(cg, dict) else {}) if inventory else {}
    out = {}
    for win in (tree or {}).get("windows") or []:
        if not isinstance(win, dict):
            continue
        tabs = [t for t in win.get("workspaces") or [] if isinstance(t, dict) and t.get("id")]
        sel = next((t for t in tabs if t["id"] == win.get("selected_workspace_id")), None)
        ow = None
        if inventory and sel:
            match, ow, _, _ = inventory.match_title(sel.get("title") or "", by_title)
        n = inventory.ws_number(ow) if ow else None
        for t in tabs:
            out[t["id"]] = {"window": win.get("id"), "ow": ow.get("id") if ow else None,
                            "ws": n, "key": key_for(n), "label": labels.get(n)}
    return out


def _started(pid):
    """Epoch seconds the process `pid` started, or None if unknown."""
    try:
        out = subprocess.run(["/bin/ps", "-o", "lstart=", "-p", str(pid)],
                             capture_output=True, text=True, timeout=2,
                             env=dict(os.environ, LC_ALL="C", LANG="C"))
        return time.mktime(time.strptime(out.stdout.strip(), "%a %b %d %H:%M:%S %Y"))
    except (OSError, ValueError, OverflowError, subprocess.SubprocessError):
        return None


def _alive(pid, started_at=None, started=_started):
    """Is the process that recorded this session still running?

    A bare pid check is not enough: pids get reused, and a session whose
    Claude exited would keep counting as waiting for as long as some other
    process held its old pid. cmux records the start time (pidStartSeconds),
    so a process with that pid but another start time is a different one.
    """
    if type(pid) is not int or pid <= 0:
        return True  # no pid recorded: nothing says it is dead
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except OSError:
        pass  # EPERM: exists, owned by someone else
    if type(started_at) not in (int, float):
        return True
    actual = started(pid)
    # ps prints whole seconds; allow for that and a DST-edge wobble.
    return actual is None or abs(actual - started_at) <= 2


def waiting_workspaces(sessions_doc, live, alive=_alive):
    """cmux workspace ids whose live, active Claude session needs input."""
    doc = sessions_doc if isinstance(sessions_doc, dict) else {}
    sessions = doc.get("sessions") if isinstance(doc.get("sessions"), dict) else {}
    active = doc.get("activeSessionsByWorkspace") if isinstance(doc.get("activeSessionsByWorkspace"), dict) else {}
    out = set()
    for sid, s in sessions.items():
        if not isinstance(s, dict) or s.get("agentLifecycle") != "needsInput":
            continue
        ws = s.get("workspaceId")
        if not isinstance(ws, str):
            continue
        cur = active.get(ws)
        if ws not in live or not isinstance(cur, dict) or cur.get("sessionId") != sid:
            continue
        if alive(s.get("pid"), s.get("pidStartSeconds")):
            out.add(ws)
    return out


def unread_workspaces(notifications, live):
    """cmux workspace ids with at least one unread notification."""
    out = set()
    for n in notifications if isinstance(notifications, list) else []:
        if (isinstance(n, dict) and n.get("is_read") is False and isinstance(n.get("workspace_id"), str)
                and n["workspace_id"] in live):
            out.add(n["workspace_id"])
    return out


def format_keys(numbers, unplaced=False):
    """"2 F1 F3+" -- the workspace keys in order, capped at KEYS_SHOWN; "?"
    stands for sessions whose workspace could not be worked out."""
    keys = [key_for(n) for n in sorted(set(numbers))]
    keys = [k for k in keys if k]
    if unplaced:
        keys.append("?")
    if len(keys) > KEYS_SHOWN:
        return " ".join(keys[:KEYS_SHOWN]) + "+"
    return " ".join(keys)


def summarize(mapping, need, unread):
    """The state file's contents, minus the timestamp."""
    done = unread - need

    def group(ids):
        placed = [mapping[i]["ws"] for i in ids if mapping.get(i, {}).get("ws")]
        return {"count": len(ids),
                "keys": format_keys(placed, unplaced=len(placed) < len(ids)),
                "workspaces": sorted(ids)}

    windows = {}
    for ids, kind in ((done, "unread"), (need, "need")):  # need wins
        for i in ids:
            ow = mapping.get(i, {}).get("ow")
            if ow:
                windows[ow] = kind
    return {"version": 1, "workspaces": mapping, "windows": windows,
            "need": group(need), "done": group(done)}


# ---------------------------------------------------------------------------
# Live sources
# ---------------------------------------------------------------------------

def run_json(cmd, timeout):
    """Parsed JSON stdout of cmd, or None on any failure."""
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                             env=dict(os.environ, CMUX_QUIET="1"))
        if out.returncode != 0:
            return None
        return json.loads(out.stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        return None


# Whether the last omniwm() query failed. The daemon then asks why
# (omniwm_unreachable), rather than every query paying for it.
omniwm_failed = False


def omniwm(what, timeout, *args):
    global omniwm_failed
    doc = run_json([OMNIWMCTL, "query", what, *args, "--json"], timeout)
    omniwm_failed = not isinstance(doc, dict) or not doc.get("ok")
    if omniwm_failed:
        return None
    result = doc.get("result")
    payload = result.get("payload") if isinstance(result, dict) else None
    got = payload.get(what) if isinstance(payload, dict) else None
    return got if isinstance(got, list) else None


def read_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def compute(previous=None):
    """The current state, or None if cmux cannot be asked at all."""
    tree = run_json([CMUX, "--json", "--id-format", "both", "tree", "--all"], 5)
    if not isinstance(tree, dict):
        return None
    notifications = run_json([CMUX, "--json", "list-notifications"], 5)
    ow_windows = omniwm("windows", 3, "--fields", "id,window-id,app,title,workspace")
    ow_workspaces = omniwm("workspaces", 3)
    cg = inventory.live_titles() if inventory else {}
    mapping = map_workspaces(tree, ow_windows, ow_workspaces, cg)
    if ow_windows is None and previous:
        # OmniWM is briefly unreachable (restarting): keep the last known
        # places instead of reporting every session as unplaced.
        old = previous.get("workspaces") or {}
        for wid, m in mapping.items():
            if wid in old and m["ws"] is None:
                mapping[wid] = old[wid]
    live = set(mapping)
    need = waiting_workspaces(read_json(SESSIONS_FILE), live)
    unread = unread_workspaces(notifications, live)
    return summarize(mapping, need, unread)


def write_state(state):
    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = f"{STATE_FILE}.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, ensure_ascii=False)
    os.replace(tmp, STATE_FILE)  # atomic: readers see old or new, never half


# ---------------------------------------------------------------------------
# hook
# ---------------------------------------------------------------------------

def rewrite(raw, state, ow_windows, ow_workspaces):
    """The policy JSON with the location in front of the subtitle, or raw
    unchanged if there is nothing to add."""
    doc = json.loads(raw)
    note = doc.get("notification") if isinstance(doc, dict) else None
    if not isinstance(note, dict):
        return raw
    spot = ((state or {}).get("workspaces") or {}).get(note.get("workspaceId"))
    if not isinstance(spot, dict):
        return raw
    n, label = spot.get("ws"), spot.get("label")
    # Where the window is NOW: it may have moved since the daemon last looked.
    if spot.get("ow") and isinstance(ow_windows, list):
        now = next((w for w in ow_windows if isinstance(w, dict) and w.get("id") == spot["ow"]), None)
        if now is not None:
            n = ((now.get("workspace") or {}).get("number"))
            if isinstance(ow_workspaces, list):
                label = workspace_labels(ow_workspaces).get(n)
    where = location(n, label)
    if not where:
        return raw
    note["subtitle"] = prefix_subtitle(note.get("subtitle"), where)
    return json.dumps(doc)  # ASCII-escaped; see hook()


def _emit(data):
    """Write bytes to stdout, ignoring a pipe cmux already closed."""
    try:
        view = memoryview(data)
        while view:
            view = view[os.write(1, view):]
    except OSError:
        pass


def hook():
    """Print the policy back, with the location if one can be found.

    Bytes in, bytes out: the fallback is always the ORIGINAL bytes, so
    input that is not UTF-8 or not JSON passes through untouched rather
    than becoming an empty or re-encoded reply. stdin is read in full
    before the watchdog starts; cmux writes it and closes, and if it ever
    did not, its own timeout is the only thing that can end that wait. The
    rewrite is ASCII-escaped JSON, which survives lone surrogates that a
    UTF-8 encode would choke on.
    """
    try:
        raw = sys.stdin.buffer.read()
    except Exception:
        raw = b""

    def give_up(*_):
        _emit(raw)
        os._exit(0)

    signal.signal(signal.SIGALRM, give_up)
    signal.alarm(HOOK_BUDGET)
    out = raw
    try:
        text = raw.decode("utf-8")
        state = read_json(STATE_FILE)
        if state:
            new = rewrite(text, state,
                          omniwm("windows", 0.4, "--fields", "id,workspace"),
                          omniwm("workspaces", 0.4))
            if new is not text:
                out = new.encode("ascii")
    except Exception:
        out = raw
    signal.alarm(0)
    _emit(out)
    os._exit(0)


# ---------------------------------------------------------------------------
# daemon
# ---------------------------------------------------------------------------

RELEVANT = re.compile(r"^(notification\.(created|read|removed)|agent\.hook\.\w+)$")


class Debounce:
    """When to refresh, given event arrival times (monotonic seconds).

    Trailing edge: QUIET after the last event of a burst. Capped: never more
    than MAX_WAIT after the first unhandled one, so a busy stream (sixteen
    sessions calling tools) still refreshes every couple of seconds instead
    of never. Plus the SAFETY refresh when nothing happens at all.
    """

    def __init__(self, now):
        self.first = self.last = None
        self.safety = now  # refresh straight away

    def event(self, now):
        self.last = now
        if self.first is None:
            self.first = now

    def deadline(self):
        if self.first is None:
            return self.safety
        return min(self.safety, self.last + QUIET, self.first + MAX_WAIT)

    def due(self, now):
        return now >= self.deadline()

    def done(self, now):
        self.first = self.last = None
        self.safety = now + SAFETY


def events_in(buf, chunk):
    """(relevant event count, leftover partial line) for a chunk of NDJSON."""
    buf += chunk
    *lines, rest = buf.split(b"\n")
    if len(rest) > 1 << 20:
        rest = b""  # one runaway line: drop it rather than grow forever
    hits = 0
    for line in lines:
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if isinstance(ev, dict) and ev.get("type") == "event" and RELEVANT.match(str(ev.get("name"))):
            hits += 1
    return hits, rest


def drawn(state):
    """The parts of the state sketchybar draws."""
    if not state:
        return None
    return (state["need"]["count"], state["need"]["keys"],
            state["done"]["count"], state["done"]["keys"], state["windows"])


def omniwm_unreachable():
    """What omniwmctl says when OmniWM is running but doesn't answer its
    ping, else None (it answers, or it isn't running: nothing to fix).

    Happens when brew upgrades the OmniWM cask under a running app: the new
    omniwmctl (a symlink into the .app) fails every call against the old one,
    differently per release, hence "no pong" rather than one message:
      0.7.3 -> 0.7.4: error: protocol_mismatch (server protocol 16, app 0.7.3)
      0.7.4 -> 0.7.5: omniwmctl: Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"
    Every location then reads as unplaced, so the daemon logs it (once).
    """
    try:
        running = subprocess.run(["pgrep", "-x", "-U", str(os.getuid()), "OmniWM"],
                                 capture_output=True, timeout=3).returncode == 0
        if not running:
            return None
        out = subprocess.run([OMNIWMCTL, "ping"], capture_output=True, text=True, timeout=3)
        said = (out.stdout + out.stderr).strip()
    except subprocess.TimeoutExpired:
        said = ""
    except (OSError, ValueError, subprocess.SubprocessError):
        return None  # can't tell; say nothing
    if said == "pong":
        return None
    return said.splitlines()[0] if said else "no answer"


def mismatch_note(was, now):
    """The log line for an unreachable OmniWM that just began, else None, so
    one that lasts all day is one line, not one per refresh."""
    if now is None or was is not None:
        return None
    return (f"omniwmctl cannot reach the running OmniWM ({now}): if OmniWM was just "
            "upgraded, restart OmniWM. Locations are stale or missing until then.")


# The problem the daemon last reported on, so a refresh that raised still
# gets its note logged by the next one.
mismatch_reported = None


def report_mismatch():
    global mismatch_reported
    now = omniwm_unreachable() if omniwm_failed else None
    note = mismatch_note(mismatch_reported, now)
    if note:
        log(note)
    mismatch_reported = now


def refresh(previous):
    try:
        state = compute(previous)
    except Exception as exc:
        # Malformed output from cmux or OmniWM must not kill the daemon
        # (launchd would restart it, but the bar would sit stale meanwhile).
        log("refresh failed:", repr(exc))
        report_mismatch()
        return previous
    report_mismatch()
    if state is None:
        # cmux is down or refusing us: say nothing rather than leave a stale
        # "needs you" on the bar.
        state = summarize({}, set(), set())
    state["updatedAt"] = time.time()
    try:
        write_state(state)
    except OSError as exc:
        log("cannot write state:", exc)
    if drawn(state) != drawn(previous):
        try:
            subprocess.run([SKETCHYBAR, "--trigger", SKETCHYBAR_EVENT], capture_output=True, timeout=5)
        except (OSError, subprocess.SubprocessError):
            pass  # bar not running; its items read the state file when it starts
    return state


def daemon():
    for name, path in (("cmux", CMUX), ("sketchybar", SKETCHYBAR)):
        if not os.access(path, os.X_OK):
            # Exit 0, and the agent has KeepAlive.SuccessfulExit = false, so
            # launchd leaves it stopped instead of respawn-looping.
            log(f"{name} not found at {path}; idle.")
            return 0
    if inventory is None:
        log("triage inventory.py not importable; counting sessions without locations.")

    def stop(*_):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop)

    previous, proc, buf = None, None, b""
    backoff, started = 1.0, 0.0
    tick = Debounce(time.monotonic())
    try:
        while True:
            if proc is None:
                try:
                    proc = subprocess.Popen(
                        [CMUX, "events", "--category", "notification", "--category", "agent",
                         "--reconnect", "--no-ack"],
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
                    started, buf = time.monotonic(), b""
                    tick.event(started)  # catch up on anything missed while not listening
                except OSError as exc:
                    log("cannot start cmux events:", exc)
                    time.sleep(backoff)
                    backoff = min(backoff * 2, 60)
                    continue

            wait = max(0.0, tick.deadline() - time.monotonic())
            ready, _, _ = select.select([proc.stdout], [], [], wait)
            if ready:
                chunk = os.read(proc.stdout.fileno(), 65536)
                if not chunk:
                    code = proc.wait()
                    proc = None
                    # --reconnect rides out cmux quitting and restarting by
                    # itself; the CLI does exit when the socket refuses it
                    # ("Access denied" under socketControlMode cmuxOnly). A
                    # stream that died at once backs off.
                    backoff = 1.0 if time.monotonic() - started > 60 else min(backoff * 2, 60)
                    log(f"cmux events exited ({code}); retrying in {backoff:.0f}s")
                    previous = refresh(previous)
                    time.sleep(backoff)
                    continue
                hits, buf = events_in(buf, chunk)
                if hits:
                    tick.event(time.monotonic())
            # Checked on every pass, not only when select times out: a
            # stream busy enough never to go quiet must still hit MAX_WAIT.
            now = time.monotonic()
            if tick.due(now):
                previous = refresh(previous)
                tick.done(time.monotonic())
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()


# ---------------------------------------------------------------------------
# jump (Caps+U and the bar's bell)
# ---------------------------------------------------------------------------

def pick_notification(notifications, need):
    """The id of the newest unread notification on a waiting workspace."""
    best = None
    for n in notifications if isinstance(notifications, list) else []:
        if (isinstance(n, dict) and n.get("is_read") is False and n.get("workspace_id") in need
                and isinstance(n.get("id"), str)):
            if best is None or str(n.get("created_at") or "") > str(best.get("created_at") or ""):
                best = n
    return best["id"] if best else None


def pick_waiting(state):
    """(cmux window, workspace) of a waiting session, lowest OmniWM workspace
    first, for when none of the waiting sessions has an unread notification
    (you glanced at it but did not answer)."""
    st = state if isinstance(state, dict) else {}
    spots = st.get("workspaces") if isinstance(st.get("workspaces"), dict) else {}
    need = ((st.get("need") or {}).get("workspaces") or []) if isinstance(st.get("need"), dict) else []
    found = [(spots[w].get("ws") or 99, w, spots[w].get("window")) for w in need
             if isinstance(w, str) and isinstance(spots.get(w), dict)
             and isinstance(spots[w].get("window"), str)]
    if not found:
        return None
    _, ws, win = min(found)
    return win, ws


def jump():
    """Go to a session that is waiting for me, else to the latest unread one.

    `cmux jump-to-unread` alone takes the NEWEST unread notification, which
    is often a session that merely finished while another sits blocked on a
    question. So a waiting session's unread notification is opened first; if
    it has none (already read, not answered), its window and workspace are
    selected directly. All of these focus the cmux window, and OmniWM follows
    focus to its workspace. Any failure falls back to plain jump-to-unread.
    """
    def ok(*args):
        return subprocess.run([CMUX, *args], capture_output=True, timeout=5).returncode == 0

    try:
        state = read_json(STATE_FILE) or {}
        need = set(((state.get("need") or {}).get("workspaces")) or [])
        if need:
            nid = pick_notification(run_json([CMUX, "--json", "list-notifications"], 3), need)
            if nid and ok("open-notification", "--id", nid):
                return 0
            spot = pick_waiting(state)
            if spot and ok("focus-window", "--window", spot[0]) \
                    and ok("select-workspace", "--workspace", spot[1], "--window", spot[0]):
                return 0
    except Exception:
        pass
    try:
        return 0 if ok("jump-to-unread") else 1
    except (OSError, subprocess.SubprocessError):
        return 1


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "jump":
        return jump()
    if cmd == "hook":
        hook()
        return 0
    if cmd == "daemon":
        return daemon()
    if cmd == "snapshot":
        json.dump(compute(), sys.stdout, indent=1, ensure_ascii=False)
        print()
        return 0
    print("usage: attention.py hook|daemon|jump|snapshot", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
