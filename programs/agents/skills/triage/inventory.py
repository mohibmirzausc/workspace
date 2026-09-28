#!/usr/bin/env python3
"""Inventory cmux windows and OmniWM workspaces for the triage skill.

Prints one JSON document with every cmux window (what it is working on, where
it lives in OmniWM) and every OmniWM workspace (label, layout, occupancy).
Read-only: it never moves, renames or closes anything.

The hard part is linking a cmux window to its OmniWM window, which is what a
move has to target. cmux does not expose the macOS window number, so the join
goes through the window TITLE (a cmux window is titled after its selected
workspace). Two traps shape how that is done:

  * OmniWM serves stale titles after a rename, so live titles come from the
    CoreGraphics helper sketchybar already builds (windowId<TAB>title).
  * Titles collide (several windows were once all "✳ hanya"). A title that
    matches more than one window is reported as ambiguous, never guessed.

It also flags windows that need a decision, so placing them does not depend on
a careful read of the table:

  * new: not present at the last triage run (per the log in state.py). New
    windows are the ones nobody has placed yet.
  * misplaced: on a pool workspace whose other windows are a different repo,
    with the reason spelled out.
  * home: the pool workspace that already holds this repo's windows, if it is
    not the one the window is on.
"""

import json
import os
import subprocess
import sys
from collections import Counter

import state

CG_TITLES = os.path.expanduser("~/.config/sketchybar/helpers/window-titles")
SPINNER = set("◐◑◒◓") | {chr(c) for c in range(0x2800, 0x2900)}
MESSAGE_CHARS = 140
USER_WORKSPACE = 1
REVIEW_WORKSPACE = 10
POOL = set(range(2, 10))


def run(*cmd):
    env = dict(os.environ, CMUX_QUIET="1")
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as exc:
        sys.exit(f"inventory: {cmd[0]} failed: {exc}")
    if out.returncode != 0:
        sys.exit(f"inventory: {' '.join(cmd)} exited {out.returncode}: {out.stderr.strip()}")
    return out.stdout


def omniwm(*args):
    doc = json.loads(run("omniwmctl", "query", *args, "--json"))
    if not doc.get("ok"):
        sys.exit(f"inventory: omniwmctl query {args[0]} failed: {doc}")
    return doc["result"]["payload"]


def repo_of(path):
    if not path or not os.path.isdir(path):
        return None
    out = subprocess.run(
        ["git", "-C", path, "rev-parse", "--show-toplevel"],
        capture_output=True, text=True,
    )
    top = out.stdout.strip() if out.returncode == 0 else path
    # A worktree under <repo>/.worktrees/<name> belongs to <repo>.
    parts = top.split(os.sep)
    if ".worktrees" in parts:
        return parts[parts.index(".worktrees") - 1]
    return os.path.basename(top)


def state_of(surface_title):
    t = (surface_title or "").lstrip()
    if not t:
        return "unknown"
    if t[0] in SPINNER:
        return "working"
    if t[0] == "✳":
        return "idle"
    return "shell"


def app_name(w):
    app = w.get("app")
    return app.get("name") if isinstance(app, dict) else app


def live_titles():
    titles = {}
    if os.access(CG_TITLES, os.X_OK):
        out = subprocess.run([CG_TITLES], capture_output=True, text=True)
        for line in out.stdout.splitlines():
            num, _, title = line.partition("\t")
            if num.isdigit():
                titles[int(num)] = title
    return titles


def ws_number(ow_window):
    return (ow_window.get("workspace") or {}).get("number")


def collect():
    tree = json.loads(run("cmux", "--json", "tree", "--all"))
    # Stable window identity: cmux's window UUID. The tree has only refs, so
    # join list-windows to it on the selected workspace, which both report.
    uuid_by_selected = {
        w.get("selected_workspace_id"): w.get("id")
        for w in json.loads(run("cmux", "--json", "list-windows"))
    }
    here = tree.get("caller", {}).get("window_ref")

    ow_windows = omniwm("windows", "--fields", "id,window-id,app,title,workspace,mode,is-scratchpad")["windows"]
    ow_workspaces = omniwm("workspaces")["workspaces"]
    cg = live_titles()

    # title -> OmniWM cmux windows carrying it (live title, else OmniWM's).
    by_title = {}
    for w in ow_windows:
        if app_name(w) != "cmux":
            continue
        title = cg.get(w.get("windowId"), w.get("title") or "")
        by_title.setdefault(title, []).append(w)

    windows = []
    for win in tree["windows"]:
        details = json.loads(run("cmux", "--json", "workspace", "list", "--window", win["ref"]))
        tabs = details["workspaces"]
        sel = next((t for t in tabs if t.get("selected")), tabs[0] if tabs else {})
        tree_ws = next((t for t in win["workspaces"] if t["ref"] == sel.get("ref")), {})
        surfaces = [s for p in tree_ws.get("panes", []) for s in p.get("surfaces", [])]
        focused = next((s for s in surfaces if s.get("selected")), surfaces[0] if surfaces else {})

        name = sel.get("title") or ""
        matches = by_title.get(name, [])
        match = "ok" if len(matches) == 1 else ("ambiguous" if matches else "none")
        ow = matches[0] if match == "ok" else None
        # Every workspace this window could be on. For an unmatched window the
        # answer is "unknown", which must be treated as "maybe workspace 1".
        candidates = sorted({ws_number(m) for m in matches} - {None})
        maybe_user = (not candidates) or USER_WORKSPACE in candidates or \
            (ow is not None and ws_number(ow) is None)

        msg = sel.get("latest_submitted_message") or ""
        windows.append({
            "id": uuid_by_selected.get(win.get("selected_workspace_id")) or win["ref"],
            "cmux_window": win["ref"],
            "cmux_workspace": sel.get("ref"),
            "is_this_session": win["ref"] == here,
            "name": name,
            "named_by_hand_or_agent": bool(sel.get("has_custom_title")),
            "cwd": sel.get("current_directory"),
            "repo": repo_of(sel.get("current_directory")),
            "state": state_of(focused.get("title")),
            "last_message": msg[:MESSAGE_CHARS],
            "last_active": sel.get("latest_submitted_at"),
            "cmux_tab_count": len(tabs),
            "cmux_tabs": [t.get("title") for t in tabs] if len(tabs) > 1 else [],
            "omniwm_match": match,
            "omniwm_id": ow["id"] if ow else None,
            "omniwm_workspace": ws_number(ow) if ow else None,
            "omniwm_candidates": candidates,
            "maybe_user_workspace": maybe_user,
            "floating": bool(ow) and ow.get("mode") not in (None, "tiling"),
            "scratchpad": bool(ow) and bool(ow.get("isScratchpad")),
        })

    others = {}
    for w in ow_windows:
        if app_name(w) != "cmux" and ws_number(w) is not None:
            others.setdefault(ws_number(w), []).append(app_name(w))

    workspaces = [{
        "number": ws["number"],
        "label": ws.get("displayName") if ws.get("displayName") != ws.get("rawName") else None,
        "layout": ws.get("layout"),
        "display": (ws.get("display") or {}).get("name"),
        "tiled": (ws.get("counts") or {}).get("tiled", 0),
        "non_cmux_apps": sorted(set(others.get(ws["number"], []))),
    } for ws in ow_workspaces]

    flag(windows, workspaces)
    current = next((ws["number"] for ws in ow_workspaces if ws.get("isCurrent")), None)
    return {"current_workspace": current, "windows": windows, "workspaces": workspaces}


def flag(windows, workspaces):
    """Add new / misplaced / home to each window, and project_repos to each workspace."""
    seen = state.last_snapshot()
    repos_on = {}
    for w in windows:
        # A window with no repo (its directory is gone) casts no vote.
        if w["omniwm_workspace"] is not None and w["repo"] is not None:
            repos_on.setdefault(w["omniwm_workspace"], []).append(w["repo"])

    # A pool workspace's project is the repo triage labelled it for, else the
    # repo most of its windows are in; a tie has no clear project.
    project = state.label_repos({ws["number"]: ws["label"] for ws in workspaces})
    project = {n: r for n, r in project.items() if n in POOL}
    for n, repos in repos_on.items():
        top = Counter(repos).most_common(2)
        if n in POOL and n not in project and top and (len(top) == 1 or top[0][1] > top[1][1]):
            project[n] = {top[0][0]}
    for ws in workspaces:
        ws["project_repos"] = sorted(project.get(ws["number"], ()))

    for w in windows:
        n, repo = w["omniwm_workspace"], w["repo"]
        w["new"] = None if seen is None else w["id"] not in seen
        # A repo that is the project of several workspaces (the dotfiles repo,
        # split by task) has no single home.
        homes = [m for m, repos in project.items() if repo in repos] if repo else []
        w["home"] = homes[0] if len(homes) == 1 and homes[0] != n else None
        w["misplaced"] = None
        if repo is None or n not in POOL or repo in project.get(n, ()):
            continue
        where = next((ws["label"] for ws in workspaces if ws["number"] == n), None) or str(n)
        if project.get(n):
            reason = f"repo {repo}, but workspace {where!r} is {', '.join(sorted(project[n]))}"
        elif w["home"]:
            # Mixed workspace with no clear project, but this repo clearly
            # lives elsewhere.
            reason = f"repo {repo} on mixed workspace {where!r}"
        else:
            # A mixed workspace of repos with no home: nothing to point at.
            continue
        if w["home"]:
            reason += f"; its repo's windows are on workspace {w['home']}"
        w["misplaced"] = reason


def main():
    json.dump(collect(), sys.stdout, indent=1, ensure_ascii=False)
    print()


if __name__ == "__main__":
    main()
