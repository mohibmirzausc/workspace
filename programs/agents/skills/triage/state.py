"""The triage log: what each run did, so later runs (and undo) know.

A conversation can be rolled back, but the windows it moved stay moved. The log
is the record that survives that: one JSON object per line in
$TRIAGE_STATE_DIR/log.jsonl (default ~/.local/state/triage), appended by
apply.py after every run and read by inventory.py (to flag windows that are new
since the last run) and by `apply.py --undo`.

Entry shape:
  {"ts": ISO-8601, "kind": "apply" | "undo", "undoes": ts (undo only),
   "renames": [{"id", "cmux_workspace", "from", "to"}],
   "moves":   [{"id", "name", "from", "to"}],
   "layouts": [{"workspace", "from", "to"}],
   "labels":  [{"workspace", "from", "to", "repos"}],
   "snapshot": [window ids present after the run]}
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
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            # A torn last line (crash mid-write) must not hide the good ones.
            continue
    return entries


def append(entry):
    os.makedirs(state_dir(), exist_ok=True)
    entry = dict(entry)
    entry.setdefault("ts", datetime.datetime.now(datetime.timezone.utc).isoformat())
    with open(log_path(), "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    return entry


def last_snapshot():
    """Window ids present after the most recent run, or None if never run."""
    for entry in reversed(read_log()):
        if "snapshot" in entry:
            return set(entry["snapshot"])
    return None


CHANGES = ("renames", "moves", "layouts", "labels")


def changed(entry):
    return any(entry.get(k) for k in CHANGES)


def last_undoable():
    """The most recent apply entry that changed something and was not undone.

    Runs that changed nothing (e.g. a re-applied plan where everything was
    "already there") are logged for their snapshot but are not undo targets,
    or --undo would silently undo nothing.
    """
    undone = set()
    for entry in reversed(read_log()):
        if entry.get("kind") == "undo":
            undone.add(entry.get("undoes"))
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
    latest = {}
    for entry in read_log():
        for lab in entry.get("labels", []):
            latest[lab.get("workspace")] = lab
    return {
        n: set(lab["repos"])
        for n, lab in latest.items()
        if lab.get("repos") and current_labels.get(n) == lab.get("to")
    }
