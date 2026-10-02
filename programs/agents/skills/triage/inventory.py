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

And it spots a cmux restart, which piles every window onto one workspace
(whichever the user was on: 1, 7, anything) and gives each a new id (names
survive):

  * last_workspace: where the last triage run left the window, by name; None
    if its name isn't unique now, the log doesn't know it, or the log says
    it was another repo.
  * restart (top level): at least 75% of the cmux windows (and at least 3)
    are on one workspace, the pile, most of those have new ids, and at least
    one of the new ones was left elsewhere by the last run. restart_workspace (top level) is the
    pile's number, or None when there is no restart.
  * restore_to / restore_from: the workspace apply.py may "restore" this
    window to, and the one it takes it from (the pile), or None. Set for a
    window on the pile with a new id whose last_workspace is any other
    workspace (1-11), during a restart; or for a window the log carried (its
    approved restore didn't happen, or an undo put it back), while it is
    still the same window (id) on the pile it was carried from.
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
# 2-9 and 11: 11 was added after 10 (review), on the external monitor.
POOL = set(range(2, 10)) | {11}
# A restart: at least this many cmux windows, at least this share on one
# workspace (the pile), and at least this many of them back from elsewhere.
RESTART_MIN_WINDOWS, RESTART_SHARE, RESTART_MIN_BACK = 3, 0.75, 1


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
        try:
            out = subprocess.run([CG_TITLES], capture_output=True, text=True, errors="replace", timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            return titles  # OmniWM's own (stale) titles are the fallback
        for line in out.stdout.splitlines():
            num, _, title = line.partition("\t")
            if num.isdigit():
                titles[int(num)] = title
    return titles


def ws_number(ow_window):
    return (ow_window.get("workspace") or {}).get("number")


def cmux_by_title(ow_windows, cg):
    """title -> OmniWM cmux windows carrying it (live title, else OmniWM's).

    Shared with ~/.config/cmux/attention.py (programs/cmux/attention.py), which
    uses the same join to say which workspace a waiting session is on.
    """
    by_title = {}
    for w in ow_windows:
        if app_name(w) != "cmux":
            continue
        title = cg.get(w.get("windowId"), w.get("title") or "")
        by_title.setdefault(title, []).append(w)
    return by_title


def match_title(name, by_title):
    """(match, omniwm window or None, candidate workspaces, maybe on 1) for
    the cmux window titled `name`. match is "ok", "ambiguous" or "none"."""
    # An empty name is no identity: it would pair with any untitled window.
    matches = by_title.get(name, []) if name else []
    match = "ok" if len(matches) == 1 else ("ambiguous" if matches else "none")
    ow = matches[0] if match == "ok" else None
    # Every workspace this window could be on. For an unmatched window the
    # answer is "unknown", which must be treated as "maybe workspace 1".
    spots = {ws_number(m) for m in matches}
    candidates = sorted(spots - {None})
    # A candidate with no workspace could be anywhere, including 1.
    maybe_user = (not candidates) or USER_WORKSPACE in candidates or None in spots
    return match, ow, candidates, maybe_user


def collect():
    tree = json.loads(run("cmux", "--json", "tree", "--all"))
    # Stable window identity: cmux's window UUID. The tree has only refs, so
    # join list-windows to it on the selected workspace, which both report.
    uuid_by_selected, seen_keys = {}, set()
    for w in json.loads(run("cmux", "--json", "list-windows")):
        key = w.get("selected_workspace_id")
        if key in seen_keys:  # not unique: no window may take this UUID
            uuid_by_selected.pop(key, None)
        elif key and w.get("id"):
            uuid_by_selected[key] = w["id"]
        seen_keys.add(key)
    here = tree.get("caller", {}).get("window_ref")

    ow_windows = omniwm("windows", "--fields", "id,window-id,app,title,workspace,mode,is-scratchpad")["windows"]
    ow_workspaces = omniwm("workspaces")["workspaces"]
    cg = live_titles()

    by_title = cmux_by_title(ow_windows, cg)

    windows = []
    for win in tree["windows"]:
        details = json.loads(run("cmux", "--json", "workspace", "list", "--window", win["ref"]))
        tabs = details["workspaces"]
        sel = next((t for t in tabs if t.get("selected")), tabs[0] if tabs else {})
        tree_ws = next((t for t in win["workspaces"] if t["ref"] == sel.get("ref")), {})
        surfaces = [s for p in tree_ws.get("panes", []) for s in p.get("surfaces", [])]
        focused = next((s for s in surfaces if s.get("selected")), surfaces[0] if surfaces else {})

        name = sel.get("title") or ""
        match, ow, candidates, maybe_user = match_title(name, by_title)

        msg = sel.get("latest_submitted_message") or ""
        windows.append({
            "id": uuid_by_selected.get(win.get("selected_workspace_id") or "") or win["ref"],
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
    pile = recovery(windows)
    current = next((ws["number"] for ws in ow_workspaces if ws.get("isCurrent")), None)
    return {"current_workspace": current, "restart": pile is not None, "restart_workspace": pile,
            "windows": windows, "workspaces": workspaces}


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


def located(w):
    """The workspace a window is on: its own, or, for a title shared by
    several windows all on one workspace, that one. None if unknown."""
    if w["omniwm_workspace"] is not None:
        return w["omniwm_workspace"]
    candidates = w.get("omniwm_candidates") or []
    # maybe_user_workspace with a lone candidate other than 1 means one of
    # the windows sharing the title has no workspace: it could be anywhere.
    if len(candidates) == 1 and (candidates[0] == USER_WORKSPACE or not w.get("maybe_user_workspace")):
        return candidates[0]
    return None


def recovery(windows):
    """Add last_workspace, restore_to and restore_from to each window; return
    the workspace a cmux restart piled the windows onto, or None if it didn't
    just restart. Call after flag(), which sets "new"."""
    last = state.last_placements()
    names = Counter(w["name"] for w in windows)
    for w in windows:
        p = last.get(w["name"]) if w["name"] and names[w["name"]] == 1 else None
        if p and p["repo"] and w.get("repo") and p["repo"] != w["repo"]:
            p = None  # the name was reused for other work
        w["last_workspace"] = p["workspace"] if p else None
        # Carried: on the pile only because of a restart when the last run
        # ended (see state.py); it counts only while still on that pile, and
        # only for the same window (its id), not a new one reusing the name.
        # Entries from before ids were logged never sent a window to 1.
        same = p and (p["id"] == w["id"] if p["id"] is not None else p["workspace"] != USER_WORKSPACE)
        w["_carried"] = p["pile"] if p and p["carried"] and same else None

    # The pile: the one workspace holding at least RESTART_SHARE of the
    # windows (more than half, so there is at most one).
    spots = Counter(located(w) for w in windows if located(w) is not None)
    pile, count = spots.most_common(1)[0] if spots else (None, 0)
    on_pile = [w for w in windows if pile is not None and located(w) == pile]
    # A restart gives every window a new id, so most of the pile must be new.
    # A window the user dragged onto the pile keeps its id, so it doesn't
    # count (unless the log carried it there: it was on the pile only because
    # of a restart when the last run ended). The windows that live on the
    # pile (often most of them: the pile is the workspace the user was on)
    # are new too, but only the ones the log left elsewhere came back.
    renewed = [w for w in on_pile if w.get("new") is True or w["_carried"] == pile]
    came_back = [w for w in renewed if w["last_workspace"] not in (None, pile)]
    restart = (len(windows) >= RESTART_MIN_WINDOWS
               and count >= RESTART_SHARE * len(windows)
               and 2 * len(renewed) > len(on_pile)
               and len(came_back) >= RESTART_MIN_BACK)
    for w in windows:
        n = w["omniwm_workspace"]
        ok = (w["omniwm_match"] == "ok" and n is not None and w["last_workspace"] not in (None, n)
              and ((restart and n == pile and w in came_back) or w["_carried"] == n))
        w["restore_to"] = w["last_workspace"] if ok else None
        w["restore_from"] = n if ok else None
        del w["_carried"]
    return pile if restart else None


def main():
    json.dump(collect(), sys.stdout, indent=1, ensure_ascii=False)
    print()


if __name__ == "__main__":
    main()
