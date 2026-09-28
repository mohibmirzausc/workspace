#!/usr/bin/env python3
"""Carry out a triage plan, log it, and undo the last one.

  apply.py [--dry-run] PLAN.json     validate and apply a plan (- for stdin)
  apply.py --undo [--dry-run]        reverse the most recent apply

Exit status: 0 done, 1 done but something failed (see "failed"), 2 refused.

Plan shape (unknown keys are refused, so a typo can't be silently ignored):
  {"windows": [{"id": "<inventory id>",
                "action": "stay" | "move" | "review" | "skip",
                "to": N,             # move only: a pool workspace, 2-9
                "rename": "name",    # optional; not on skip
                "reason": "why"}],   # required to keep a flagged window
   "workspaces": [{"number": N, "label": "F1 dotfiles",
                   "repos": ["workspace"], "layout": "dwindle"}]}

Validation (refusals name the window):
  * coverage: every window in a fresh inventory gets exactly one decision;
  * workspace 1 is untouchable: its windows must be "skip", and so must any
    window that MIGHT be on it (an unmatched window's workspace is unknown);
    skipped windows can't be renamed;
  * moves go to 2-9 and "review" means 10; only tiled, non-scratchpad windows
    matched to their own OmniWM window move. An unmatched window can only stay
    (rename it now so it matches, and move it next run);
  * renames are unique across the resulting set of names;
  * a window flagged new or misplaced may stay, but only with a "reason".

Execution: renames, a fresh inventory, then every move is re-checked against
it (still not on workspace 1, still uniquely matched) right before it happens;
a window already on its destination is "already there", so re-applying a plan
(e.g. after a rolled-back conversation) is harmless. Then layouts, labels, and
every display back to the workspace it showed. Every change is logged with its
before value (state.py), even if the run stops part-way, and --undo replays
the log backwards under the same workspace bounds.
"""

import json
import subprocess
import sys

import inventory
import state
from inventory import POOL, REVIEW_WORKSPACE, USER_WORKSPACE

ACTIONS = {"stay", "move", "review", "skip"}
LAYOUTS = {"dwindle", "niri"}
PLAN_KEYS = {"windows", "workspaces"}
WINDOW_KEYS = {"id", "action", "to", "rename", "reason"}
WORKSPACE_KEYS = {"number", "label", "repos", "layout"}
LABELLED = POOL | {REVIEW_WORKSPACE}
MAX_LABEL = 12
MAX_NAME = 16


def key_for(n):
    """The key that reaches workspace n: the digit for 2-5, F1-F5 for 6-10."""
    return str(n) if n <= 5 else f"F{n - 5}"


def is_int(x):
    return type(x) is int  # not bool, not 2.0


def clean_text(x, limit):
    """A printable, trimmed, non-empty string of at most `limit` characters."""
    return isinstance(x, str) and x == x.strip() and 0 < len(x) <= limit and x.isprintable()


def cmux(*args):
    return inventory.run("cmux", *args)


def omni(*args):
    """Run an omniwmctl command; return (ok, status, or the error code if not ok)."""
    try:
        out = subprocess.run(["omniwmctl", "--json", *map(str, args)],
                             capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, type(exc).__name__
    try:
        doc = json.loads(out.stdout)
    except json.JSONDecodeError:
        return False, (out.stderr.strip() or f"exit {out.returncode}")
    ok = bool(doc.get("ok"))
    return ok, ((doc.get("status") if ok else doc.get("code") or doc.get("status")) or "")


# ---------------------------------------------------------------- validation

def validate(plan, inv):
    """Return a list of problems; empty means the plan may run."""
    if not isinstance(plan, dict):
        return ["the plan must be a JSON object"]
    problems = [f"unknown plan key {k!r}" for k in plan if k not in PLAN_KEYS]
    entries = plan.get("windows")
    if not isinstance(entries, list) or not all(isinstance(e, dict) for e in entries):
        return problems + ["'windows' must be a list of objects"]
    workspaces = plan.get("workspaces", [])
    if not isinstance(workspaces, list) or not all(isinstance(ws, dict) for ws in workspaces):
        return problems + ["'workspaces' must be a list of objects"]

    by_id = {w["id"]: w for w in inv["windows"]}
    seen = {}
    for e in entries:
        problems += [f"window entry has unknown key {k!r}" for k in e if k not in WINDOW_KEYS]
        wid = e.get("id")
        if not isinstance(wid, str):
            problems.append(f"window entry needs a string 'id', got {wid!r}")
            continue
        if wid in seen:
            problems.append(f"window {wid} appears twice in the plan")
        seen[wid] = e
    for i, w in by_id.items():
        if i not in seen:
            problems.append(f"no decision for window {w['name']!r} (id {i}, workspace {w['omniwm_workspace']})")
    for i in seen:
        if i not in by_id:
            problems.append(f"plan names window {i}, which is not open")

    # Every window's name once the plan has run, to keep renames unique.
    final_names = {}
    for i, w in by_id.items():
        new = seen.get(i, {}).get("rename")
        final_names.setdefault(new if isinstance(new, str) else w["name"], []).append(i)
    moving = {}

    for wid, e in seen.items():
        w = by_id.get(wid)
        if w is None:
            continue
        name, action = w["name"], e.get("action")
        if not isinstance(action, str) or action not in ACTIONS:
            problems.append(f"{name!r}: action must be one of {sorted(ACTIONS)}, got {action!r}")
            continue
        maybe_user = w["omniwm_workspace"] == USER_WORKSPACE or bool(w.get("maybe_user_workspace"))
        if maybe_user and action != "skip":
            why = "is on workspace 1" if w["omniwm_workspace"] == USER_WORKSPACE else \
                f"can't be located ({w['omniwm_match']} match) and might be on workspace 1"
            problems.append(f"{name!r} {why}, which triage never touches: must be 'skip'")
        if action == "skip" and not maybe_user:
            problems.append(f"{name!r}: 'skip' is only for workspace 1; use 'stay'")
        if "to" in e and action != "move":
            problems.append(f"{name!r}: 'to' only goes with 'move'")
        if action == "move" and not (is_int(e.get("to")) and e["to"] in POOL):
            problems.append(f"{name!r}: move needs 'to' as a whole number 2-9 (review is its own action), got {e.get('to')!r}")
        if action in ("move", "review"):
            if w.get("floating") or w.get("scratchpad"):
                problems.append(f"{name!r} is a floating or scratchpad window; triage doesn't move those")
            elif w["omniwm_match"] != "ok":
                problems.append(f"{name!r} isn't matched to an OmniWM window ({w['omniwm_match']}): "
                                "it can only 'stay' (rename it so it matches, and move it next run)")
            else:
                moving.setdefault(w["omniwm_id"], []).append(name)
        if "reason" in e and not isinstance(e["reason"], str):
            problems.append(f"{name!r}: 'reason' must be a string")
        flags = [f for f in ("new", "misplaced") if w.get(f)]
        if flags and action == "stay" and not (isinstance(e.get("reason"), str) and e["reason"].strip()):
            problems.append(f"{name!r} is flagged {' and '.join(flags)}: 'stay' is fine but needs a 'reason'")
        if "rename" in e:
            new = e["rename"]
            if action == "skip":
                problems.append(f"{name!r}: a skipped window can't be renamed")
            elif not clean_text(new, MAX_NAME):
                problems.append(f"{name!r}: rename must be 1-{MAX_NAME} printable characters with no outer spaces, got {new!r}")
            elif len(final_names.get(new, [])) > 1:
                problems.append(f"{name!r}: rename {new!r} would give two windows the same name")

    for names in moving.values():
        if len(names) > 1:
            problems.append(f"{' and '.join(map(repr, names))} resolve to the same OmniWM window; neither can move")

    numbers = set()
    for ws in workspaces:
        problems += [f"workspace entry has unknown key {k!r}" for k in ws if k not in WORKSPACE_KEYS]
        n = ws.get("number")
        if not is_int(n) or n not in LABELLED:
            problems.append(f"workspace {n!r}: only whole numbers 2-10 can be labelled or re-laid-out")
            continue
        if n in numbers:
            problems.append(f"workspace {n} appears twice")
        numbers.add(n)
        key = key_for(n)
        if "label" in ws:
            label = ws["label"]
            if not clean_text(label, MAX_LABEL):
                problems.append(f"workspace {n}: label must be 1-{MAX_LABEL} printable characters, got {label!r}")
            elif not (label == key or (label.startswith(key + " ") and label[len(key) + 1:].strip())):
                problems.append(f"workspace {n}: label {label!r} must be {key!r} or start with {key + ' '!r}")
        if "repos" in ws:
            repos = ws["repos"]
            if not (isinstance(repos, list) and all(isinstance(r, str) and r for r in repos)):
                problems.append(f"workspace {n}: 'repos' must be a list of repo names")
            elif "label" not in ws:
                problems.append(f"workspace {n}: 'repos' needs the 'label' it describes")
        if "layout" in ws and not (isinstance(ws["layout"], str) and ws["layout"] in LAYOUTS):
            problems.append(f"workspace {n}: layout must be dwindle or niri")
    return problems


# ----------------------------------------------------------------- execution

class Run:
    """The report, log entry and failures for one apply or undo."""

    def __init__(self, kind, dry):
        self.dry = dry
        self.report, self.failed = [], []
        self.log = {"kind": kind, "renames": [], "moves": [], "layouts": [], "labels": []}

    def say(self, line):
        self.report.append(line)

    def fail(self, line):
        self.failed.append(line)
        self.report.append("FAILED: " + line)


def displays_now():
    """{display id: workspace number shown on it}, and the focused display."""
    shown, focused = {}, None
    for ws in inventory.omniwm("workspaces")["workspaces"]:
        if ws.get("isVisible"):
            d = (ws.get("display") or {}).get("id")
            shown[d] = ws["number"]
            if ws.get("isCurrent"):
                focused = d
    return shown, focused


def restore_view(view, run):
    """Put every display back on the workspace it showed, focused one last."""
    shown, focused = view
    if run.dry or not shown:
        return
    now, _ = displays_now()
    order = [d for d in shown if d != focused] + ([focused] if focused in shown else [])
    switched = False
    for d in order:
        # Switching another display moves focus, so the focused one is
        # re-selected whenever anything was switched.
        if now.get(d) != shown[d] or (switched and d == focused):
            ok, status = omni("command", "switch-workspace", shown[d])
            switched = True
            if not ok:
                run.fail(f"couldn't return to workspace {shown[d]}: {status}")
    if switched:
        run.say("put your displays back on the workspaces they showed")


def set_layout(n, layout, run):
    if run.dry:
        run.say(f"would set workspace {n} to {layout}")
        return False
    ok, status = omni("command", "switch-workspace", n)
    if not ok:
        # Setting the layout now would change whichever workspace is active.
        run.fail(f"layout {n} -> {layout}: couldn't switch there ({status})")
        return False
    ok, status = omni("command", "set-workspace-layout", layout)
    if not ok:
        run.fail(f"layout {n} -> {layout}: {status}")
        return False
    run.say(f"workspace {n} -> {layout}")
    return True


def set_label(n, label, run):
    if run.dry:
        run.say(f"would label workspace {n} {label!r}")
        return False
    # "" falls back to the digit on 2-5; a bare F-key is written literally.
    ok, status = omni("workspace", "rename", n, "" if label == str(n) else label)
    if not ok:
        run.fail(f"label {n} -> {label!r}: {status}")
        return False
    run.say(f"label {n} -> {label!r}")
    return True


def move(w, dest, run, verb="moved"):
    if run.dry:
        run.say(f"would move {w['name']!r} {w['omniwm_workspace']} -> {dest}")
        return False
    ok, status = omni("window", "move-to-workspace", w["omniwm_id"], dest)
    if not ok:
        run.fail(f"move {w['name']!r} {w['omniwm_workspace']} -> {dest}: {status}")
        return False
    run.say(f"{verb} {w['name']!r} {w['omniwm_workspace']} -> {dest}")
    return True


def unsafe_to_move(w, validated, fresh_windows):
    """Why this window must not move right now, or None."""
    if validated.get("maybe_user_workspace") or validated["omniwm_workspace"] == USER_WORKSPACE:
        return "it wasn't located off workspace 1 when the plan was checked"
    if w.get("maybe_user_workspace") or w["omniwm_workspace"] in (None, USER_WORKSPACE):
        return "it is on (or may be on) workspace 1 now"
    if w["omniwm_match"] != "ok":
        return f"no unique OmniWM match ({w['omniwm_match']})"
    if sum(x["omniwm_id"] == w["omniwm_id"] for x in fresh_windows) > 1:
        return "another cmux window resolves to the same OmniWM window"
    if w.get("floating") or w.get("scratchpad"):
        return "it is floating or in a scratchpad now"
    return None


def guarded(body, run, *args):
    """Run body; a failing cmux/OmniWM query (inventory.run exits) becomes a
    reported failure instead of losing the run's log and view restore."""
    try:
        body(*args, run)
    except SystemExit as exc:
        run.fail(f"stopped part-way: {exc}")


def finish(run, view, decided_ids):
    """Always: restore the view, then log what happened, even partially."""
    try:
        restore_view(view, run)
    except (SystemExit, Exception) as exc:
        run.fail(f"couldn't restore the view: {exc}")
    if run.dry:
        return
    run.log["failed"] = run.failed
    run.log["snapshot"] = sorted(decided_ids)
    if run.log["kind"] == "undo":
        run.log["complete"] = not run.failed
    run.log["ts"] = state.append(run.log)["ts"]


def result(run, done_key, ts):
    out = {"dry_run": True, "would": run.report} if run.dry else {done_key: ts, "report": run.report}
    if run.failed:
        out["failed"] = run.failed
    return (1 if run.failed else 0), out


def apply(plan, dry):
    inv = inventory.collect()
    problems = validate(plan, inv)
    if problems:
        return 2, {"refused": problems}
    run = Run("apply", dry)
    # Recorded every run, changed or not: how later runs learn each
    # workspace's project (inventory.flag via state.label_repos).
    run.log["projects"] = [
        {"workspace": ws["number"], "label": ws["label"], "repos": ws.get("repos", [])}
        for ws in plan.get("workspaces", []) if "label" in ws
    ]
    validated = {w["id"]: w for w in inv["windows"]}
    view = displays_now()
    try:
        guarded(execute, run, plan, validated)
    finally:
        # The snapshot is the windows this run decided on; ones that opened
        # mid-run still read "new" next time.
        finish(run, view, validated)
    return result(run, "applied", run.log.get("ts"))


def execute(plan, validated, run):
    entries = {e["id"]: e for e in plan["windows"]}
    for wid, e in entries.items():
        w, new = validated[wid], e.get("rename")
        if not new or new == w["name"]:
            continue
        if run.dry:
            run.say(f"would rename {w['name']!r} -> {new!r}")
            continue
        cmux("workspace-action", "--workspace", w["cmux_workspace"], "--action", "rename", "--title", new)
        run.log["renames"].append({"id": wid, "cmux_workspace": w["cmux_workspace"], "from": w["name"], "to": new})
        run.say(f"renamed {w['name']!r} -> {new!r}")

    # Renames changed titles, and titles are the join to OmniWM.
    fresh = inventory.collect()["windows"] if run.log["renames"] else list(validated.values())
    now = {w["id"]: w for w in fresh}
    for wid, e in entries.items():
        if e["action"] not in ("move", "review"):
            continue
        dest = REVIEW_WORKSPACE if e["action"] == "review" else e["to"]
        w = now.get(wid)
        if w is None:
            run.fail(f"{validated[wid]['name']!r} closed during the run; not moved")
        elif w["omniwm_workspace"] == dest:
            run.say(f"{w['name']!r} already on {dest}")
        elif (why := unsafe_to_move(w, validated[wid], fresh)):
            run.fail(f"didn't move {w['name']!r}: {why}")
        elif move(w, dest, run):
            run.log["moves"].append({"id": wid, "name": w["name"], "from": w["omniwm_workspace"], "to": dest})

    live = {ws["number"]: ws for ws in inventory.collect()["workspaces"]}
    for ws in plan.get("workspaces", []):
        n, layout = ws["number"], ws.get("layout")
        before = live.get(n, {}).get("layout")
        if not layout or layout == before:
            continue
        if before not in LAYOUTS:
            run.fail(f"layout {n}: current layout unknown ({before!r}); not changed")
        elif set_layout(n, layout, run):
            run.log["layouts"].append({"workspace": n, "from": before, "to": layout})
    for ws in plan.get("workspaces", []):
        n, label = ws["number"], ws.get("label")
        before = live.get(n, {}).get("label") or str(n)
        if label and label != before and set_label(n, label, run):
            run.log["labels"].append({"workspace": n, "from": before, "to": label})


# ---------------------------------------------------------------------- undo

def undo(dry):
    entry = state.last_undoable()
    if entry is None:
        return 1, {"undo": "nothing to undo"}
    run = Run("undo", dry)
    run.log["undoes"] = entry["ts"]
    inv = inventory.collect()
    view = displays_now()
    try:
        guarded(reverse, run, entry, inv)
    finally:
        finish(run, view, {w["id"] for w in inv["windows"]})
    return result(run, "undid", entry["ts"])


def reverse(entry, inv, run):
    """Replay an entry backwards under the same bounds apply enforces. The log
    is a plain file anyone can edit, so it isn't trusted to stay in bounds.
    Steps already reversed (e.g. by an undo that failed part-way) are
    recognised, so a retry finishes the job instead of reporting "changed"."""
    by_id = {w["id"]: w for w in inv["windows"]}
    live = {ws["number"]: ws for ws in inv["workspaces"]}

    def label_now(n):
        return live.get(n, {}).get("label") or str(n)

    for lab in reversed(entry.get("labels", [])):
        n, frm, to = lab.get("workspace"), lab.get("from"), lab.get("to")
        if not (is_int(n) and n in LABELLED and isinstance(frm, str) and isinstance(to, str)):
            run.fail(f"ignored an out-of-bounds label entry: {lab!r}")
        elif label_now(n) == frm:
            run.say(f"label {n} already {frm!r}")
        elif label_now(n) != to:
            run.say(f"left label {n}: changed since (now {label_now(n)!r})")
        elif set_label(n, frm, run):
            run.log["labels"].append({"workspace": n, "from": to, "to": frm})

    for lay in reversed(entry.get("layouts", [])):
        n, frm, to = lay.get("workspace"), lay.get("from"), lay.get("to")
        current = live.get(n, {}).get("layout")
        if not (is_int(n) and n in LABELLED and frm in LAYOUTS and to in LAYOUTS):
            run.fail(f"ignored an out-of-bounds layout entry: {lay!r}")
        elif current == frm:
            run.say(f"layout {n} already {frm}")
        elif current != to:
            run.say(f"left layout {n}: changed since")
        elif set_layout(n, frm, run):
            run.log["layouts"].append({"workspace": n, "from": to, "to": frm})

    moveable = POOL | {REVIEW_WORKSPACE}
    for mv in reversed(entry.get("moves", [])):
        frm, to, w = mv.get("from"), mv.get("to"), by_id.get(mv.get("id"))
        if not (is_int(frm) and is_int(to) and frm in moveable and to in moveable):
            run.fail(f"ignored an out-of-bounds move entry: {mv!r}")
        elif w is None:
            run.say(f"left {mv.get('name', mv.get('id'))!r}: closed since")
        elif w["omniwm_workspace"] == frm:
            run.say(f"{w['name']!r} already back on {frm}")
        elif w["omniwm_workspace"] != to:
            run.say(f"left {w['name']!r}: moved since (now on {w['omniwm_workspace']})")
        elif (why := unsafe_to_move(w, w, inv["windows"])):
            run.fail(f"didn't move {w['name']!r} back: {why}")
        elif move(w, frm, run, verb="moved back"):
            run.log["moves"].append({"id": mv["id"], "name": w["name"], "from": to, "to": frm})

    for rn in reversed(entry.get("renames", [])):
        frm, to, w = rn.get("from"), rn.get("to"), by_id.get(rn.get("id"))
        if not (isinstance(frm, str) and isinstance(to, str)):
            run.fail(f"ignored a malformed rename entry: {rn!r}")
        elif w is None:
            run.say(f"left {to!r}: closed since")
        elif w["name"] == frm:
            run.say(f"{frm!r} already has its old name")
        elif w["name"] != to:
            run.say(f"left {to!r}: renamed since (now {w['name']!r})")
        elif w.get("maybe_user_workspace") or w["omniwm_workspace"] == USER_WORKSPACE:
            run.say(f"left {to!r}: it is on workspace 1 now")
        elif run.dry:
            run.say(f"would rename {to!r} back to {frm!r}")
        else:
            cmux("workspace-action", "--workspace", w["cmux_workspace"], "--action", "rename", "--title", frm)
            run.log["renames"].append({"id": rn["id"], "cmux_workspace": w["cmux_workspace"], "from": to, "to": frm})
            run.say(f"renamed {to!r} back to {frm!r}")


# ---------------------------------------------------------------------- main

def main(argv):
    dry = "--dry-run" in argv
    args = [a for a in argv if a != "--dry-run"]
    if args == ["--undo"]:
        code, out = undo(dry)
    elif len(args) == 1 and not args[0].startswith("--"):
        try:
            if args[0] == "-":
                plan = json.load(sys.stdin)
            else:
                with open(args[0], encoding="utf-8") as f:
                    plan = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            code, out = 2, {"refused": [f"can't read the plan: {exc}"]}
        else:
            code, out = apply(plan, dry)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    json.dump(out, sys.stdout, indent=1, ensure_ascii=False)
    print()
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
