"""The triage log: what each run did, so later runs (and undo) know.

A conversation can be rolled back, but the windows it moved stay moved. The log
is the record that survives that: one JSON object per line in
$TRIAGE_STATE_DIR/log.jsonl (default ~/.local/state/triage), appended by
apply.py after every run and read by inventory.py (to flag windows that are new
since the last run) and by `apply.py --undo`.

Entry shape:
  {"ts": ISO-8601, "kind": "apply" | "undo",
   "undoes": ts, "complete": bool          (undo only)
   "renames":  [{"id", "cmux_workspace", "from", "to"}],
   "moves":    [{"id", "name", "from", "to"}],
   "restores": [{"id", "name", "from", "to"}],   (from the restart pile; undo: back to it)
   "layouts":  [{"workspace", "from", "to"}],
   "labels":   [{"workspace", "from", "to"}],
   "projects": [{"workspace", "label", "repos"}],   (apply only; not undone)
   "failed":   ["what failed"],
   "snapshot": [window ids the run decided on],
   "placements": [{"name", "workspace", "repo",
                   "carried"?, "pile"?, "unverified"?}]}   (every cmux window after the run)

`projects` records which repos each planned label stands for, on every run,
whether or not the label changed. That is how later runs learn a workspace's
project, including for labels set before this log existed.

`placements` is where every cmux window was when the run ended, keyed by name
because names survive a cmux restart and window ids don't. After a restart
every window lands on one workspace, the pile (whichever one the user was
on: 1, 7, ...); the last placements say where each one belongs, so they can
be restored. A window still on the pile only because of a restart (its
approved restore failed, or an undo put it back or left it there) is recorded
at the workspace it belongs on, marked "carried", with "pile" the workspace
it is stuck on, so one partial run doesn't erase it; a restore the user
declined is forgotten. Entries from before "pile" was logged were all on 1. A
window that can't be located when the run ends keeps its previous placement,
marked "unverified".
"""

import datetime
import json
import os


def state_dir():
    return os.environ.get("TRIAGE_STATE_DIR") or os.path.expanduser("~/.local/state/triage")


def log_path():
    return os.path.join(state_dir(), "log.jsonl")


def read_log():
    try:
        # A line torn inside a multi-byte character must not break every read.
        with open(log_path(), encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        return []
    entries = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            # A torn last line (crash mid-write) must not hide the good ones.
            continue
        if isinstance(entry, dict):  # anything else is a hand edit; ignore it
            entries.append(entry)
    return entries


def append(entry):
    os.makedirs(state_dir(), exist_ok=True)
    entry = dict(entry)
    entry.setdefault("ts", datetime.datetime.now(datetime.timezone.utc).isoformat())
    line = json.dumps(entry, ensure_ascii=False) + "\n"
    with open(log_path(), "a+b") as f:
        size = f.seek(0, os.SEEK_END)
        if size:
            # After a torn last line, start a fresh one, or this entry is
            # glued to the torn one and both are lost.
            f.seek(size - 1)
            if f.read(1) != b"\n":
                line = "\n" + line
        f.write(line.encode("utf-8"))
    return entry


def ts_of(entry, key="ts"):
    """An entry's timestamp (or the one it undoes), if it is a usable string."""
    value = entry.get(key)
    return value if isinstance(value, str) else None


def reverted(entry):
    """The ts an undo entry really reverted on screen, or None.

    An abandoned undo only stops trying: nothing changed, so the run it
    names still stands for what is on screen (snapshot, placements).
    """
    if entry.get("kind") == "undo" and entry.get("complete") and not entry.get("abandoned"):
        return ts_of(entry, "undoes")
    return None


def last_snapshot():
    """Window ids the most recent standing run decided on, or None if never run.

    Undone runs don't count: after an undo, the windows that run placed read
    "new" again, as they did before it.
    """
    undone = set()
    for entry in reversed(read_log()):
        if entry.get("kind") == "undo":
            undone.add(reverted(entry) or "")
        elif ts_of(entry) not in undone and isinstance(entry.get("snapshot"), list):
            return {i for i in entry["snapshot"] if isinstance(i, str)}
    return None


CHANGES = ("renames", "moves", "restores", "layouts", "labels")


def changed(entry):
    return any(entry.get(k) for k in CHANGES)


def last_undoable():
    """The most recent apply entry that changed something and was not undone.

    Runs that changed nothing (e.g. a re-applied plan where everything was
    "already there") are logged for their snapshot but are not undo targets,
    or --undo would silently undo nothing. An undo that failed part-way is
    not "complete", so its target stays undoable and can be retried.
    """
    undone = set()
    for entry in reversed(read_log()):
        if entry.get("kind") == "undo":
            if entry.get("complete") and ts_of(entry, "undoes"):
                undone.add(entry["undoes"])
        elif entry.get("kind") == "apply" and ts_of(entry) and entry["ts"] not in undone and changed(entry):
            return entry
    return None


def label_repos(current_labels):
    """{workspace: set of repos} for labels triage set that are still on the bar.

    A label like "F1 dotfiles" doesn't name a repo, so the project's repos are
    recorded when apply.py sets the label (a project can span several, e.g.
    two imogen repos). It counts only while the live label is still
    the one triage wrote; a hand edit or a newer label drops the mapping.
    """
    # Keyed by (workspace, label text), so undoing back to an older label
    # finds the repos recorded for that label.
    latest = {}
    for entry in read_log():
        projects = entry.get("projects")
        for proj in projects if isinstance(projects, list) else []:
            if not isinstance(proj, dict):
                continue
            n, label, repos = proj.get("workspace"), proj.get("label"), proj.get("repos")
            if (type(n) is int and isinstance(label, str) and label and isinstance(repos, list)
                    and repos and all(isinstance(r, str) and r for r in repos)):
                latest[(n, label)] = set(repos)
    return {
        n: latest[(n, label)]
        for n, label in current_labels.items()
        if (n, label) in latest
    }


def last_placements():
    """{name: {"workspace", "repo", "carried", "pile"}} from the most recent
    standing entry with placements. "pile" is the workspace a carried window
    is stuck on (1 for entries from before it was logged), else None.

    Undone applies don't count (the undo's own placements follow them), but
    abandoned ones do: abandoning changes nothing on screen. A name recorded
    more than once, or with no workspace, is dropped: it can't say where one
    window belongs.
    """
    undone = set()
    for entry in reversed(read_log()):
        undone.add(reverted(entry) or "")
        if entry.get("kind") not in ("apply", "undo") or not ts_of(entry) or entry["ts"] in undone:
            continue
        placements = entry.get("placements")
        if not isinstance(placements, list):
            continue
        spots, dupes = {}, set()
        for p in placements:
            if not isinstance(p, dict) or not isinstance(p.get("name"), str) or not p["name"]:
                continue
            name, n, repo = p["name"], p.get("workspace"), p.get("repo")
            if name in spots or name in dupes:
                dupes.add(name)
                spots.pop(name, None)
            elif type(n) is int and 1 <= n <= 11:
                pile = p.get("pile", 1)
                # A carried window with a malformed pile can't say where it
                # is stuck, so it isn't carried.
                carried = (p.get("carried") is True and type(pile) is int
                           and 1 <= pile <= 11 and pile != n)
                spots[name] = {"workspace": n, "repo": repo if isinstance(repo, str) else None,
                               "carried": carried, "pile": pile if carried else None}
            else:
                dupes.add(name)  # known to exist, but not where
        return spots
    return {}
