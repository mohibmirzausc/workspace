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
"""

import json
import os
import subprocess
import sys

CG_TITLES = os.path.expanduser("~/.config/sketchybar/helpers/window-titles")
SPINNER = set("◐◑◒◓") | {chr(c) for c in range(0x2800, 0x2900)}
MESSAGE_CHARS = 140


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


def main():
    tree = json.loads(run("cmux", "--json", "tree", "--all"))
    here = tree.get("caller", {}).get("window_ref")

    ow_windows = omniwm("windows", "--fields", "id,window-id,app,title,workspace")["windows"]
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

        msg = sel.get("latest_submitted_message") or ""
        windows.append({
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
            "omniwm_workspace": ow["workspace"]["number"] if ow else None,
        })

    others = {}
    for w in ow_windows:
        if app_name(w) != "cmux" and w.get("workspace"):
            others.setdefault(w["workspace"]["number"], []).append(app_name(w))

    workspaces = [{
        "number": ws["number"],
        "label": ws.get("displayName") if ws.get("displayName") != ws.get("rawName") else None,
        "layout": ws.get("layout"),
        "display": (ws.get("display") or {}).get("name"),
        "tiled": (ws.get("counts") or {}).get("tiled", 0),
        "non_cmux_apps": sorted(set(others.get(ws["number"], []))),
    } for ws in ow_workspaces]

    json.dump({"windows": windows, "workspaces": workspaces}, sys.stdout, indent=1, ensure_ascii=False)
    print()


if __name__ == "__main__":
    main()
