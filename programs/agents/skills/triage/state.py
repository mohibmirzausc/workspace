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
   "layouts":  [{"workspace", "from", "to"}],
   "labels":   [{"workspace", "from", "to"}],
   "projects": [{"workspace", "label", "repos"}],   (apply only; not undone)
   "failed":   ["what failed"],
   "snapshot": [window ids the run decided on]}

`projects` records which repos each planned label stands for, on every run,
whether or not the label changed. That is how later runs learn a workspace's
project, including for labels set before this log existed.
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
        with open(log_path(), encoding="utf-8") as f:
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
    with open(log_path(), "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    return entry


def last_snapshot():
    """Window ids the most recent standing run decided on, or None if never run.

    Undone runs don't count: after an undo, the windows that run placed read
    "new" again, as they did before it.
    """
    undone = set()
    for entry in reversed(read_log()):
        if entry.get("kind") == "undo":
            if entry.get("complete"):
                undone.add(entry.get("undoes"))
        elif entry.get("ts") not in undone and isinstance(entry.get("snapshot"), list):
            return set(entry["snapshot"])
    return None


CHANGES = ("renames", "moves", "layouts", "labels")


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
            if entry.get("complete") and isinstance(entry.get("undoes"), str):
                undone.add(entry["undoes"])
        elif entry.get("kind") == "apply" and entry.get("ts") not in undone and changed(entry):
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
