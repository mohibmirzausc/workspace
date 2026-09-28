#!/usr/bin/env python3
"""Carry out a triage plan, log it, and undo the last one.

  apply.py [--dry-run] PLAN.json     validate and apply a plan (- for stdin)
  apply.py --undo [--dry-run]        reverse the most recent apply

Plan shape:
  {"windows": [{"id": "<inventory id>",
                "action": "stay" | "move" | "review" | "skip",
                "to": N,             # move only: a pool workspace, 2-9
                "rename": "name",    # optional, any action but skip
                "reason": "why"}],
   "workspaces": [{"number": N, "label": "F1 dotfiles",
                   "repos": ["workspace"], "layout": "dwindle"}]}

The plan must give EVERY window in a fresh inventory exactly one decision. A
missing window is refused by name, so a window can't be skipped over by
accident. `skip` is only for workspace 1, which triage never touches, and
workspace 1's windows must be skipped. `review` means workspace 10.

Windows the inventory flags new or misplaced don't have to move, but they
must be considered: a flagged window may "stay" only with a "reason".

Order: renames, re-inventory (titles changed, and titles are the join to
OmniWM), moves, layouts, labels, then back to the workspace the user was on.
A window already on its destination is reported as "already there", not moved
again, so re-running a plan (e.g. after a rolled-back conversation) is harmless.
Every change is appended to the log (state.py) with its before value, which is
what --undo replays in reverse.
"""

import json
import subprocess
import sys

import inventory
import state
from inventory import POOL, REVIEW_WORKSPACE, USER_WORKSPACE

ACTIONS = {"stay", "move", "review", "skip"}
LAYOUTS = {"dwindle", "niri"}
MAX_LABEL = 12


def key_for(n):
    """The key that reaches workspace n: the digit for 2-5, F1-F5 for 6-10."""
    return str(n) if n <= 5 else f"F{n - 5}"


def cmux(*args):
    return inventory.run("cmux", *args)


def omni(*args):
    """Run an omniwmctl command; return (ok, status or error code)."""
    out = subprocess.run(
        ["omniwmctl", "--json", *args], capture_output=True, text=True, timeout=10
    )
    try:
        doc = json.loads(out.stdout)
    except json.JSONDecodeError:
        return False, (out.stderr.strip() or f"exit {out.returncode}")
    return bool(doc.get("ok")), doc.get("status") or doc.get("code") or ""


# ---------------------------------------------------------------- validation

def validate(plan, inv):
    """Return a list of problems; empty means the plan may run."""
    problems = []
    by_id = {w["id"]: w for w in inv["windows"]}
    entries = plan.get("windows")
    if not isinstance(entries, list):
        return ["plan has no 'windows' list"]

    seen = {}
    for e in entries:
        wid = e.get("id")
        if wid in seen:
            problems.append(f"window {wid} appears twice in the plan")
        seen[wid] = e
    missing = [w for i, w in by_id.items() if i not in seen]
    unknown = [i for i in seen if i not in by_id]
    for w in missing:
        problems.append(f"no decision for window {w['name']!r} (id {w['id']}, workspace {w['omniwm_workspace']})")
    for i in unknown:
        problems.append(f"plan names window {i}, which is not open")

    for wid, e in seen.items():
        w = by_id.get(wid)
        if w is None:
            continue
        action, name = e.get("action"), w["name"]
        on_user_ws = w["omniwm_workspace"] == USER_WORKSPACE
        if action not in ACTIONS:
            problems.append(f"{name!r}: unknown action {action!r}")
            continue
        if on_user_ws and action != "skip":
            problems.append(f"{name!r} is on workspace 1, which triage never touches: must be 'skip'")
        if action == "skip" and not on_user_ws:
            problems.append(f"{name!r}: 'skip' is only for workspace 1; use 'stay'")
        if action == "move" and e.get("to") not in POOL:
            problems.append(f"{name!r}: move needs 'to' in 2-9 (review is its own action), got {e.get('to')!r}")
        if action in ("move", "review") and w["omniwm_match"] != "ok" and not e.get("rename"):
            problems.append(f"{name!r}: can't be matched to an OmniWM window ({w['omniwm_match']}); give it a unique 'rename'")
        # New or misplaced windows need not move, but they must be considered:
        # keeping one where it is takes a stated reason, so "stay" is a
        # decision and not an oversight.
        flags = [f for f in ("new", "misplaced") if w.get(f)]
        if flags and action == "stay" and not (e.get("reason") or "").strip():
            problems.append(f"{name!r} is flagged {' and '.join(flags)}: 'stay' is fine but needs a 'reason'")
        rename = e.get("rename")
        if rename is not None and (action == "skip" or not isinstance(rename, str) or not rename.strip() or len(rename) > 16):
            problems.append(f"{name!r}: rename must be 1-16 characters and not on a skipped window")

    for ws in plan.get("workspaces", []):
        n = ws.get("number")
        if n not in POOL | {REVIEW_WORKSPACE}:
            problems.append(f"workspace {n!r}: only 2-10 can be labelled or re-laid-out")
            continue
        label, key = ws.get("label"), key_for(n)
        if label is not None and not (label == key or label.startswith(key + " ")):
            problems.append(f"workspace {n}: label {label!r} must start with its key {key!r}")
        if label is not None and len(label) > MAX_LABEL:
            problems.append(f"workspace {n}: label {label!r} is over {MAX_LABEL} characters")
        if ws.get("layout") is not None and ws["layout"] not in LAYOUTS:
            problems.append(f"workspace {n}: layout must be dwindle or niri")
    return problems


# ----------------------------------------------------------------- execution

def destination(e):
    return REVIEW_WORKSPACE if e["action"] == "review" else e.get("to")


def set_layout(n, layout, report, dry):
    if dry:
        report.append(f"would set workspace {n} to {layout}")
        return True
    omni("command", "switch-workspace", str(n))
    ok, status = omni("command", "set-workspace-layout", layout)
    report.append(f"workspace {n} -> {layout}: {status}")
    return ok


def set_label(n, label, report, dry):
    # "" falls back to the digit on 2-5; a bare key is written literally.
    value = "" if label == str(n) else label
    if dry:
        report.append(f"would label workspace {n} {label!r}")
        return True
    ok, status = omni("workspace", "rename", str(n), value)
    report.append(f"label {n} -> {label!r}: {status}")
    return ok


def return_to(original, report, dry):
    if original is None or dry:
        return
    now = inventory.omniwm("workspaces", "--current")["workspaces"]
    if now and now[0]["number"] != original:
        omni("command", "switch-workspace", str(original))
        report.append(f"returned you to workspace {original}")


def apply(plan, dry):
    inv = inventory.collect()
    problems = validate(plan, inv)
    if problems:
        return 2, {"refused": problems}

    original = inv["current_workspace"]
    entries = {e["id"]: e for e in plan["windows"]}
    by_id = {w["id"]: w for w in inv["windows"]}
    report, log = [], {"kind": "apply", "renames": [], "moves": [], "layouts": [], "labels": []}
    try:
        _execute(plan, entries, by_id, inv, report, log, dry)
    finally:
        # Log whatever changed, even if a command failed part-way (inventory.run
        # exits on failure), so --undo can still reverse the part that happened.
        if not dry and any(log[k] for k in ("renames", "moves", "layouts", "labels")):
            try:
                log["snapshot"] = [w["id"] for w in inventory.collect()["windows"]]
            except SystemExit:
                log["snapshot"] = list(by_id)
            log["ts"] = state.append(log)["ts"]
    return_to(original, report, dry)
    if dry:
        return 0, {"dry_run": True, "would": report}
    if "ts" not in log:
        log["snapshot"] = [w["id"] for w in inventory.collect()["windows"]]
        log["ts"] = state.append(log)["ts"]
    return 0, {"applied": log["ts"], "report": report}


def _execute(plan, entries, by_id, inv, report, log, dry):
    for wid, e in entries.items():
        w, new = by_id[wid], e.get("rename")
        if new and new != w["name"]:
            if dry:
                report.append(f"would rename {w['name']!r} -> {new!r}")
                continue
            cmux("workspace-action", "--workspace", w["cmux_workspace"], "--action", "rename", "--title", new)
            log["renames"].append({"id": wid, "cmux_workspace": w["cmux_workspace"], "from": w["name"], "to": new})
            report.append(f"renamed {w['name']!r} -> {new!r}")

    if log["renames"]:
        inv = inventory.collect()
        by_id = {w["id"]: w for w in inv["windows"]}

    for wid, e in entries.items():
        dest = destination(e)
        if dest is None:
            continue
        w = by_id.get(wid)
        if w is None:
            report.append(f"skipped {wid}: closed during the run")
            continue
        if w["omniwm_workspace"] == dest:
            report.append(f"{w['name']!r} already on {dest}")
            continue
        if w["omniwm_match"] != "ok":
            report.append(f"skipped {w['name']!r}: still no unique OmniWM match ({w['omniwm_match']})")
            continue
        if dry:
            report.append(f"would move {w['name']!r} {w['omniwm_workspace']} -> {dest}")
            continue
        ok, status = omni("window", "move-to-workspace", w["omniwm_id"], str(dest))
        if ok:
            log["moves"].append({"id": wid, "name": w["name"], "from": w["omniwm_workspace"], "to": dest})
        report.append(f"moved {w['name']!r} {w['omniwm_workspace']} -> {dest}: {status}")

    live = {ws["number"]: ws for ws in inventory.collect()["workspaces"]} if not dry else \
        {ws["number"]: ws for ws in inv["workspaces"]}
    for ws in plan.get("workspaces", []):
        n, layout = ws["number"], ws.get("layout")
        before = live.get(n, {}).get("layout")
        if layout and layout != before and set_layout(n, layout, report, dry) and not dry:
            log["layouts"].append({"workspace": n, "from": before, "to": layout})
    for ws in plan.get("workspaces", []):
        n, label = ws["number"], ws.get("label")
        before = live.get(n, {}).get("label") or str(n)
        if label and label != before and set_label(n, label, report, dry) and not dry:
            log["labels"].append({"workspace": n, "from": before, "to": label, "repos": ws.get("repos", [])})


def undo(dry):
    entry = state.last_undoable()
    if entry is None:
        return 1, {"undo": "nothing to undo"}
    inv = inventory.collect()
    original = inv["current_workspace"]
    by_id = {w["id"]: w for w in inv["windows"]}
    report, log = [], {"kind": "undo", "undoes": entry["ts"], "renames": [], "moves": [], "layouts": [], "labels": []}

    live = {ws["number"]: ws for ws in inv["workspaces"]}
    for lab in reversed(entry.get("labels", [])):
        n = lab["workspace"]
        if (live.get(n, {}).get("label") or str(n)) != lab["to"]:
            report.append(f"left label {n}: changed since ({live.get(n, {}).get('label')!r})")
        elif set_label(n, lab["from"], report, dry) and not dry:
            log["labels"].append({"workspace": n, "from": lab["to"], "to": lab["from"]})
    for lay in reversed(entry.get("layouts", [])):
        n = lay["workspace"]
        if live.get(n, {}).get("layout") != lay["to"]:
            report.append(f"left layout {n}: changed since")
        elif set_layout(n, lay["from"], report, dry) and not dry:
            log["layouts"].append({"workspace": n, "from": lay["to"], "to": lay["from"]})
    for mv in reversed(entry.get("moves", [])):
        w = by_id.get(mv["id"])
        if w is None:
            report.append(f"left {mv['name']!r}: closed since")
        elif w["omniwm_workspace"] != mv["to"]:
            report.append(f"left {w['name']!r}: moved since (now on {w['omniwm_workspace']})")
        elif w["omniwm_match"] != "ok":
            report.append(f"left {w['name']!r}: no unique OmniWM match now")
        elif dry:
            report.append(f"would move {w['name']!r} back {mv['to']} -> {mv['from']}")
        else:
            ok, status = omni("window", "move-to-workspace", w["omniwm_id"], str(mv["from"]))
            if ok:
                log["moves"].append({"id": mv["id"], "name": w["name"], "from": mv["to"], "to": mv["from"]})
            report.append(f"moved {w['name']!r} back {mv['to']} -> {mv['from']}: {status}")
    for rn in reversed(entry.get("renames", [])):
        w = by_id.get(rn["id"])
        if w is None or w["name"] != rn["to"]:
            report.append(f"left name of {rn['to']!r}: renamed or closed since")
        elif dry:
            report.append(f"would rename {rn['to']!r} back to {rn['from']!r}")
        else:
            cmux("workspace-action", "--workspace", w["cmux_workspace"], "--action", "rename", "--title", rn["from"])
            log["renames"].append({"id": rn["id"], "cmux_workspace": w["cmux_workspace"], "from": rn["to"], "to": rn["from"]})
            report.append(f"renamed {rn['to']!r} back to {rn['from']!r}")

    return_to(original, report, dry)
    if dry:
        return 0, {"dry_run": True, "would": report}
    log["snapshot"] = [w["id"] for w in inventory.collect()["windows"]]
    state.append(log)
    return 0, {"undid": entry["ts"], "report": report}


def main(argv):
    dry = "--dry-run" in argv
    args = [a for a in argv if a != "--dry-run"]
    if args == ["--undo"]:
        code, result = undo(dry)
    elif len(args) == 1:
        src = sys.stdin if args[0] == "-" else open(args[0], encoding="utf-8")
        with src:
            plan = json.load(src)
        code, result = apply(plan, dry)
    else:
        sys.exit(__doc__)
    json.dump(result, sys.stdout, indent=1, ensure_ascii=False)
    print()
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
