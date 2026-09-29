"""Tests for the triage scripts' pure logic: flags, plan validation, the log.

Run: python3 test_triage.py   (no cmux or OmniWM needed; nothing is moved)
"""

import os
import shutil
import tempfile
import unittest

os.environ["TRIAGE_STATE_DIR"] = tempfile.mkdtemp(prefix="triage-test-")

import apply  # noqa: E402
import inventory  # noqa: E402
import state  # noqa: E402


def win(wid, repo, ws, **kw):
    return {"id": wid, "name": wid, "repo": repo, "omniwm_workspace": ws,
            "omniwm_match": "ok", "omniwm_id": f"ow_{wid}", "cmux_workspace": f"workspace:{wid}", **kw}


def workspaces():
    return [{"number": n, "label": label, "layout": "dwindle"} for n, label in
            [(1, "💼"), (2, "2 alloc"), (3, "3 agents"), (4, "4 imogen"), (6, "F1 dotfiles"), (10, "F5 review")]]


def desktop():
    """Today's desktop: 'allocmisc' is the internal-allocations window that
    landed on the dotfiles workspace and was nearly missed."""
    return [win("omni", "workspace", 6), win("allocmisc", "internal-allocations", 6),
            win("alloc", "internal-allocations", 2), win("story", "internal-allocations", 2),
            win("bs", "imogen-a", 4), win("bk", "imogen-b", 4),
            win("agent", "workspace", 3), win("pi", "workspace", 3),
            win("tmp", "tmp", 10), win("jan", "release", 1)]


def reset_log():
    shutil.rmtree(state.state_dir(), ignore_errors=True)


class FlagTests(unittest.TestCase):
    def setUp(self):
        reset_log()

    def flagged(self, windows=None):
        windows = windows or desktop()
        inventory.flag(windows, workspaces())
        return {w["id"]: w for w in windows}

    def test_first_run_flags_the_mixed_workspace(self):
        w = self.flagged()
        self.assertIsNone(w["allocmisc"]["new"])  # no log yet
        self.assertEqual(w["allocmisc"]["home"], 2)
        self.assertIn("internal-allocations", w["allocmisc"]["misplaced"])

    def test_labelled_workspaces_pin_the_miss_exactly(self):
        state.append({"kind": "apply", "snapshot": ["omni", "alloc", "story", "bs", "bk", "agent", "pi", "tmp", "jan"],
                      "projects": [{"workspace": 2, "label": "2 alloc", "repos": ["internal-allocations"]},
                                   {"workspace": 3, "label": "3 agents", "repos": ["workspace"]},
                                   {"workspace": 4, "label": "4 imogen", "repos": ["imogen-a", "imogen-b"]},
                                   {"workspace": 6, "label": "F1 dotfiles", "repos": ["workspace"]}]})
        w = self.flagged()
        self.assertTrue(w["allocmisc"]["new"])
        self.assertIn("its repo's windows are on workspace 2", w["allocmisc"]["misplaced"])
        flagged = {i for i, x in w.items() if x["misplaced"]}
        self.assertEqual(flagged, {"allocmisc"})  # nothing else, incl. the two-repo imogen project
        self.assertFalse(w["omni"]["new"])
        self.assertIsNone(w["omni"]["home"])  # dotfiles repo owns 3 and 6: no single home

    def test_hand_edited_label_drops_the_recorded_repo(self):
        state.append({"kind": "apply", "projects": [{"workspace": 6, "label": "F1 dotfiles", "repos": ["workspace"]}]})
        wss = workspaces()
        next(ws for ws in wss if ws["number"] == 6)["label"] = "F1 renamed"
        self.assertEqual(state.label_repos({ws["number"]: ws["label"] for ws in wss}), {})

    def test_windows_without_a_repo_neither_vote_nor_crash(self):
        windows = [win("a", None, 5), win("b", None, 5), win("c", "x", 5), win("d", None, 3), win("e", "y", 3)]
        w = self.flagged(windows)
        self.assertTrue(all(x["home"] is None for x in w.values()))
        self.assertIsNone(w["d"]["misplaced"])

    def test_user_and_review_workspaces_are_never_misplaced(self):
        w = self.flagged()
        self.assertIsNone(w["jan"]["misplaced"])
        self.assertIsNone(w["tmp"]["misplaced"])


class ValidateTests(unittest.TestCase):
    def setUp(self):
        reset_log()
        windows = desktop()
        inventory.flag(windows, workspaces())
        self.inv = {"current_workspace": 6, "windows": windows, "workspaces": workspaces()}

    def plan(self, **overrides):
        entries = []
        for w in self.inv["windows"]:
            e = {"id": w["id"], "action": "skip" if w["omniwm_workspace"] == 1 else "stay"}
            if w.get("misplaced") or w.get("new"):
                e["reason"] = "considered"
            e.update(overrides.get(w["id"], {}))
            entries.append(e)
        return {"windows": entries}

    def test_complete_plan_passes(self):
        self.assertEqual(apply.validate(self.plan(), self.inv), [])

    def test_missing_window_is_refused_by_name(self):
        plan = self.plan()
        plan["windows"] = [e for e in plan["windows"] if e["id"] != "allocmisc"]
        problems = apply.validate(plan, self.inv)
        self.assertTrue(any("no decision for window 'allocmisc'" in p for p in problems), problems)

    def test_duplicate_and_unknown_windows_are_refused(self):
        plan = self.plan()
        plan["windows"].append({"id": "alloc", "action": "stay"})
        plan["windows"].append({"id": "ghost", "action": "stay"})
        problems = apply.validate(plan, self.inv)
        self.assertTrue(any("appears twice" in p for p in problems))
        self.assertTrue(any("ghost" in p and "not open" in p for p in problems))

    def test_flagged_window_may_stay_only_with_a_reason(self):
        plan = self.plan(allocmisc={"action": "stay", "reason": ""})
        self.assertTrue(any("'allocmisc' is flagged" in p for p in apply.validate(plan, self.inv)))
        plan = self.plan(allocmisc={"action": "stay", "reason": "scratch work, keep near dotfiles"})
        self.assertEqual(apply.validate(plan, self.inv), [])

    def test_workspace_one_is_untouchable(self):
        self.assertTrue(apply.validate(self.plan(jan={"action": "move", "to": 5}), self.inv))
        self.assertTrue(apply.validate(self.plan(omni={"action": "skip"}), self.inv))

    def test_moves_stay_in_the_pool(self):
        for to in (1, 10, 11, None, "2"):
            problems = apply.validate(self.plan(allocmisc={"action": "move", "to": to}), self.inv)
            self.assertTrue(problems, f"to={to!r} should be refused")
        self.assertEqual(apply.validate(self.plan(allocmisc={"action": "move", "to": 2}), self.inv), [])

    def test_unmatched_window_can_only_stay(self):
        pi = next(w for w in self.inv["windows"] if w["id"] == "pi")
        pi.update(omniwm_match="ambiguous", omniwm_workspace=None, omniwm_id=None,
                  omniwm_candidates=[3], maybe_user_workspace=False)
        self.assertTrue(apply.validate(self.plan(pi={"action": "review", "rename": "pi shell"}), self.inv))
        self.assertEqual(apply.validate(self.plan(pi={"action": "stay", "rename": "pi shell"}), self.inv), [])

    def test_window_that_might_be_on_workspace_one_must_be_skipped(self):
        pi = next(w for w in self.inv["windows"] if w["id"] == "pi")
        pi.update(omniwm_match="ambiguous", omniwm_workspace=None, omniwm_id=None,
                  omniwm_candidates=[1, 3], maybe_user_workspace=True)
        for e in ({"action": "move", "to": 5, "rename": "pi x"}, {"action": "stay"},
                  {"action": "stay", "rename": "pi x"}, {"action": "skip", "rename": "pi x"}):
            self.assertTrue(apply.validate(self.plan(pi=e), self.inv), e)
        self.assertEqual(apply.validate(self.plan(pi={"action": "skip"}), self.inv), [])

    def test_to_is_only_for_move(self):
        for e in ({"action": "stay", "to": 1}, {"action": "review", "to": 4}):
            self.assertTrue(apply.validate(self.plan(omni=e), self.inv), e)
        self.assertTrue(apply.validate(self.plan(jan={"action": "skip", "to": 4}), self.inv))

    def test_numbers_must_be_real_ints(self):
        for to in (2.0, True, "2"):
            self.assertTrue(apply.validate(self.plan(omni={"action": "move", "to": to}), self.inv), to)
        plan = self.plan()
        plan["workspaces"] = [{"number": 6.0, "label": "F1 x"}]
        self.assertTrue(apply.validate(plan, self.inv))

    def test_renames_stay_unique(self):
        self.assertTrue(apply.validate(self.plan(omni={"action": "stay", "rename": "alloc"}), self.inv))
        self.assertTrue(apply.validate(self.plan(omni={"action": "stay", "rename": "same"},
                                                 pi={"action": "stay", "rename": "same"}), self.inv))
        for bad in ("a\nb", " padded", "", 7):
            self.assertTrue(apply.validate(self.plan(omni={"action": "stay", "rename": bad}), self.inv), bad)

    def test_floating_and_scratchpad_windows_never_move(self):
        next(w for w in self.inv["windows"] if w["id"] == "pi")["scratchpad"] = True
        self.assertTrue(apply.validate(self.plan(pi={"action": "review"}), self.inv))

    def test_shared_omniwm_window_cannot_move(self):
        for i in ("agent", "pi"):
            next(w for w in self.inv["windows"] if w["id"] == i)["omniwm_id"] = "ow_same"
        self.assertTrue(apply.validate(self.plan(agent={"action": "review"}, pi={"action": "review"}), self.inv))

    def test_malformed_plans_are_refused_not_crashed(self):
        for plan in ([], {"windows": "x"}, {"windows": ["x"]}, {"windows": [{"id": ["x"]}]},
                     {"windows": [], "workspaces": {}}, {"windows": [], "close": ["omni"]}):
            self.assertTrue(apply.validate(plan, self.inv), plan)
        plan = self.plan()
        for ws in ({"number": 2, "label": 5}, {"number": [2]}, {"number": 2, "layout": ["x"]},
                   {"number": 2, "label": "2 x", "repos": [["x"]]}, {"number": 2, "label": "2 "}):
            plan["workspaces"] = [ws]
            self.assertTrue(apply.validate(plan, self.inv), ws)
        plan["workspaces"] = [{"number": 2, "label": "2 a"}, {"number": 2, "label": "2 b"}]
        self.assertTrue(apply.validate(plan, self.inv))

    def test_labels_carry_their_key(self):
        for n, label, ok in [(2, "2 alloc", True), (6, "F1 dotfiles", True), (10, "F5 review", True),
                             (6, "dotfiles", False), (6, "6 dotfiles", False), (2, "F1 alloc", False),
                             (7, "F2 a-very-long-name", False), (1, "1 mine", False)]:
            plan = self.plan()
            plan["workspaces"] = [{"number": n, "label": label, "repos": ["x"]}]
            self.assertEqual(apply.validate(plan, self.inv) == [], ok, f"{n} {label!r}")

    def test_bad_rename_and_layout_are_refused(self):
        self.assertTrue(apply.validate(self.plan(omni={"action": "stay", "rename": "x" * 17}), self.inv))
        plan = self.plan()
        plan["workspaces"] = [{"number": 6, "layout": "grid"}]
        self.assertTrue(apply.validate(plan, self.inv))


class LogTests(unittest.TestCase):
    def setUp(self):
        reset_log()

    def test_undo_walks_back_one_apply_at_a_time(self):
        a = state.append({"kind": "apply", "moves": [1]})
        b = state.append({"kind": "apply", "moves": [2]})
        self.assertEqual(state.last_undoable()["ts"], b["ts"])
        state.append({"kind": "undo", "undoes": b["ts"], "complete": True})
        self.assertEqual(state.last_undoable()["ts"], a["ts"])
        state.append({"kind": "undo", "undoes": a["ts"], "complete": True})
        self.assertIsNone(state.last_undoable())

    def test_failed_undo_can_be_retried(self):
        a = state.append({"kind": "apply", "moves": [{"id": "x"}]})
        state.append({"kind": "undo", "undoes": a["ts"], "complete": False})
        self.assertEqual(state.last_undoable()["ts"], a["ts"])
        state.append({"kind": "undo", "undoes": a["ts"], "complete": True})
        self.assertIsNone(state.last_undoable())

    def test_undo_skips_runs_that_changed_nothing(self):
        a = state.append({"kind": "apply", "moves": [{"id": "x"}]})
        state.append({"kind": "apply", "moves": [], "labels": [], "snapshot": ["x"]})
        self.assertEqual(state.last_undoable()["ts"], a["ts"])

    def test_torn_last_line_is_ignored(self):
        state.append({"kind": "apply", "snapshot": ["x"]})
        with open(state.log_path(), "a") as f:
            f.write('{"kind": "apply", "snaps')
        self.assertEqual(state.last_snapshot(), {"x"})

    def test_key_for(self):
        self.assertEqual([apply.key_for(n) for n in range(2, 11)],
                         ["2", "3", "4", "5", "F1", "F2", "F3", "F4", "F5"])


class FakeDesktop:
    """Stands in for cmux + OmniWM so apply()/undo() run end to end.

    Two displays: A shows 1/2/5, B shows the rest. Window names that collide
    come out "ambiguous" with candidate workspaces, as the real title join does.
    `fail` holds commands (tuples) that return not-ok; `on_rename` is a hook
    that runs after a cmux rename (to simulate the user acting mid-run).
    """

    DISPLAY = {1: "A", 2: "A", 5: "A"}

    def __init__(self, windows, labels=None, layouts=None, shown=None, current="B"):
        self.w = {i: dict(name=n, ws=ws, repo=repo) for i, (n, ws, repo) in windows.items()}
        self.labels = dict(labels or {})
        self.layouts = {n: "dwindle" for n in range(1, 11)} | dict(layouts or {})
        self.shown = dict(shown or {"A": 2, "B": 6})
        self.current = current
        self.fail, self.on_rename, self.calls = set(), None, []

    def display(self, n):
        return self.DISPLAY.get(n, "B")

    def collect(self):
        names = {}
        for i, x in self.w.items():
            names.setdefault(x["name"], []).append(i)
        windows = []
        for i, x in self.w.items():
            same = names[x["name"]]
            ok = len(same) == 1
            cands = sorted({self.w[j]["ws"] for j in same})
            windows.append({
                "id": i, "name": x["name"], "repo": x["repo"], "cmux_workspace": f"workspace:{i}",
                "omniwm_match": "ok" if ok else "ambiguous", "omniwm_id": f"ow_{i}" if ok else None,
                "omniwm_workspace": x["ws"] if ok else None, "omniwm_candidates": cands,
                "maybe_user_workspace": 1 in cands, "floating": False, "scratchpad": False})
        wss = [{"number": n, "label": self.labels.get(n), "layout": self.layouts[n]} for n in range(1, 11)]
        inventory.flag(windows, wss)
        return {"current_workspace": self.shown[self.current], "windows": windows, "workspaces": wss}

    def omniwm(self, *args):
        return {"workspaces": [{"number": n, "display": {"id": self.display(n)},
                                "isVisible": self.shown[self.display(n)] == n,
                                "isCurrent": self.shown[self.current] == n} for n in range(1, 11)]}

    def omni(self, *args):
        args = tuple(map(str, args))
        self.calls.append(args)
        if args in self.fail:
            return False, "boom"
        if args[:2] == ("command", "switch-workspace"):
            n = int(args[2])
            self.shown[self.display(n)] = n
            self.current = self.display(n)
        elif args[:2] == ("command", "set-workspace-layout"):
            self.layouts[self.shown[self.current]] = args[2]
        elif args[:2] == ("window", "move-to-workspace"):
            self.w[args[2].removeprefix("ow_")]["ws"] = int(args[3])
        elif args[:2] == ("workspace", "rename"):
            self.labels[int(args[2])] = args[3] or None
        return True, "executed"

    def cmux(self, *args):
        if ("cmux",) + args in self.fail:
            raise SystemExit("cmux failed")
        i = args[args.index("--workspace") + 1].removeprefix("workspace:")
        self.w[i]["name"] = args[args.index("--title") + 1]
        if self.on_rename:
            self.on_rename(self)

    def __enter__(self):
        self.saved = (inventory.collect, inventory.omniwm, apply.omni, apply.cmux)
        inventory.collect, inventory.omniwm = self.collect, self.omniwm
        apply.omni, apply.cmux = self.omni, self.cmux
        return self

    def __exit__(self, *exc):
        inventory.collect, inventory.omniwm, apply.omni, apply.cmux = self.saved

    def ws_of(self, i):
        return self.w[i]["ws"]


def full_plan(desk, **decisions):
    """A complete plan: every window 'stay' (or 'skip' on 1) unless overridden."""
    inv = desk.collect()
    entries = []
    for w in inv["windows"]:
        e = {"id": w["id"], "action": "skip" if w["omniwm_workspace"] == 1 or w["maybe_user_workspace"] else "stay"}
        if e["action"] == "stay" and (w["new"] or w["misplaced"]):
            e["reason"] = "considered"
        e.update(decisions.get(w["id"], {}))
        entries.append(e)
    return {"windows": entries}


class ExecuteTests(unittest.TestCase):
    def setUp(self):
        reset_log()

    def desk(self, **kw):
        return FakeDesktop({"jan": ("jan", 1, "release"), "a": ("a", 3, "x"), "b": ("b", 6, "y"),
                            "c": ("c", 6, "y")}, **kw)

    def test_apply_then_undo_restores_everything(self):
        with self.desk(labels={6: "F1 y"}) as d:
            plan = full_plan(d, a={"action": "move", "to": 7, "rename": "a work"})
            plan["workspaces"] = [{"number": 7, "label": "F2 x", "repos": ["x"], "layout": "niri"}]
            code, out = apply.apply(plan, dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual((d.ws_of("a"), d.w["a"]["name"], d.labels[7], d.layouts[7]), (7, "a work", "F2 x", "niri"))
            self.assertEqual(d.shown, {"A": 2, "B": 6})  # both displays put back
            self.assertEqual(state.label_repos({7: "F2 x"}), {7: {"x"}})
            code, out = apply.undo(dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual((d.ws_of("a"), d.w["a"]["name"], d.labels.get(7), d.layouts[7]), (3, "a", None, "dwindle"))
            self.assertEqual(d.shown, {"A": 2, "B": 6})
            self.assertEqual(apply.undo(dry=False), (0, {"undo": "nothing to undo"}))

    def test_reapplying_is_harmless(self):
        with self.desk() as d:
            plan = full_plan(d, a={"action": "move", "to": 7})
            apply.apply(plan, dry=False)
            code, out = apply.apply(plan, dry=False)
            self.assertIn("'a' already on 7", out["report"])
            apply.undo(dry=False)
            self.assertEqual(d.ws_of("a"), 3)  # undid the real move, not the no-op

    def test_colliding_title_on_workspace_one_is_never_touched(self):
        with FakeDesktop({"jan": ("dup", 1, "release"), "x": ("dup", 3, "x")}) as d:
            inv = d.collect()
            bad = {"windows": [{"id": "jan", "action": "move", "to": 5, "rename": "jan new"},
                               {"id": "x", "action": "stay", "rename": "x new"}]}
            self.assertTrue(apply.validate(bad, inv))
            code, out = apply.apply(full_plan(d, x={"action": "skip"}), dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual((d.ws_of("jan"), d.w["jan"]["name"]), (1, "dup"))

    def test_window_dragged_onto_workspace_one_mid_run_is_not_moved(self):
        with self.desk() as d:
            d.on_rename = lambda desk: desk.w["a"].update(ws=1)
            code, out = apply.apply(full_plan(d, a={"action": "move", "to": 7},
                                              b={"action": "stay", "rename": "b2"}), dry=False)
            self.assertEqual(code, 1)
            self.assertEqual(d.ws_of("a"), 1)
            self.assertTrue(any("workspace 1" in f for f in out["failed"]))

    def test_failed_move_is_reported_and_not_logged(self):
        with self.desk() as d:
            d.fail.add(("window", "move-to-workspace", "ow_a", "7"))
            code, out = apply.apply(full_plan(d, a={"action": "move", "to": 7}), dry=False)
            self.assertEqual(code, 1)
            self.assertTrue(out["failed"])
            self.assertIsNone(state.last_undoable())

    def test_failed_undo_can_be_retried(self):
        with self.desk() as d:
            plan = full_plan(d, a={"action": "move", "to": 7})
            plan["workspaces"] = [{"number": 7, "label": "F2 x", "repos": ["x"]}]
            apply.apply(plan, dry=False)
            d.fail.add(("window", "move-to-workspace", "ow_a", "3"))
            self.assertEqual(apply.undo(dry=False)[0], 1)
            self.assertEqual(d.ws_of("a"), 7)
            d.fail.clear()
            code, out = apply.undo(dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual((d.ws_of("a"), d.labels.get(7)), (3, None))
            self.assertIn("label 7 already '7'", out["report"])

    def test_layout_is_not_set_when_the_switch_fails(self):
        with self.desk() as d:
            d.fail.add(("command", "switch-workspace", "8"))
            plan = full_plan(d)
            plan["workspaces"] = [{"number": 8, "layout": "niri"}]
            code, out = apply.apply(plan, dry=False)
            self.assertEqual(code, 1)
            self.assertEqual(d.layouts[6], "dwindle")  # the active one was not changed instead
            self.assertIsNone(state.last_undoable())

    def test_dry_run_changes_and_logs_nothing(self):
        with self.desk() as d:
            plan = full_plan(d, a={"action": "move", "to": 7, "rename": "a2"})
            plan["workspaces"] = [{"number": 7, "label": "F2 x", "repos": ["x"], "layout": "niri"}]
            code, out = apply.apply(plan, dry=True)
            self.assertEqual(code, 0, out)
            self.assertEqual((d.ws_of("a"), d.w["a"]["name"], d.labels.get(7)), (3, "a", None))
            self.assertFalse(os.path.exists(state.log_path()))

    def test_projects_are_recorded_even_when_the_label_is_unchanged(self):
        with self.desk(labels={6: "F1 y"}) as d:
            plan = full_plan(d)
            plan["workspaces"] = [{"number": 6, "label": "F1 y", "repos": ["y"]}]
            apply.apply(plan, dry=False)
            self.assertEqual(state.label_repos({6: "F1 y"}), {6: {"y"}})

    def test_stop_part_way_still_logs_and_undoes(self):
        with self.desk() as d:
            d.fail.add(("cmux", "workspace-action", "--workspace", "workspace:b", "--action", "rename", "--title", "b2"))
            code, out = apply.apply(full_plan(d, a={"action": "stay", "rename": "a2"},
                                              b={"action": "stay", "rename": "b2"}), dry=False)
            self.assertEqual(code, 1)
            self.assertEqual(d.w["a"]["name"], "a2")
            apply.undo(dry=False)
            self.assertEqual(d.w["a"]["name"], "a")

    def test_focus_returns_to_the_focused_display(self):
        # Workspace 6 is visible on B while A is focused; re-laying-out 6
        # focuses B without changing what either display shows.
        with self.desk(current="A") as d:
            plan = full_plan(d)
            plan["workspaces"] = [{"number": 6, "layout": "niri"}]
            apply.apply(plan, dry=False)
            self.assertEqual((d.layouts[6], d.shown, d.current), ("niri", {"A": 2, "B": 6}, "A"))
            apply.undo(dry=False)
            self.assertEqual((d.layouts[6], d.current), ("dwindle", "A"))

    def test_undo_of_an_unlocatable_window_stays_retryable(self):
        with self.desk() as d:
            apply.apply(full_plan(d, a={"action": "move", "to": 7}), dry=False)
            d.w["a2"] = dict(name="a", ws=8, repo="x")  # a new window takes its title
            self.assertEqual(apply.undo(dry=False)[0], 1)
            del d.w["a2"]
            self.assertEqual(apply.undo(dry=False)[0], 0)
            self.assertEqual(d.ws_of("a"), 3)

    def test_undone_run_leaves_its_windows_new(self):
        with self.desk() as d:
            apply.apply(full_plan(d), dry=False)  # first run: everything seen
            d.w["n"] = dict(name="n", ws=3, repo="x")
            inv = d.collect()
            self.assertTrue(next(w for w in inv["windows"] if w["id"] == "n")["new"])
            apply.apply(full_plan(d, n={"action": "move", "to": 7}), dry=False)
            self.assertFalse(next(w for w in d.collect()["windows"] if w["id"] == "n")["new"])
            apply.undo(dry=False)
            self.assertTrue(next(w for w in d.collect()["windows"] if w["id"] == "n")["new"])

    def test_renaming_to_the_current_name_is_a_no_op(self):
        with self.desk() as d:
            self.assertEqual(apply.validate(full_plan(d, a={"action": "stay", "rename": "a"}), d.collect()), [])

    def test_unexpected_error_still_logs_and_reports(self):
        with self.desk() as d:
            real = d.omni
            def boom(*args):
                if args[:2] == ("workspace", "rename"):
                    raise KeyError("surprise")
                return real(*args)
            apply.omni = boom
            plan = full_plan(d, a={"action": "move", "to": 7})
            plan["workspaces"] = [{"number": 7, "label": "F2 x", "repos": ["x"]}]
            code, out = apply.apply(plan, dry=False)
            self.assertEqual(code, 1)
            self.assertTrue(any("KeyError" in f for f in out["failed"]))
            self.assertEqual(state.last_undoable()["moves"][0]["to"], 7)

    def test_undo_refuses_a_hand_edited_log(self):
        with self.desk() as d:
            state.append({"kind": "apply", "moves": [{"id": "a", "from": 1, "to": 3}],
                          "labels": [{"workspace": 1, "from": "1", "to": "hacked"}],
                          "layouts": [{"workspace": 1, "from": "niri", "to": "dwindle"}]})
            code, out = apply.undo(dry=False)
            self.assertEqual(code, 0, out)  # bad entries are ignored, not retried forever
            self.assertEqual(d.ws_of("a"), 3)
            self.assertEqual(len(out["ignored"]), 3)
            self.assertFalse([c for c in d.calls if c[:2] != ("command", "switch-workspace")])
            self.assertIsNone(state.last_undoable())

    def test_malformed_log_neither_crashes_nor_blocks(self):
        with self.desk() as d:
            os.makedirs(state.state_dir(), exist_ok=True)
            with open(state.log_path(), "a") as f:
                f.write("5\n[1, 2]\n")
            state.append({"kind": "apply", "moves": "oops", "labels": [{"workspace": [7]}, "x"],
                          "projects": [{"workspace": [2], "label": "2 a", "repos": ["a"]}, 7,
                                       {"workspace": 3, "label": None, "repos": ["a"]}]})
            d.collect()  # the inventory still runs
            self.assertEqual(state.label_repos({2: "2 a", 3: None}), {})
            code, out = apply.undo(dry=False)
            self.assertEqual(code, 0, out)
            self.assertTrue(out["ignored"])

    def test_abandon_lets_undo_reach_older_runs(self):
        with self.desk() as d:
            apply.apply(full_plan(d, a={"action": "move", "to": 7}), dry=False)
            first = state.last_undoable()["ts"]
            apply.apply(full_plan(d, b={"action": "move", "to": 8}), dry=False)
            d.fail.add(("window", "move-to-workspace", "ow_b", "6"))
            self.assertEqual(apply.undo(dry=False)[0], 1)  # stuck
            self.assertEqual(apply.abandon(dry=False)[0], 0)
            self.assertEqual(state.last_undoable()["ts"], first)
            apply.undo(dry=False)
            self.assertEqual((d.ws_of("a"), d.ws_of("b")), (3, 8))

    def test_move_refused_if_its_omniwm_window_changed(self):
        # Two windows swap names; if titles lag, x's new name would match y.
        with FakeDesktop({"x": ("a", 3, "r"), "y": ("b", 4, "r")}) as d:
            plan = full_plan(d, x={"action": "move", "to": 7, "rename": "b"}, y={"action": "stay", "rename": "a"})
            self.assertEqual(apply.validate(plan, d.collect()), [])
            real_collect, renamed = d.collect, []
            d.on_rename = lambda desk: renamed.append(1)
            def lagging():
                inv = real_collect()
                if renamed:  # after the renames, the title join lags behind them
                    for w in inv["windows"]:
                        w["omniwm_id"] = {"x": "ow_y", "y": "ow_x"}[w["id"]]
                return inv
            inventory.collect = lagging
            code, out = apply.apply(plan, dry=False)
            self.assertEqual(code, 1)
            self.assertEqual((d.ws_of("x"), d.ws_of("y")), (3, 4))

    def test_undo_rename_does_not_create_a_duplicate(self):
        with self.desk() as d:
            apply.apply(full_plan(d, a={"action": "stay", "rename": "a2"}), dry=False)
            d.w["b"]["name"] = "a"  # the user reuses the old name
            code, out = apply.undo(dry=False)
            self.assertEqual((d.w["a"]["name"], d.w["b"]["name"]), ("a2", "a"))
            self.assertTrue(any("another window is called 'a'" in r for r in out["report"]))

    def test_layout_waits_for_its_workspace_to_be_active(self):
        with self.desk() as d:
            real = d.omni
            def no_op_switch(*args):  # switch "succeeds" but nothing changes
                if args[:2] == ("command", "switch-workspace"):
                    return True, "executed"
                return real(*args)
            apply.omni = no_op_switch
            plan = full_plan(d)
            plan["workspaces"] = [{"number": 8, "layout": "niri"}]
            code, out = apply.apply(plan, dry=False)
            self.assertEqual(code, 1)
            self.assertNotIn("niri", d.layouts.values())


if __name__ == "__main__":
    unittest.main(verbosity=1)
