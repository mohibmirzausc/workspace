#!/usr/bin/env python3
"""Carry out a triage plan, log it, and undo the last one.

  apply.py [--dry-run] PLAN.json     validate and apply a plan (- for stdin)
  apply.py --undo [--dry-run]        reverse the most recent apply
  apply.py --undo --abandon          stop trying to undo it (reach older runs)

Exit status: 0 done, 1 done but something failed (see "failed"), 2 refused.

Plan shape (unknown keys are refused, so a typo can't be silently ignored):
  {"windows": [{"id": "<inventory id>",
                "action": "stay" | "move" | "review" | "skip" | "restore",
                "to": N,             # move: a pool workspace, 2-9 or 11;
                                     # restore: optional, its last_workspace
                "rename": "name",    # optional; not on skip
                "reason": "why"}],   # required to keep a flagged window
   "workspaces": [{"number": N, "label": "F1 dotfiles",
                   "repos": ["workspace"]}]}   # no "layout": all niri

Validation (refusals name the window):
  * coverage: every window in a fresh inventory gets exactly one decision;
  * workspace 1 is untouchable: its windows must be "skip", and so must any
    window that MIGHT be on it (an unmatched window's workspace is unknown);
    skipped windows can't be renamed;
  * moves go to 2-9 or 11 and "review" means 10; only tiled, non-scratchpad
    windows matched to their own OmniWM window move. An unmatched window can
    only stay (rename it now so it matches, and move it next run);
  * "restore" undoes a restart's pile-up (cmux's or OmniWM's): only a window the inventory
    gives a restore_to (see inventory.py), still on its restore_from (the
    pile), uniquely matched and uniquely named, only to that workspace, and
    never with a rename. It is the one way off workspace 1 (when the pile is
    on 1) and the one way onto it (for a window the log last saw on 1, when
    the pile is elsewhere). Anything else on 1 is still "skip";
  * renames are unique across the resulting set of names;
  * a window flagged new or misplaced may stay, but only with a "reason".

Execution: renames, a fresh inventory, then every move is re-checked against
it (still not on workspace 1, still uniquely matched; a restore: still on the
pile, still the same OmniWM window, still uniquely named, still restorable to
the same workspace) right before it happens;
a window already on its destination is "already there", so re-applying a plan
(e.g. after a rolled-back conversation) is harmless (a plan that restored a
window onto 1 is refused instead, until that window is "skip"). Then layouts, labels, and
every display back to the workspace it showed. Every change is logged with its
before value (state.py), even if the run stops part-way, and --undo replays
the log backwards under the same workspace bounds.
"""

import json
import subprocess
import sys
import time

import inventory
import state
from inventory import POOL, REVIEW_WORKSPACE, USER_WORKSPACE

ACTIONS = {"stay", "move", "review", "skip", "restore"}
LAYOUTS = {"dwindle", "niri"}
PLAN_KEYS = {"windows", "workspaces"}
WINDOW_KEYS = {"id", "action", "to", "rename", "reason"}
WORKSPACE_KEYS = {"number", "label", "repos", "layout"}
LABELLED = POOL | {REVIEW_WORKSPACE}
MAX_LABEL = 12
MAX_NAME = 16
SETTLE_TRIES, SETTLE_SECONDS = 6, 0.25


def key_for(n):
    """The key that reaches workspace n: the digit for 2-5, F1-F5 for 6-10,
    and 6 for 11 (the sixth workspace on the external monitor)."""
    if n == 11:
        return "6"
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
    names_now = {}
    for w in inv["windows"]:
        names_now[w["name"]] = names_now.get(w["name"], 0) + 1
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
        final_names.setdefault(new if isinstance(new, str) and new else w["name"], []).append(i)
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
        if action == "restore":
            problems += [f"{name!r}: {why}" for why in unrestorable(w, e, inv, names_now)]
        elif maybe_user and action != "skip":
            why = "is on workspace 1" if w["omniwm_workspace"] == USER_WORKSPACE else \
                f"can't be located ({w['omniwm_match']} match) and might be on workspace 1"
            problems.append(f"{name!r} {why}, which triage never touches: must be 'skip'")
        if action == "skip" and not maybe_user:
            problems.append(f"{name!r}: 'skip' is only for workspace 1; use 'stay'")
        if "to" in e and action not in ("move", "restore"):
            problems.append(f"{name!r}: 'to' only goes with 'move' or 'restore'")
        if action == "move" and not (is_int(e.get("to")) and e["to"] in POOL):
            problems.append(f"{name!r}: move needs 'to' as a whole number 2-9 or 11 (review is its own action), got {e.get('to')!r}")
        if action in ("move", "review", "restore"):
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
        if "rename" in e and e["rename"] != name:
            new = e["rename"]
            if action == "skip":
                problems.append(f"{name!r}: a skipped window can't be renamed")
            elif action == "restore":
                problems.append(f"{name!r}: a restored window can't be renamed (rename it next run)")
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
            problems.append(f"workspace {n!r}: only whole numbers 2-11 can be labelled or re-laid-out")
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
            elif label != key and not ws.get("repos") and n != REVIEW_WORKSPACE:
                problems.append(f"workspace {n}: project label {label!r} needs 'repos' (the repos it stands for)")
        if "repos" in ws:
            repos = ws["repos"]
            if not (isinstance(repos, list) and all(isinstance(r, str) and r for r in repos)):
                problems.append(f"workspace {n}: 'repos' must be a list of repo names")
            elif "label" not in ws:
                problems.append(f"workspace {n}: 'repos' needs the 'label' it describes")
        if "layout" in ws and not (isinstance(ws["layout"], str) and ws["layout"] in LAYOUTS):
            problems.append(f"workspace {n}: layout must be dwindle or niri")
    return problems


WORKSPACES = range(1, 12)  # every workspace a window can be on, 1-11


def restore_dest(w):
    """Where a restore of this window goes: its restore_to, or, for a window
    already back on its last workspace (a re-applied plan), that workspace."""
    if w.get("restore_to") is not None:
        return w["restore_to"]
    return w.get("last_workspace")


def unrestorable(w, e, inv, names_now):
    """Why this window can't be restored off the restart pile (validation)."""
    last, on, dest = w.get("last_workspace"), w["omniwm_workspace"], restore_dest(w)
    skip = ": must be 'skip'" if on == USER_WORKSPACE else ""
    if w["omniwm_match"] != "ok" or not w.get("omniwm_id") or not is_int(on):
        return [f"isn't matched to one OmniWM window ({w['omniwm_match']}), so it can't be restored"]
    if not w["name"] or names_now.get(w["name"], 0) != 1:
        return [f"its name isn't unique, so its last workspace is unknown{skip}"]
    if not (is_int(last) and last in WORKSPACES):
        return [f"its last workspace is {last!r}, not 1-11, so it can't be restored{skip}"]
    if w.get("restore_to") is not None:
        frm = w.get("restore_from")
        # The inventory's own invariant, checked: restore_to is its last
        # workspace and restore_from is where it is, which is elsewhere.
        if not (is_int(dest) and dest == last and is_int(frm) and frm == on and frm != dest):
            return [f"its restore_to {dest!r} / restore_from {frm!r} don't fit where it is ({on}) "
                    f"and its last workspace ({last}){skip}"]
    elif on == last == USER_WORKSPACE:
        return [f"its last workspace is 1, where it is now{skip}"]
    elif on != last:
        pile = inv.get("restart_workspace") if inv.get("restart") is True else None
        if pile is None:
            why = "'restore' is only for after a cmux or OmniWM restart, and the inventory doesn't report one"
        elif on != pile:
            why = f"'restore' only moves windows off the restart pile on workspace {pile}; this one is on {on}"
        elif inv.get("restart_kind") == "cmux":
            why = f"it kept its id since the last run, so it was put on {pile} by hand, not by a restart"
        else:
            why = f"the inventory gives it no restore_to, so it isn't one the restart moved onto {pile}"
        return [why + skip]
    # else: already back on its last workspace (2-11): a re-applied plan.
    if "to" in e and not (is_int(e["to"]) and e["to"] == last):
        return [f"'restore' goes back to its last workspace {last}, not {e['to']!r} (leave 'to' out)"]
    return []


# ----------------------------------------------------------------- execution

class Run:
    """The report, log entry and failures for one apply or undo."""

    def __init__(self, kind, dry):
        self.dry = dry
        self.report, self.failed, self.rejected = [], [], []
        self.log = {"kind": kind, "renames": [], "moves": [], "restores": [], "layouts": [], "labels": []}
        # {name: (workspace, pile)} for windows on the pile only because of a
        # restart: their placement keeps the workspace they belong on, while
        # they are still on the pile (see state.py).
        self.carry = {}

    def say(self, line):
        self.report.append(line)

    def fail(self, line):
        self.failed.append(line)
        self.report.append("FAILED: " + line)

    def reject(self, line):
        """A step that can never succeed (a malformed or out-of-bounds log
        entry): reported, but it doesn't keep an undo from completing, or one
        bad entry would block every older undo forever."""
        self.rejected.append(line)
        self.report.append("IGNORED: " + line)


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
    now, now_focused = displays_now()
    order = [d for d in shown if d != focused] + ([focused] if focused in shown else [])
    switched = False
    for d in order:
        # Switching a display focuses it, so the originally focused display is
        # re-selected if anything was switched or focus moved (set_layout
        # focuses the display of the workspace it re-lays-out).
        if now.get(d) != shown[d] or (d == focused and (switched or now_focused != focused)):
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
    shown, focused = displays_now() if ok else ({}, None)
    if not ok or shown.get(focused) != n:
        # set-workspace-layout acts on whichever workspace is active, so it
        # only runs once workspace n is confirmed to be the active one.
        run.fail(f"layout {n} -> {layout}: couldn't switch there ({status if not ok else 'not active after switching'})")
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
    # "" falls back to the digit on 2-5; a bare F-key, or "6" on 11, is
    # written literally.
    ok, status = omni("workspace", "rename", n, "" if label == str(n) else label)
    if not ok:
        run.fail(f"label {n} -> {label!r}: {status}")
        return False
    run.say(f"label {n} -> {label!r}")
    return True


def move(w, dest, run, verb="moved"):
    if run.dry:
        run.say(f"would {'restore' if verb == 'restored' else 'move'} {w['name']!r} {w['omniwm_workspace']} -> {dest}")
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
    if w["omniwm_id"] != validated["omniwm_id"]:
        # Its title now matches a different OmniWM window than when the plan
        # was checked (e.g. two windows swapped names and titles lag).
        return "its OmniWM window changed since the plan was checked"
    if sum(x["omniwm_id"] == w["omniwm_id"] for x in fresh_windows) > 1:
        return "another cmux window resolves to the same OmniWM window"
    if w.get("floating") or w.get("scratchpad"):
        return "it is floating or in a scratchpad now"
    return None


def unsafe_to_restore(w, validated, dest, fresh_windows):
    """Why this window must not be restored off the restart pile right now, or None."""
    frm = validated.get("restore_from")
    if (validated.get("restore_to") is None or not is_int(frm) or validated["omniwm_workspace"] != frm
            or validated["omniwm_match"] != "ok"):
        return "it wasn't uniquely located on the restart pile when the plan was checked"
    if w["omniwm_match"] != "ok" or w["omniwm_workspace"] != frm:
        return f"it isn't uniquely located on workspace {frm} now ({w['omniwm_match']} match, on {w['omniwm_workspace']})"
    if w["omniwm_id"] != validated["omniwm_id"]:
        return "its OmniWM window changed since the plan was checked"
    if sum(x["name"] == w["name"] for x in fresh_windows) > 1:
        return "another window has its name now"
    if sum(x["omniwm_id"] == w["omniwm_id"] for x in fresh_windows) > 1:
        return "another cmux window resolves to the same OmniWM window"
    if w.get("restore_to") != dest or w.get("restore_from") != frm:
        return (f"it isn't restorable to {dest} now (restore_to {w.get('restore_to')!r}, "
                f"restore_from {w.get('restore_from')!r})")
    if w.get("floating") or w.get("scratchpad"):
        return "it is floating or in a scratchpad now"
    return None


def unsafe_to_unrestore(w, windows):
    """Why a restored window must not be moved back to its pile right now, or
    None. The caller has checked it is uniquely matched and still where the
    restore put it."""
    if sum(x["name"] == w["name"] for x in windows) > 1:
        return "another window has its name now"
    if sum(x["omniwm_id"] == w["omniwm_id"] for x in windows) > 1:
        return "another cmux window resolves to the same OmniWM window"
    if w.get("floating") or w.get("scratchpad"):
        return "it is floating or in a scratchpad now"
    return None


def placements(run, windows):
    """Every cmux window's workspace after the run, for restart recovery."""
    before = state.last_placements()
    names = [w["name"] for w in windows]
    out = []
    for w in windows:
        p = {"name": w["name"], "workspace": w["omniwm_workspace"], "repo": w.get("repo")}
        unique = names.count(w["name"]) == 1
        carry = run.carry.get(w["name"]) if unique else None
        if carry and w["omniwm_workspace"] == carry[1]:
            # Still on the pile: record where it belongs, and where it's stuck.
            p.update(workspace=carry[0], carried=True, pile=carry[1], id=w["id"])
        elif w["omniwm_workspace"] is None and unique and w["name"] in before:
            # Can't be located right now (e.g. its title lags): keep what the
            # log knew rather than forget it.
            old = before[w["name"]]
            p.update(workspace=old["workspace"], unverified=True,
                     **({"carried": True, "pile": old["pile"], **({"id": old["id"]} if old["id"] else {})}
                        if old["carried"] else {}))
        out.append(p)
    return out


def guarded(body, run, *args):
    """Run body; a failing cmux/OmniWM query (inventory.run exits) becomes a
    reported failure instead of losing the run's log and view restore."""
    try:
        body(*args, run)
    except SystemExit as exc:
        run.fail(f"stopped part-way: {exc}")
    except Exception as exc:  # still log and restore, and report as JSON
        run.fail(f"stopped part-way: {type(exc).__name__}: {exc}")


def finish(run, view, decided_ids):
    """Always: restore the view, then log what happened, even partially."""
    try:
        restore_view(view, run)
    except (SystemExit, Exception) as exc:
        run.fail(f"couldn't restore the view: {exc}")
    if run.dry:
        return
    try:
        after = inventory.collect()
        run.log["placements"] = placements(run, after["windows"])
        # Which OmniWM this run saw, so the next one can tell it restarted
        # (state.last_omniwm). From the same inventory as the placements.
        run.log["omniwm"] = after.get("omniwm_instance")
    except (SystemExit, Exception) as exc:
        # No placements: the next run falls back to the last entry that has them.
        run.fail(f"couldn't record where windows are: {exc}")
    run.log["failed"] = run.failed
    if run.rejected:
        run.log["ignored"] = run.rejected
    if decided_ids is not None:
        run.log["snapshot"] = sorted(decided_ids)
    if run.log["kind"] == "undo":
        run.log["complete"] = not run.failed
    run.log["ts"] = state.append(run.log)["ts"]


def result(run, done_key, ts):
    out = {"dry_run": True, "would": run.report} if run.dry else {done_key: ts, "report": run.report}
    if run.failed:
        out["failed"] = run.failed
    if run.rejected:
        out["ignored"] = run.rejected
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
    # An approved restore that doesn't happen must not forget where the window
    # goes (see state.py). A declined one (the window was skipped) is forgotten.
    run.carry = {validated[e["id"]]["name"]: (validated[e["id"]]["restore_to"], validated[e["id"]]["restore_from"])
                 for e in plan["windows"] if e["action"] == "restore"
                 and validated[e["id"]].get("restore_to") is not None}
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

    # Renames changed titles, and titles are the join to OmniWM. Window titles
    # can lag a cmux rename briefly, so poll until the renamed windows match.
    # Moves are re-checked against a fresh inventory, renames or not.
    fresh = list(validated.values())
    if run.log["renames"]:
        renamed = {r["id"] for r in run.log["renames"]}
        for attempt in range(SETTLE_TRIES):
            fresh = inventory.collect()["windows"]
            if all(w["omniwm_match"] == "ok" for w in fresh if w["id"] in renamed):
                break
            time.sleep(SETTLE_SECONDS)
    elif any(e["action"] in ("move", "review", "restore") for e in entries.values()):
        fresh = inventory.collect()["windows"]
    now = {w["id"]: w for w in fresh}
    for wid, e in entries.items():
        if e["action"] == "restore":
            dest = restore_dest(validated[wid])
            w = now.get(wid)
            if w is None:
                run.fail(f"{validated[wid]['name']!r} closed during the run; not restored")
            elif w["omniwm_workspace"] == dest and w["omniwm_match"] == "ok":
                run.say(f"{w['name']!r} already on {dest}")
            elif (why := unsafe_to_restore(w, validated[wid], dest, fresh)):
                run.fail(f"didn't restore {w['name']!r}: {why}")
            elif move(w, dest, run, verb="restored"):
                run.log["restores"].append({"id": wid, "name": w["name"], "from": w["omniwm_workspace"], "to": dest})
            continue
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

def abandon(dry):
    """Give up on undoing the most recent run (e.g. its undo keeps failing for
    a reason that won't clear), so --undo can reach older runs. Changes
    nothing on screen."""
    entry = state.last_undoable()
    if entry is None:
        return 0, {"undo": "nothing to undo"}
    if dry:
        return 0, {"dry_run": True, "would": [f"stop trying to undo the run from {entry['ts']}"]}
    state.append({"kind": "undo", "undoes": entry["ts"], "complete": True, "abandoned": True,
                  "renames": [], "moves": [], "restores": [], "layouts": [], "labels": [], "failed": []})
    return 0, {"abandoned": entry["ts"]}


def undo(dry):
    entry = state.last_undoable()
    if entry is None:
        return 0, {"undo": "nothing to undo"}
    run = Run("undo", dry)
    run.log["undoes"] = entry["ts"]
    inv = inventory.collect()
    view = displays_now()
    try:
        guarded(reverse, run, entry, inv)
    finally:
        # No snapshot: undoing a run should leave its windows reading "new"
        # again, as they did before it (state.last_snapshot skips undone runs).
        finish(run, view, None)
    return result(run, "undid", entry["ts"])


def placed_after(entry, name, n):
    """Whether an entry's own placements put the window called name on
    workspace n (for real, not carried) when that run ended."""
    placements = entry.get("placements")
    if not isinstance(name, str) or not name or not isinstance(placements, list):
        return False
    mine = [p for p in placements if isinstance(p, dict) and p.get("name") == name]
    return (len(mine) == 1 and is_int(mine[0].get("workspace")) and mine[0]["workspace"] == n
            and not mine[0].get("carried"))


def reverse(entry, inv, run):
    """Replay an entry backwards under the same bounds apply enforces. The log
    is a plain file anyone can edit, so it isn't trusted to stay in bounds.
    Steps already reversed (e.g. by an undo that failed part-way) are
    recognised, so a retry finishes the job instead of reporting "changed"."""
    by_id = {w["id"]: w for w in inv["windows"]}
    live = {ws["number"]: ws for ws in inv["workspaces"]}

    def label_now(n):
        return live.get(n, {}).get("label") or str(n)

    def items(key):
        """The entry's list for key, keeping only well-formed objects."""
        value = entry.get(key, [])
        if not isinstance(value, list):
            run.reject(f"malformed {key!r} in the log")
            return []
        good = [x for x in value if isinstance(x, dict)]
        if len(good) != len(value):
            run.reject(f"{len(value) - len(good)} malformed {key!r} entries in the log")
        return good

    names_now = {}
    for x in inv["windows"]:
        names_now.setdefault(x["name"], []).append(x["id"])
    # Windows still on a restart's pile: undoing something else mustn't
    # forget where they belong.
    run.carry = {x["name"]: (x["restore_to"], x["restore_from"]) for x in inv["windows"]
                 if x.get("restore_to") is not None}

    for lab in reversed(items("labels")):
        n, frm, to = lab.get("workspace"), lab.get("from"), lab.get("to")
        if not (is_int(n) and n in LABELLED and isinstance(frm, str) and isinstance(to, str)):
            run.reject(f"out-of-bounds label entry: {lab!r}")
        elif label_now(n) == frm:
            run.say(f"label {n} already {frm!r}")
        elif label_now(n) != to:
            run.say(f"left label {n}: changed since (now {label_now(n)!r})")
        elif set_label(n, frm, run):
            run.log["labels"].append({"workspace": n, "from": to, "to": frm})

    for lay in reversed(items("layouts")):
        n, frm, to = lay.get("workspace"), lay.get("from"), lay.get("to")
        if not (is_int(n) and n in LABELLED and isinstance(frm, str) and isinstance(to, str)
                and frm in LAYOUTS and to in LAYOUTS):
            run.reject(f"out-of-bounds layout entry: {lay!r}")
            continue
        current = live.get(n, {}).get("layout")
        if current == frm:
            run.say(f"layout {n} already {frm}")
        elif current != to:
            run.say(f"left layout {n}: changed since")
        elif set_layout(n, frm, run):
            run.log["layouts"].append({"workspace": n, "from": to, "to": frm})

    moveable = POOL | {REVIEW_WORKSPACE}
    renamed_from = {rn.get("id"): rn.get("from") for rn in items("renames")}
    for mv in reversed(items("moves")):
        frm, to, wid = mv.get("from"), mv.get("to"), mv.get("id")
        if not (is_int(frm) and is_int(to) and frm in moveable and to in moveable and isinstance(wid, str)):
            run.reject(f"out-of-bounds move entry: {mv!r}")
            continue
        w = by_id.get(wid)
        if w is None:
            run.say(f"left {mv.get('name', mv.get('id'))!r}: closed since")
        elif isinstance(mv.get("name"), str) and w["name"] not in (mv["name"], renamed_from.get(wid)):
            # The id must still be the window it moved (a ref id is reused),
            # under the name it moved with or, if an undo that failed part-way
            # renamed it back already, the one it had before the run.
            run.say(f"left {mv['name']!r}: its id is now {w['name']!r}")
        elif w["omniwm_match"] != "ok":
            # Can't tell where it is (e.g. a new window took its title): not a
            # deliberate skip, so the undo stays retryable.
            run.fail(f"can't locate {w['name']!r} to move it back ({w['omniwm_match']} match)")
        elif w["omniwm_workspace"] == frm:
            run.say(f"{w['name']!r} already back on {frm}")
        elif w["omniwm_workspace"] != to:
            run.say(f"left {w['name']!r}: moved since (now on {w['omniwm_workspace']})")
        elif (why := unsafe_to_move(w, w, inv["windows"])):
            run.fail(f"didn't move {w['name']!r} back: {why}")
        elif move(w, frm, run, verb="moved back"):
            run.log["moves"].append({"id": mv["id"], "name": w["name"], "from": to, "to": frm})

    # A restore is the one move logged from or to workspace 1 (from it when
    # the pile was on 1, to it for a window the log last saw there), so its
    # undo is the one move back into or out of it, and only for windows
    # triage itself restored: from is the pile it took the window off.
    for rs in reversed(items("restores")):
        frm, to, wid = rs.get("from"), rs.get("to"), rs.get("id")
        if not (is_int(frm) and is_int(to) and frm in WORKSPACES and to in WORKSPACES and frm != to
                and isinstance(wid, str)):
            run.reject(f"out-of-bounds restore entry: {rs!r}")
            continue
        w = by_id.get(wid)
        if w is not None and w["name"] != rs.get("name"):
            # The id must still be the window it restored.
            run.say(f"left {rs.get('name', wid)!r}: its id is now {w['name']!r}")
            continue
        if USER_WORKSPACE in (frm, to) and not placed_after(entry, rs.get("name"), to):
            # The undos that change the user's workspace: the run must also
            # have recorded leaving the window where the restore put it, so a
            # lone hand-written restore entry can't move a window off 1 or
            # onto it.
            run.reject(f"restore {'onto' if to == USER_WORKSPACE else 'off'} 1 that the run's placements "
                       f"don't confirm: {rs!r}")
            continue
        if w is not None and names_now.get(w["name"]) == [wid]:
            run.carry[w["name"]] = (to, frm)  # counts only if it ends up on the pile
        if w is None:
            run.say(f"left {rs.get('name', wid)!r}: closed since")
        elif w["omniwm_match"] != "ok":
            run.fail(f"can't locate {w['name']!r} to move it back ({w['omniwm_match']} match)")
        elif w["omniwm_workspace"] == frm:
            run.say(f"{w['name']!r} already back on {frm}")
        elif w["omniwm_workspace"] != to:
            run.say(f"left {w['name']!r}: moved since (now on {w['omniwm_workspace']})")
        elif (why := unsafe_to_unrestore(w, inv["windows"])):
            run.fail(f"didn't move {w['name']!r} back: {why}")
        elif move(w, frm, run, verb="moved back"):
            run.log["restores"].append({"id": wid, "name": w["name"], "from": to, "to": frm})

    for rn in reversed(items("renames")):
        frm, to, wid = rn.get("from"), rn.get("to"), rn.get("id")
        if not (isinstance(frm, str) and isinstance(to, str) and isinstance(wid, str)
                and frm and len(frm) <= 256 and frm.isprintable()):
            run.reject(f"malformed rename entry: {rn!r}")
            continue
        w = by_id.get(wid)
        if w is None:
            run.say(f"left {to!r}: closed since")
        elif w["name"] == frm:
            run.say(f"{frm!r} already has its old name")
        elif w["name"] != to:
            run.say(f"left {to!r}: renamed since (now {w['name']!r})")
        elif w.get("maybe_user_workspace") or w["omniwm_workspace"] == USER_WORKSPACE:
            run.say(f"left {to!r}: it is on workspace 1 now")
        elif [i for i in names_now.get(frm, []) if i != wid]:
            run.say(f"left {to!r}: another window is called {frm!r} now")
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
    elif sorted(args) == ["--abandon", "--undo"]:
        code, out = abandon(dry)
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
