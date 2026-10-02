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


def spots():
    return {name: p["workspace"] for name, p in state.last_placements().items()}


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
        for to in (1, 10, 12, None, "2", "11"):
            problems = apply.validate(self.plan(allocmisc={"action": "move", "to": to}), self.inv)
            self.assertTrue(problems, f"to={to!r} should be refused")
        for to in (2, 9, 11):  # 11 is in the pool, past review
            self.assertEqual(apply.validate(self.plan(allocmisc={"action": "move", "to": to}), self.inv), [])

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
                             (7, "F2 a-very-long-name", False), (1, "1 mine", False),
                             (11, "6 alloc", True), (11, "6", True), (11, "11 alloc", False),
                             (11, "F6 alloc", False), (11, "alloc", False), (12, "7 x", False)]:
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
        self.assertEqual([apply.key_for(n) for n in range(2, 12)],
                         ["2", "3", "4", "5", "F1", "F2", "F3", "F4", "F5", "6"])


class FakeDesktop:
    """Stands in for cmux + OmniWM so apply()/undo() run end to end.

    Two displays: A shows 1/2/5, B shows the rest. Window names that collide
    come out "ambiguous" with candidate workspaces, as the real title join does.
    `fail` holds commands (tuples) that return not-ok; `on_rename` is a hook
    that runs after a cmux rename (to simulate the user acting mid-run).
    """

    DISPLAY = {1: "A", 2: "A", 5: "A", 11: "A"}
    NUMBERS = range(1, 12)

    def __init__(self, windows, labels=None, layouts=None, shown=None, current="B"):
        self.w = {i: dict(name=n, ws=ws, repo=repo) for i, (n, ws, repo) in windows.items()}
        self.labels = dict(labels or {})
        self.layouts = {n: "dwindle" for n in self.NUMBERS} | dict(layouts or {})
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
        wss = [{"number": n, "label": self.labels.get(n), "layout": self.layouts[n]} for n in self.NUMBERS]
        inventory.flag(windows, wss)
        pile = inventory.recovery(windows)
        return {"current_workspace": self.shown[self.current], "restart": pile is not None,
                "restart_workspace": pile, "windows": windows, "workspaces": wss}

    def restart(self, prefix="r", on=1):
        """cmux restarts: every window lands on one workspace (1, or the one
        the user was on) under a new id, names kept."""
        self.w = {prefix + i: dict(x, ws=on) for i, x in self.w.items()}

    def omniwm(self, *args):
        return {"workspaces": [{"number": n, "display": {"id": self.display(n)},
                                "isVisible": self.shown[self.display(n)] == n,
                                "isCurrent": self.shown[self.current] == n} for n in self.NUMBERS]}

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

    def test_workspace_eleven_is_a_pool_workspace_keyed_6(self):
        # 11 sits on the external display (A) and its key is Caps+6, so its
        # bare label is a literal "6", never "" (which would show "11").
        with self.desk(labels={11: "6"}) as d:
            plan = full_plan(d, a={"action": "move", "to": 11})
            plan["workspaces"] = [{"number": 11, "label": "6 x", "repos": ["x"]}]
            code, out = apply.apply(plan, dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual((d.ws_of("a"), d.labels[11]), (11, "6 x"))
            self.assertEqual(d.shown, {"A": 2, "B": 6})
            self.assertEqual(state.label_repos({11: "6 x"}), {11: {"x"}})
            code, out = apply.undo(dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual((d.ws_of("a"), d.labels[11]), (3, "6"))
            self.assertIn(("workspace", "rename", "11", "6"), d.calls)

    def test_emptied_workspace_eleven_goes_back_to_its_key(self):
        with FakeDesktop({"a": ("a", 3, "x")}, labels={11: "6 x"}) as d:
            plan = full_plan(d)
            plan["workspaces"] = [{"number": 11, "label": "6"}]
            code, out = apply.apply(plan, dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual(d.labels[11], "6")
            self.assertIn(("workspace", "rename", "11", "6"), d.calls)

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


class RestartTests(unittest.TestCase):
    """After a cmux restart every window is on 1 with a new id; restore puts
    each back on its last workspace, by name, and nothing else leaves 1."""

    def setUp(self):
        reset_log()

    def settled(self, **extra):
        """A desktop triaged once (so placements are logged), then restarted."""
        windows = {"jan": ("jan", 1, "release"), "a": ("a", 3, "x"), "b": ("b", 6, "y"),
                   "c": ("c", 6, "y"), "t": ("t", 10, "tmp")} | extra
        d = FakeDesktop(windows)
        with d:
            code, out = apply.apply(full_plan(d), dry=False)
            self.assertEqual(code, 0, out)
        d.restart()
        return d

    def restore_all(self, d, **decisions):
        inv = d.collect()
        restores = {w["id"]: {"action": "restore"} for w in inv["windows"]
                    if w["omniwm_workspace"] == 1 and w["last_workspace"] not in (None, 1)}
        return full_plan(d, **(restores | decisions))

    def test_placements_are_recorded_by_name(self):
        d = self.settled()
        self.assertEqual(spots(), {"jan": 1, "a": 3, "b": 6, "c": 6, "t": 10})
        entry = state.read_log()[-1]
        self.assertIn({"name": "a", "workspace": 3, "repo": "x"}, entry["placements"])

    def test_restart_is_detected(self):
        with self.settled() as d:
            inv = d.collect()
            self.assertIs(inv["restart"], True)
            last = {w["name"]: w["last_workspace"] for w in inv["windows"]}
            self.assertEqual(last, {"jan": 1, "a": 3, "b": 6, "c": 6, "t": 10})

    def test_no_restart_without_a_majority_on_one(self):
        with self.settled() as d:
            d.w["ra"]["ws"], d.w["rb"]["ws"] = 3, 6  # 3 of 5 on 1: 60%
            self.assertIs(d.collect()["restart"], False)

    def test_no_restart_when_they_were_on_one_last_time(self):
        with FakeDesktop({"a": ("a", 1, "x"), "b": ("b", 1, "y"), "c": ("c", 1, "z"), "d": ("d", 3, "z")}) as d:
            apply.apply(full_plan(d), dry=False)
            d.restart()
            # Most were on 1 before, too; one window back from elsewhere is
            # too little to tell a restart from a reopened window.
            self.assertIs(d.collect()["restart"], False)

    def test_no_restart_with_too_few_windows_or_no_log(self):
        with FakeDesktop({"a": ("a", 1, "x"), "b": ("b", 1, "y")}) as d:
            self.assertIs(d.collect()["restart"], False)  # no log
            state.append({"kind": "apply", "placements": [{"name": "a", "workspace": 3}, {"name": "b", "workspace": 4}]})
            self.assertIs(d.collect()["restart"], False)  # only two windows

    def test_restore_then_undo_back_to_one(self):
        with self.settled() as d:
            code, out = apply.apply(self.restore_all(d), dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual({x["name"]: x["ws"] for x in d.w.values()}, {"jan": 1, "a": 3, "b": 6, "c": 6, "t": 10})
            self.assertIs(d.collect()["restart"], False)
            self.assertEqual(len(state.last_undoable()["restores"]), 4)
            code, out = apply.undo(dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual({x["ws"] for x in d.w.values()}, {1})
            # Undoing kept where they belong, so they can be restored again.
            self.assertEqual(spots(), {"jan": 1, "a": 3, "b": 6, "c": 6, "t": 10})
            self.assertIs(d.collect()["restart"], True)
            code, out = apply.apply(self.restore_all(d), dry=False)
            self.assertEqual((code, d.ws_of("ra")), (0, 3), out)

    def test_restore_to_workspace_eleven(self):
        d = self.settled(e=("e", 11, "z"))
        self.assertEqual(spots()["e"], 11)
        with d:
            inv = d.collect()
            self.assertIs(inv["restart"], True)
            self.assertEqual(next(w for w in inv["windows"] if w["id"] == "re")["restore_to"], 11)
            code, out = apply.apply(self.restore_all(d), dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual(d.ws_of("re"), 11)
            code, out = apply.undo(dry=False)
            self.assertEqual((code, d.ws_of("re")), (0, 1), out)

    def test_failed_restore_keeps_where_it_belongs(self):
        with self.settled() as d:
            d.fail.add(("window", "move-to-workspace", "ow_ra", "3"))
            code, out = apply.apply(self.restore_all(d), dry=False)
            self.assertEqual(code, 1)
            self.assertEqual((d.ws_of("ra"), d.ws_of("rb")), (1, 6))
            self.assertEqual(spots()["a"], 3)
            placement = next(p for p in state.read_log()[-1]["placements"] if p["name"] == "a")
            self.assertTrue(placement["carried"])
            d.fail.clear()
            inv = d.collect()
            self.assertIs(inv["restart"], False)  # most are back now...
            ra = next(w for w in inv["windows"] if w["id"] == "ra")
            self.assertEqual(ra["restore_to"], 3)  # ...but the carried one can still go
            code, out = apply.apply(full_plan(d, ra={"action": "restore"}), dry=False)
            self.assertEqual((code, d.ws_of("ra")), (0, 3), out)

    def test_declined_restore_is_forgotten(self):
        with self.settled() as d:
            apply.apply(full_plan(d), dry=False)  # everything on 1 skipped
            self.assertEqual(set(spots().values()), {1})
            self.assertIs(d.collect()["restart"], False)

    def test_windows_dragged_onto_one_are_not_a_restart(self):
        with FakeDesktop({"jan": ("jan", 1, "r"), "a": ("a", 3, "x"), "b": ("b", 6, "y"), "c": ("c", 6, "y")}) as d:
            apply.apply(full_plan(d), dry=False)
            d.w["a"]["ws"] = d.w["b"]["ws"] = 1  # same ids: the user's own drag
            inv = d.collect()
            self.assertIs(inv["restart"], False)
            self.assertEqual({w["restore_to"] for w in inv["windows"]}, {None})
            problems = apply.validate(full_plan(d, a={"action": "restore"}), inv)
            self.assertTrue(problems)

    def test_undo_of_a_partial_restore_keeps_every_destination(self):
        with self.settled() as d:
            code, out = apply.apply(self.restore_all(d, rt={"action": "skip"}), dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual(spots()["t"], 1)  # declined
            d.fail.add(("window", "move-to-workspace", "ow_ra", "1"))
            code, out = apply.undo(dry=False)  # 'a' can't go back yet
            self.assertEqual(code, 1)
            d.fail.clear()
            self.assertEqual(apply.undo(dry=False)[0], 0)
            self.assertEqual(spots(), {"jan": 1, "a": 3, "b": 6, "c": 6, "t": 1})

    def test_undo_of_another_run_after_a_restart_keeps_destinations(self):
        with self.settled() as d:
            state.append({"kind": "apply", "labels": [{"workspace": 7, "from": "F2", "to": "F2 x"}],
                          "placements": state.read_log()[-1]["placements"]})
            d.labels[7] = "F2 x"
            self.assertEqual(apply.undo(dry=False)[0], 0)
            self.assertEqual(spots(), {"jan": 1, "a": 3, "b": 6, "c": 6, "t": 10})
            self.assertIs(d.collect()["restart"], True)

    def test_abandon_keeps_the_placements_it_left(self):
        with FakeDesktop({"jan": ("jan", 1, "r"), "a": ("a", 3, "x"), "b": ("b", 6, "y"), "c": ("c", 6, "y")}) as d:
            apply.apply(full_plan(d), dry=False)
            apply.apply(full_plan(d, a={"action": "move", "to": 7}), dry=False)
            apply.abandon(dry=False)
            self.assertEqual(spots()["a"], 7)
            d.restart()
            ra = next(w for w in d.collect()["windows"] if w["id"] == "ra")
            self.assertEqual(ra["restore_to"], 7)

    def test_reused_name_in_another_repo_has_no_last_workspace(self):
        with self.settled() as d:
            d.w["ra"]["repo"] = "other"
            ra = next(w for w in d.collect()["windows"] if w["id"] == "ra")
            self.assertEqual((ra["last_workspace"], ra["restore_to"]), (None, None))

    def test_restore_is_rechecked_without_renames(self):
        with self.settled() as d:
            plan = self.restore_all(d)
            real = inventory.collect
            calls = []
            def moved_after_validation():
                calls.append(1)
                if len(calls) == 2:  # the re-check, after validation
                    d.w["ra"]["ws"] = 5
                return real()
            inventory.collect = moved_after_validation
            code, out = apply.apply(plan, dry=False)
            self.assertEqual(code, 1, out)
            self.assertEqual(d.ws_of("ra"), 5)
            self.assertTrue(any("didn't restore 'a'" in f for f in out["failed"]), out)

    def test_no_restore_once_the_restart_has_passed(self):
        with self.settled() as d:
            for i in ("rb", "rc", "rt"):  # the user put most back by hand
                d.w[i]["ws"] = {"rb": 6, "rc": 6, "rt": 10}[i]
            inv = d.collect()
            self.assertIs(inv["restart"], False)
            ra = next(w for w in inv["windows"] if w["id"] == "ra")
            self.assertEqual((ra["last_workspace"], ra["restore_to"]), (3, None))
            self.assertTrue(apply.validate(full_plan(d, ra={"action": "restore"}), inv))

    def test_restore_refused_if_the_restart_passes_mid_run(self):
        with self.settled() as d:
            plan = self.restore_all(d)
            real, calls = inventory.collect, []
            def user_restores_the_rest():
                calls.append(1)
                if len(calls) == 2:
                    d.w["rb"]["ws"], d.w["rc"]["ws"], d.w["rt"]["ws"] = 6, 6, 10
                return real()
            inventory.collect = user_restores_the_rest
            code, out = apply.apply(plan, dry=False)
            self.assertEqual(code, 1, out)
            self.assertEqual(d.ws_of("ra"), 1)
            self.assertTrue(any("isn't restorable" in f for f in out["failed"]), out)

    def test_reapplied_restore_is_harmless(self):
        with self.settled() as d:
            plan = self.restore_all(d)
            apply.apply(plan, dry=False)
            code, out = apply.apply(plan, dry=False)
            self.assertEqual(code, 0, out)
            self.assertIn("'a' already on 3", out["report"])

    def test_dry_run_restore_logs_nothing(self):
        with self.settled() as d:
            before = len(state.read_log())
            code, out = apply.apply(self.restore_all(d), dry=True)
            self.assertEqual(code, 0, out)
            self.assertIn("would restore 'a' 1 -> 3", out["would"])
            self.assertEqual((d.ws_of("ra"), len(state.read_log())), (1, before))

    def test_undo_restore_needs_the_same_name(self):
        with self.settled() as d:
            d.w["rb"]["ws"] = 6
            state.append({"kind": "apply", "restores": [{"id": "rb", "name": "someone-else", "from": 1, "to": 6}]})
            apply.undo(dry=False)
            self.assertEqual(d.ws_of("rb"), 6)

    def test_unlocatable_window_keeps_its_placement(self):
        with FakeDesktop({"jan": ("jan", 1, "r"), "a": ("a", 3, "x"), "b": ("b", 6, "y")}) as d:
            apply.apply(full_plan(d), dry=False)
            real = d.collect
            def unmatched():
                inv = real()
                for w in inv["windows"]:
                    if w["id"] == "a":
                        w.update(omniwm_match="none", omniwm_id=None, omniwm_workspace=None,
                                 omniwm_candidates=[], maybe_user_workspace=True)
                return inv
            inventory.collect = unmatched
            apply.apply(full_plan(d, a={"action": "skip"}), dry=False)
            placement = next(p for p in state.read_log()[-1]["placements"] if p["name"] == "a")
            self.assertEqual((placement["workspace"], placement["unverified"]), (3, True))
            self.assertEqual(spots()["a"], 3)

    def test_torn_line_does_not_swallow_the_next_entry(self):
        os.makedirs(state.state_dir(), exist_ok=True)
        with open(state.log_path(), "ab") as f:
            f.write('{"kind": "apply", "placements": [{"name": "✳'.encode()[:-1])  # torn mid-character
        state.append({"kind": "apply", "placements": [{"name": "a", "workspace": 3}]})
        self.assertEqual(spots(), {"a": 3})

    def test_odd_timestamps_do_not_crash(self):
        state.append({"kind": "apply", "ts": ["x"], "moves": [{"id": "x"}], "snapshot": [["y"], "z"],
                      "placements": [{"name": "a", "workspace": 3}]})
        state.append({"kind": "undo", "undoes": ["x"], "complete": True})
        self.assertIsNone(state.last_undoable())
        self.assertEqual(state.last_snapshot(), {"z"})
        self.assertEqual(spots(), {})

    def test_restore_is_refused_without_a_restart(self):
        with FakeDesktop({"jan": ("jan", 1, "release"), "a": ("a", 1, "x"), "b": ("b", 3, "y")}) as d:
            state.append({"kind": "apply", "placements": [{"name": "a", "workspace": 3}]})
            inv = d.collect()
            self.assertEqual(next(w for w in inv["windows"] if w["id"] == "a")["last_workspace"], 3)
            problems = apply.validate(full_plan(d, a={"action": "restore"}), inv)
            self.assertTrue(any("restart" in p for p in problems), problems)

    def test_restore_goes_only_to_its_last_workspace(self):
        with self.settled() as d:
            inv = d.collect()
            for to in (4, 1, 10, "3", 3.0, None):
                problems = apply.validate(self.restore_all(d, ra={"action": "restore", "to": to}), inv)
                self.assertTrue(problems, f"to={to!r}")
            self.assertEqual(apply.validate(self.restore_all(d, ra={"action": "restore", "to": 3}), inv), [])

    def test_restore_is_refused_for_windows_that_belong_on_one(self):
        with self.settled() as d:
            problems = apply.validate(self.restore_all(d, rjan={"action": "restore"}), d.collect())
            self.assertTrue(any("'jan'" in p and "last workspace is 1" in p for p in problems), problems)
            problems = apply.validate(self.restore_all(d, rjan={"action": "stay"}), d.collect())
            self.assertTrue(any("'jan'" in p and "must be 'skip'" in p for p in problems), problems)

    def test_other_actions_still_cannot_leave_one(self):
        with self.settled() as d:
            for e in ({"action": "move", "to": 3}, {"action": "review"}, {"action": "stay"},
                      {"action": "restore", "rename": "a2"}):
                self.assertTrue(apply.validate(self.restore_all(d, ra=e), d.collect()), e)

    def test_restore_only_moves_windows_off_the_pile(self):
        with self.settled() as d:
            d.w["rb"]["ws"] = 7
            problems = apply.validate(self.restore_all(d, rb={"action": "restore"}), d.collect())
            self.assertTrue(any("only moves windows off the restart pile on workspace 1" in p for p in problems),
                            problems)

    def test_duplicate_names_are_not_restored(self):
        with self.settled(e=("e", 4, "z"), f=("f", 5, "z")) as d:
            d.w["rb"]["name"] = "c"  # two windows called 'c' now
            inv = d.collect()
            self.assertEqual({w["last_workspace"] for w in inv["windows"] if w["name"] == "c"}, {None})
            for i in ("rb", "rc"):
                self.assertTrue(apply.validate(self.restore_all(d, **{i: {"action": "restore"}}), inv), i)
            code, out = apply.apply(self.restore_all(d), dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual((d.ws_of("rb"), d.ws_of("rc"), d.ws_of("ra")), (1, 1, 3))

    def test_duplicate_name_is_refused_even_if_matched(self):
        # Belt and braces: a shared name never restores, whatever the join says.
        with self.settled() as d:
            inv = d.collect()
            for w in inv["windows"]:
                if w["id"] == "rb":
                    w["name"] = "c"
            problems = apply.validate(self.restore_all(d, rc={"action": "restore"}), inv)
            self.assertTrue(any("'c'" in p and "isn't unique" in p for p in problems), problems)

    def test_names_logged_twice_have_no_last_workspace(self):
        state.append({"kind": "apply", "placements": [{"name": "a", "workspace": 3}, {"name": "a", "workspace": 4},
                                                       {"name": "b", "workspace": 5}]})
        self.assertEqual(spots(), {"b": 5})

    def test_maybe_user_window_is_not_restored(self):
        with self.settled() as d:
            inv = d.collect()
            ra = next(w for w in inv["windows"] if w["id"] == "ra")
            ra.update(omniwm_match="ambiguous", omniwm_id=None, omniwm_workspace=None,
                      omniwm_candidates=[1, 3], maybe_user_workspace=True)
            problems = apply.validate(self.restore_all(d, ra={"action": "restore"}), inv)
            self.assertTrue(any("'a'" in p and "matched" in p for p in problems), problems)

    def test_restore_is_rechecked_before_it_runs(self):
        cases = {
            "left 1": lambda desk: desk.w["ra"].update(ws=5),
            "renamed to a duplicate": lambda desk: desk.w["rb"].update(name="a"),
        }
        for why, act in cases.items():
            with self.subTest(why), self.settled() as d:
                d.on_rename = act
                plan = self.restore_all(d, rt={"action": "restore", "to": 10})
                # A rename elsewhere forces the fresh inventory the re-check uses.
                d.w["n"] = dict(name="n", ws=4, repo="z")
                plan["windows"].append({"id": "n", "action": "stay", "rename": "n2", "reason": "x"})
                code, out = apply.apply(plan, dry=False)
                self.assertEqual(code, 1, out)
                self.assertTrue(any("didn't restore 'a'" in f for f in out["failed"]), out)
                self.assertNotEqual(d.ws_of("ra"), 3)
                reset_log()

    def test_restore_refused_if_its_omniwm_window_changed(self):
        with self.settled() as d:
            plan = self.restore_all(d)
            d.w["n"] = dict(name="n", ws=4, repo="z")
            plan["windows"].append({"id": "n", "action": "stay", "rename": "n2", "reason": "x"})
            real_collect, renamed = d.collect, []
            d.on_rename = lambda desk: renamed.append(1)
            def lagging():
                inv = real_collect()
                for w in inv["windows"]:
                    if renamed and w["id"] == "ra":
                        w["omniwm_id"] = "ow_other"
                return inv
            inventory.collect = lagging
            code, out = apply.apply(plan, dry=False)
            self.assertEqual(code, 1)
            self.assertEqual(d.ws_of("ra"), 1)
            self.assertEqual(d.ws_of("rb"), 6)

    def test_undo_moves_into_one_only_for_logged_restores(self):
        with self.settled() as d:
            state.append({"kind": "apply", "moves": [{"id": "rb", "from": 1, "to": 6}],
                          "restores": [{"id": "rc", "name": "c", "from": 0, "to": 6},
                                       {"id": "ra", "name": "a", "from": 1, "to": 1},
                                       {"id": "rt", "from": True, "to": 10}, "x"]})
            d.w["rb"]["ws"] = d.w["rc"]["ws"] = 6
            d.w["rt"]["ws"] = 10
            code, out = apply.undo(dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual((d.ws_of("rb"), d.ws_of("rc"), d.ws_of("rt")), (6, 6, 10))
            self.assertEqual(len(out["ignored"]), 5)

    def test_malformed_placements_are_ignored(self):
        os.makedirs(state.state_dir(), exist_ok=True)
        state.append({"kind": "apply", "placements": [{"name": "good", "workspace": 3}]})
        state.append({"kind": "apply", "placements": [
            {"name": "a", "workspace": "3"}, {"name": "b", "workspace": 12}, {"name": "c", "workspace": True},
            {"name": 7, "workspace": 3}, {"name": "", "workspace": 3}, "x", None, {"workspace": 2},
            {"name": "d", "workspace": 4}]})
        self.assertEqual(spots(), {"d": 4})
        state.append({"kind": "apply", "placements": "oops"})
        state.append({"kind": "note", "placements": [{"name": "z", "workspace": 2}]})
        self.assertEqual(spots(), {"d": 4})
        with FakeDesktop({"a": ("a", 1, "x"), "b": ("b", 1, "x"), "d": ("d", 1, "x")}) as d:
            inv = d.collect()
            self.assertEqual({w["name"]: w["last_workspace"] for w in inv["windows"]}, {"a": None, "b": None, "d": 4})
            self.assertIs(inv["restart"], False)  # only 1 of 3 known to be elsewhere

    def test_old_carried_placements_were_on_one(self):
        # Logged before "pile" existed: every carried window was stuck on 1.
        state.append({"kind": "apply", "placements": [{"name": "a", "workspace": 3, "carried": True},
                                                       {"name": "b", "workspace": 4, "carried": True, "pile": "7"},
                                                       {"name": "c", "workspace": 5, "carried": True, "pile": 5}]})
        last = state.last_placements()
        self.assertEqual((last["a"]["carried"], last["a"]["pile"]), (True, 1))
        self.assertEqual((last["b"]["carried"], last["b"]["pile"]), (False, None))  # malformed pile
        self.assertEqual((last["c"]["carried"], last["c"]["pile"]), (False, None))  # stuck where it belongs?
        with FakeDesktop({"ra": ("a", 1, None), "rb": ("b", 7, None), "x": ("x", 3, None)}) as d:
            w = {x["name"]: x for x in d.collect()["windows"]}
            self.assertEqual((w["a"]["restore_to"], w["a"]["restore_from"]), (3, 1))
            self.assertIsNone(w["b"]["restore_to"])

    def test_undone_apply_placements_do_not_count(self):
        a = state.append({"kind": "apply", "moves": [{"id": "x"}], "placements": [{"name": "a", "workspace": 3}]})
        b = state.append({"kind": "apply", "moves": [{"id": "x"}], "placements": [{"name": "a", "workspace": 5}]})
        state.append({"kind": "undo", "undoes": b["ts"], "complete": True})
        self.assertEqual(spots(), {"a": 3})
        self.assertTrue(a)


class PileTests(unittest.TestCase):
    """A restart can pile every window onto any workspace, not just 1 (on
    2026-09-30 all 12 landed on 7, the one the user was viewing)."""

    HOME = {"jan": 1, "a": 3, "b": 6, "c": 6, "rel": 7, "rel2": 7, "t": 10, "e": 11}

    def setUp(self):
        reset_log()

    def settled(self, on=7):
        windows = {"jan": ("jan", 1, "release"), "a": ("a", 3, "x"), "b": ("b", 6, "y"), "c": ("c", 6, "y"),
                   "rel": ("rel", 7, "rel"), "rel2": ("rel2", 7, "rel"), "t": ("t", 10, "tmp"),
                   "e": ("e", 11, "z")}
        d = FakeDesktop(windows, labels={7: "F2 rel"})
        with d:
            code, out = apply.apply(full_plan(d), dry=False)
            self.assertEqual(code, 0, out)
        d.restart(on=on)
        return d

    def windows(self, d):
        return {w["name"]: w for w in d.collect()["windows"]}

    def restores(self, d, **decisions):
        """Restore every window with a restore_to; keep the rest in place."""
        inv = d.collect()
        restores = {w["id"]: {"action": "restore"} for w in inv["windows"] if w["restore_to"] is not None}
        return full_plan(d, **(restores | decisions))

    def where(self, d):
        return {x["name"]: x["ws"] for x in d.w.values()}

    def test_pile_on_seven_is_detected(self):
        with self.settled(on=7) as d:
            inv = d.collect()
            self.assertEqual((inv["restart"], inv["restart_workspace"]), (True, 7))
            w = {x["name"]: x for x in inv["windows"]}
            self.assertEqual({n: x["restore_to"] for n, x in w.items()},
                             {"jan": 1, "a": 3, "b": 6, "c": 6, "rel": None, "rel2": None, "t": 10, "e": 11})
            self.assertEqual({x["restore_from"] for n, x in w.items() if x["restore_to"]}, {7})
            self.assertEqual({x["restore_from"] for n, x in w.items() if not x["restore_to"]}, {None})

    def test_restore_from_seven_then_undo(self):
        with self.settled(on=7) as d:
            code, out = apply.apply(self.restores(d), dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual(self.where(d), self.HOME)
            self.assertIn("restored 'a' 7 -> 3", out["report"])
            self.assertIn("restored 'jan' 7 -> 1", out["report"])
            self.assertEqual({r["from"] for r in state.last_undoable()["restores"]}, {7})
            self.assertFalse(any(p.get("carried") for p in state.read_log()[-1]["placements"]))
            self.assertIs(d.collect()["restart"], False)
            code, out = apply.undo(dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual(set(self.where(d).values()), {7})  # jan too: back off 1
            self.assertEqual(spots(), self.HOME)  # kept where they belong
            last = state.last_placements()
            self.assertEqual((last["a"]["carried"], last["a"]["pile"]), (True, 7))
            self.assertFalse(last["rel"]["carried"])
            inv = d.collect()
            self.assertEqual((inv["restart"], inv["restart_workspace"]), (True, 7))
            code, out = apply.apply(self.restores(d), dry=False)
            self.assertEqual((code, self.where(d)), (0, self.HOME), out)

    def test_pile_on_one_still_works(self):
        with self.settled(on=1) as d:
            inv = d.collect()
            self.assertEqual((inv["restart"], inv["restart_workspace"]), (True, 1))
            w = {x["name"]: x for x in inv["windows"]}
            self.assertEqual((w["jan"]["restore_to"], w["rel"]["restore_to"], w["rel"]["restore_from"]), (None, 7, 1))
            code, out = apply.apply(self.restores(d), dry=False)
            self.assertEqual((code, self.where(d)), (0, self.HOME), out)
            self.assertEqual(apply.undo(dry=False)[0], 0)
            self.assertEqual(set(self.where(d).values()), {1})

    def test_pile_on_review(self):
        with self.settled(on=10) as d:
            inv = d.collect()
            self.assertEqual(inv["restart_workspace"], 10)
            w = {x["name"]: x for x in inv["windows"]}
            self.assertIsNone(w["t"]["restore_to"])  # it lives on review
            self.assertEqual((w["jan"]["restore_to"], w["rel"]["restore_to"]), (1, 7))
            code, out = apply.apply(self.restores(d), dry=False)
            self.assertEqual((code, self.where(d)), (0, self.HOME), out)
            self.assertEqual(apply.undo(dry=False)[0], 0)
            self.assertEqual(set(self.where(d).values()), {10})

    def test_unrestored_windows_on_a_pool_pile_get_normal_decisions(self):
        with self.settled(on=7) as d:
            inv = d.collect()
            ids = {x["name"]: x["id"] for x in inv["windows"]}
            # Not on 1, so not 'skip': they are ordinary windows on 7.
            problems = apply.validate(self.restores(d, **{ids["rel"]: {"action": "skip"}}), inv)
            self.assertTrue(any("'skip' is only for workspace 1" in p for p in problems), problems)
            # New (fresh ids), so staying takes a reason.
            problems = apply.validate(self.restores(d, **{ids["rel"]: {"action": "stay", "reason": ""}}), inv)
            self.assertTrue(any("'rel' is flagged new" in p for p in problems), problems)
            # A declined restore: the window is planned like any other.
            plan = self.restores(d, **{ids["a"]: {"action": "move", "to": 4},
                                       ids["b"]: {"action": "stay", "reason": "keep it here"},
                                       ids["rel2"]: {"action": "review"}})
            code, out = apply.apply(plan, dry=False)
            self.assertEqual(code, 0, out)
            self.assertEqual((d.ws_of("ra"), d.ws_of("rb"), d.ws_of("rrel2"), d.ws_of("rc")), (4, 7, 10, 6))
            self.assertEqual((spots()["a"], spots()["b"]), (4, 7))  # declined: forgotten
            self.assertIsNone(self.windows(d)["b"]["restore_to"])

    def test_no_restart_when_a_project_workspace_is_just_busy(self):
        # Most windows on one workspace with old ids is a project, not a pile.
        with FakeDesktop({"a": ("a", 3, "x"), "b": ("b", 3, "x"), "c": ("c", 3, "x"), "d": ("d", 3, "x"),
                          "e": ("e", 6, "y")}) as d:
            apply.apply(full_plan(d), dry=False)
            inv = d.collect()
            self.assertEqual((inv["restart"], inv["restart_workspace"]), (False, None))
            # Even if the user drags every window onto 3 by hand: same ids.
            d.w["e"]["ws"] = 3
            apply.apply(full_plan(d), dry=False)
            d.w["a"]["ws"] = d.w["b"]["ws"] = 5
            state.append({"kind": "apply", "placements": [{"name": n, "workspace": 5} for n in "abcde"]})
            for x in d.w.values():
                x["ws"] = 3
            inv = d.collect()
            self.assertIs(inv["restart"], False)
            self.assertEqual({w["restore_to"] for w in inv["windows"]}, {None})
            self.assertTrue(apply.validate(full_plan(d, a={"action": "restore"}), inv))

    def test_one_reopened_window_on_a_busy_workspace_is_not_a_restart(self):
        # 'e' (logged on 6) is closed and reopened on 3, where the rest live
        # with their old ids: one new id is not a restart.
        with FakeDesktop({"a": ("a", 3, "x"), "b": ("b", 3, "x"), "c": ("c", 3, "x"), "d": ("d", 3, "x"),
                          "e": ("e", 6, "x")}) as d:
            apply.apply(full_plan(d), dry=False)
            d.w["e2"] = dict(d.w.pop("e"), ws=3)
            inv = d.collect()
            self.assertEqual((inv["restart"], inv["restart_workspace"]), (False, None))
            self.assertEqual({w["restore_to"] for w in inv["windows"]}, {None})

    def test_no_restart_for_many_new_windows_with_new_names(self):
        with FakeDesktop({"a": ("a", 3, "x"), "b": ("b", 6, "y")}) as d:
            apply.apply(full_plan(d), dry=False)
            for i in "nopq":
                d.w[i] = dict(name=i, ws=4, repo="z")
            d.w["a"]["ws"] = d.w["b"]["ws"] = 4
            self.assertIs(d.collect()["restart"], False)

    def test_mixed_pile(self):
        # One window escaped the pile, one new window opened on it, the two
        # that live on 7 now share a name: the pile is still found, and only
        # the clean ones restore.
        with self.settled(on=7) as d:
            d.w["re"]["ws"] = 11
            d.w["new"] = dict(name="brand new", ws=7, repo="q")
            d.w["rrel2"]["name"] = "rel"
            inv = d.collect()
            self.assertEqual((inv["restart"], inv["restart_workspace"]), (True, 7))
            w = {x["id"]: x for x in inv["windows"]}
            self.assertEqual({i: x["restore_to"] for i, x in w.items() if x["restore_to"] is not None},
                             {"rjan": 1, "ra": 3, "rb": 6, "rc": 6, "rt": 10})
            self.assertIsNone(w["re"]["restore_to"])  # already home
            for i in ("rrel", "rrel2", "new"):
                problems = apply.validate(self.restores(d, **{i: {"action": "restore"}}), inv)
                self.assertTrue(problems, i)
            # Already home: a restore of it is a harmless no-op.
            code, out = apply.apply(self.restores(d, re={"action": "restore"}), dry=False)
            self.assertEqual(code, 0, out)
            self.assertIn("'e' already on 11", out["report"])
            self.assertEqual({i: d.ws_of(i) for i in d.w},
                             {"rjan": 1, "ra": 3, "rb": 6, "rc": 6, "rt": 10, "re": 11,
                              "rrel": 7, "rrel2": 7, "new": 7})

    def test_pile_onto_the_busiest_workspace(self):
        # The pile is the workspace the user was on, often their busiest: 7
        # windows live on 7, 5 elsewhere, all piled on 7 with new ids.
        homes = {f"h{i}": 7 for i in range(7)} | {"a": 3, "b": 4, "c": 5, "d": 6, "e": 11}
        with FakeDesktop({i: (i, ws, None) for i, ws in homes.items()}) as d:
            apply.apply(full_plan(d), dry=False)
            d.restart(on=7)
            inv = d.collect()
            self.assertEqual((inv["restart"], inv["restart_workspace"]), (True, 7))
            self.assertEqual({w["name"]: w["restore_to"] for w in inv["windows"] if w["restore_to"]},
                             {"a": 3, "b": 4, "c": 5, "d": 6, "e": 11})

    def test_unknown_names_do_not_dilute_a_pile(self):
        # Four logged elsewhere, four sharing a default title (no last
        # workspace), all piled on 5.
        windows = {i: (i, ws, None) for i, ws in {"a": 3, "b": 4, "c": 6, "d": 11}.items()}
        with FakeDesktop(windows | {f"u{i}": ("✳ Claude Code", 2, None) for i in range(4)}) as d:
            apply.apply(full_plan(d), dry=False)
            d.restart(on=5)
            inv = d.collect()
            self.assertEqual((inv["restart"], inv["restart_workspace"]), (True, 5))
            self.assertEqual({w["name"]: w["restore_to"] for w in inv["windows"] if w["restore_to"]},
                             {"a": 3, "b": 4, "c": 6, "d": 11})

    def test_second_restart_onto_another_pile(self):
        with self.settled(on=7) as d:
            d.fail.add(("window", "move-to-workspace", "ow_ra", "3"))
            self.assertEqual(apply.apply(self.restores(d), dry=False)[0], 1)
            d.fail.clear()
            d.restart(prefix="s", on=5)  # before the next run, onto 5
            inv = d.collect()
            self.assertEqual(inv["restart_workspace"], 5)
            a = next(w for w in inv["windows"] if w["name"] == "a")
            self.assertEqual((a["restore_to"], a["restore_from"]), (3, 5))
            code, out = apply.apply(self.restores(d), dry=False)
            self.assertEqual((code, self.where(d)), (0, self.HOME), out)

    def test_carried_placement_is_for_the_same_window(self):
        with self.settled(on=7) as d:
            d.fail.add(("window", "move-to-workspace", "ow_rjan", "1"))
            self.assertEqual(apply.apply(self.restores(d), dry=False)[0], 1)
            d.fail.clear()
            self.assertEqual(state.last_placements()["jan"]["id"], "rjan")
            self.assertEqual(self.windows(d)["jan"]["restore_to"], 1)
            # 'jan' is closed and a new window takes its name, on the pile.
            del d.w["rjan"]
            d.w["other"] = dict(name="jan", ws=7, repo=None)
            self.assertIsNone(self.windows(d)["jan"]["restore_to"])

    def test_legacy_carried_placement_never_goes_to_one(self):
        state.append({"kind": "apply", "snapshot": ["a", "b"], "placements": [
            {"name": "a", "workspace": 1, "carried": True, "pile": 3},
            {"name": "b", "workspace": 4, "carried": True, "pile": 3}]})
        with FakeDesktop({"a": ("a", 3, None), "b": ("b", 3, None)}) as d:
            w = self.windows(d)
            self.assertEqual((w["a"]["restore_to"], w["b"]["restore_to"]), (None, 4))

    def test_unverified_carried_placement_keeps_its_pile(self):
        with self.settled(on=7) as d:
            d.fail.add(("window", "move-to-workspace", "ow_ra", "3"))
            apply.apply(self.restores(d), dry=False)
            d.fail.clear()
            real = d.collect
            def unmatched():
                inv = real()
                for w in inv["windows"]:
                    if w["id"] == "ra":
                        w.update(omniwm_match="none", omniwm_id=None, omniwm_workspace=None,
                                 omniwm_candidates=[], maybe_user_workspace=True)
                return inv
            inventory.collect = unmatched
            apply.apply(full_plan(d, ra={"action": "skip"}), dry=False)
            inventory.collect = real
            p = state.last_placements()["a"]
            self.assertEqual((p["workspace"], p["carried"], p["pile"], p["id"]), (3, True, 7, "ra"))
            self.assertEqual(self.windows(d)["a"]["restore_to"], 3)

    def test_failed_undo_of_a_restore_onto_one_stays_put(self):
        with self.settled(on=7) as d:
            self.assertEqual(apply.apply(self.restores(d), dry=False)[0], 0)
            d.fail.add(("window", "move-to-workspace", "ow_rjan", "7"))
            code, out = apply.undo(dry=False)
            self.assertEqual(code, 1)
            self.assertEqual((d.ws_of("rjan"), d.ws_of("ra")), (1, 7))
            p = state.last_placements()["jan"]
            self.assertEqual((p["workspace"], p["carried"]), (1, False))
            d.fail.clear()
            self.assertEqual(apply.undo(dry=False)[0], 0)
            self.assertEqual(d.ws_of("rjan"), 7)

    def test_the_share_is_at_least_three_quarters(self):
        state.append({"kind": "apply", "snapshot": [], "placements": [
            {"name": n, "workspace": ws} for n, ws in [("a", 3), ("b", 4), ("c", 5), ("d", 6), ("e", 6)]]})
        with FakeDesktop({"a": ("a", 7, None), "b": ("b", 7, None), "c": ("c", 7, None), "d": ("d", 6, None)}) as d:
            self.assertEqual(d.collect()["restart_workspace"], 7)  # 3 of 4: exactly 75%
            d.w["e"] = dict(name="e", ws=6, repo=None)
            self.assertIsNone(d.collect()["restart_workspace"])  # 3 of 5

    def test_pile_below_the_share_is_not_a_restart(self):
        # 7 is busy with windows that live there; with the others not piled,
        # under 75% of the windows are on it.
        with self.settled(on=7) as d:
            for i in ("ra", "rb", "rc", "rt"):
                d.w[i[1:]] = dict(d.w.pop(i), ws=self.HOME[i[1:]])  # these never restarted
            for i in ("x1", "x2", "x3"):
                d.w[i] = dict(name=i, ws=7, repo="rel")
            inv = d.collect()
            self.assertIs(inv["restart"], False)  # jan, e back of 6 on 7
            self.assertEqual({w["restore_to"] for w in inv["windows"]}, {None})

    def test_window_on_one_is_not_off_a_pile_elsewhere(self):
        with self.settled(on=7) as d:
            d.w["ra"]["ws"] = 1  # a stray on 1, new id, logged on 3
            inv = d.collect()
            self.assertEqual(inv["restart_workspace"], 7)
            a = next(w for w in inv["windows"] if w["id"] == "ra")
            self.assertIsNone(a["restore_to"])
            problems = apply.validate(self.restores(d, ra={"action": "restore"}), inv)
            self.assertTrue(any("'a'" in p and "pile on workspace 7" in p and "must be 'skip'" in p
                                for p in problems), problems)
            self.assertEqual(apply.validate(self.restores(d, ra={"action": "skip"}), inv), [])

    def test_restore_into_one_only_to_its_last_workspace(self):
        with self.settled(on=7) as d:
            inv = d.collect()
            for to in (2, 7, 10, None):
                self.assertTrue(apply.validate(self.restores(d, rjan={"action": "restore", "to": to}), inv), to)
            self.assertEqual(apply.validate(self.restores(d, rjan={"action": "restore", "to": 1}), inv), [])
            # Nothing else may go to 1: move refuses it outright.
            self.assertTrue(apply.validate(self.restores(d, ra={"action": "move", "to": 1}), inv))

    def test_restore_into_one_is_rechecked(self):
        cases = {
            "left the pile": lambda desk: desk.w["rjan"].update(ws=5),
            "renamed to a duplicate": lambda desk: desk.w["rb"].update(name="jan"),
            "restore_to changed": lambda desk: state.append(
                {"kind": "apply", "placements": [{"name": "jan", "workspace": 4, "repo": "release"}]}),
        }
        for why, act in cases.items():
            with self.subTest(why), self.settled(on=7) as d:
                plan = self.restores(d)
                real, calls = inventory.collect, []
                def acted():
                    calls.append(1)
                    if len(calls) == 2:  # the re-check, after validation
                        act(d)
                    return real()
                inventory.collect = acted
                code, out = apply.apply(plan, dry=False)
                self.assertEqual(code, 1, out)
                self.assertTrue(any("didn't restore 'jan'" in f for f in out["failed"]), out)
                self.assertNotEqual(d.ws_of("rjan"), 1)
                reset_log()

    def test_failed_restore_off_seven_is_carried(self):
        with self.settled(on=7) as d:
            d.fail.add(("window", "move-to-workspace", "ow_ra", "3"))
            code, out = apply.apply(self.restores(d), dry=False)
            self.assertEqual(code, 1)
            placement = next(p for p in state.read_log()[-1]["placements"] if p["name"] == "a")
            self.assertEqual((placement["workspace"], placement["carried"], placement["pile"]), (3, True, 7))
            d.fail.clear()
            inv = d.collect()
            self.assertIs(inv["restart"], False)
            a = next(w for w in inv["windows"] if w["id"] == "ra")
            self.assertEqual((a["restore_to"], a["restore_from"]), (3, 7))
            code, out = apply.apply(full_plan(d, ra={"action": "restore"}), dry=False)
            self.assertEqual((code, d.ws_of("ra")), (0, 3), out)

    def test_carried_window_moved_off_its_pile_is_not_restored(self):
        with self.settled(on=7) as d:
            d.fail.add(("window", "move-to-workspace", "ow_ra", "3"))
            apply.apply(self.restores(d), dry=False)
            d.fail.clear()
            d.w["ra"]["ws"] = 5  # the user put it somewhere by hand
            a = self.windows(d)["a"]
            self.assertIsNone(a["restore_to"])
            d.w["ra"]["ws"] = 1  # or onto 1: never pulled off it
            self.assertIsNone(self.windows(d)["a"]["restore_to"])

    def test_undo_restore_into_one_needs_the_same_window(self):
        for why in ("renamed", "duplicate name"):
            with self.subTest(why), self.settled(on=7) as d:
                self.assertEqual(apply.apply(self.restores(d), dry=False)[0], 0)
                if why == "renamed":
                    d.w["rjan"]["name"] = "mine now"
                else:
                    d.w["dup"] = dict(name="jan", ws=1, repo="release")
                apply.undo(dry=False)
                self.assertEqual(d.ws_of("rjan"), 1)  # left on 1
                self.assertEqual(d.ws_of("ra"), 7)  # the rest went back
                reset_log()

    def test_undo_rejects_out_of_bounds_restores(self):
        with self.settled(on=7) as d:
            d.w["ra"]["ws"] = 3
            for bad in ({"id": "ra", "name": "a", "from": 3, "to": 3}, {"id": "ra", "name": "a", "from": 12, "to": 3},
                        {"id": "ra", "name": "a", "from": "7", "to": 3}, {"id": "ra", "name": "a", "from": 7, "to": 0}):
                state.append({"kind": "apply", "restores": [bad]})
                code, out = apply.undo(dry=False)
                self.assertEqual((code, len(out["ignored"]), d.ws_of("ra")), (0, 1, 3), bad)

    def test_carried_from_another_pile_does_not_make_a_restart(self):
        # Carried off a pile on 1, but now (same ids) on 7 by hand: not back
        # from a restart on 7.
        state.append({"kind": "apply", "snapshot": ["a", "b", "c", "d", "e"], "placements": [
            {"name": "a", "workspace": 3, "carried": True, "pile": 1},
            {"name": "b", "workspace": 4, "carried": True},
            {"name": "c", "workspace": 5, "carried": True, "pile": 1},
            {"name": "d", "workspace": 7}, {"name": "e", "workspace": 7}]})
        with FakeDesktop({i: (i, 7, None) for i in "abcde"}) as d:
            inv = d.collect()
            self.assertIs(inv["restart"], False)
            self.assertEqual({w["restore_to"] for w in inv["windows"]}, {None})

    def test_unlocatable_window_does_not_count_toward_a_pile(self):
        # 3 of 5 on 7 is 60%; a window whose title is shared with one that
        # has no workspace could be anywhere, so it doesn't make it 80%.
        state.append({"kind": "apply", "snapshot": [], "placements": [
            {"name": n, "workspace": ws} for n, ws in [("a", 3), ("b", 4), ("c", 5), ("d", 6)]]})
        windows = [win(i, None, ws) for i, ws in [("a", 7), ("b", 7), ("c", 7), ("d", 6)]]
        windows.append(win("u", None, None, omniwm_match="ambiguous", omniwm_id=None,
                           omniwm_candidates=[7], maybe_user_workspace=True))
        inventory.flag(windows, workspaces())
        self.assertIsNone(inventory.recovery(windows))
        windows[-1]["maybe_user_workspace"] = False  # all sharers on 7: it's on 7
        self.assertEqual(inventory.recovery(windows), 7)

    def test_inconsistent_inventory_restore_is_refused(self):
        # validate() doesn't trust the inventory's restore_to blindly.
        bad = {"restore_from 5, on 7": dict(restore_from=5), "restore_to 4, last 3": dict(restore_to=4),
               "restore_to off 1-11": dict(restore_to=12, last_workspace=12),
               "restore_from = restore_to": dict(restore_to=7, last_workspace=7)}
        for why, change in bad.items():
            with self.subTest(why), self.settled(on=7) as d:
                inv = d.collect()
                a = next(w for w in inv["windows"] if w["id"] == "ra")
                self.assertEqual((a["restore_to"], a["restore_from"]), (3, 7))
                a.update(change)
                problems = apply.validate(self.restores(d), inv)
                self.assertTrue(any(p.startswith("'a'") for p in problems), problems)
                reset_log()

    def test_restore_and_unrestore_guards(self):
        v = {"id": "ra", "name": "a", "omniwm_workspace": 7, "omniwm_match": "ok", "omniwm_id": "ow_ra",
             "restore_to": 3, "restore_from": 7, "last_workspace": 3}
        self.assertIsNone(apply.unsafe_to_restore(dict(v), v, 3, [v]))
        for why, fresh, validated in [
                ("moved off the pile", dict(v, omniwm_workspace=5), v),
                ("pile changed", dict(v, restore_from=5), v),
                ("validated off its pile", v, dict(v, omniwm_workspace=5)),
                ("validated with no restore_to", v, dict(v, restore_to=None, restore_from=None))]:
            self.assertTrue(apply.unsafe_to_restore(fresh, validated, 3, [fresh]), why)
        # Names can differ from titles, so these are checked on their own.
        for why, others in [("duplicate name", [dict(v, id="x", omniwm_id="ow_x")]),
                            ("shared OmniWM window", [dict(v, id="x", name="x")])]:
            self.assertTrue(apply.unsafe_to_restore(dict(v), v, 3, [v] + others), why)
        self.assertTrue(apply.unsafe_to_restore(dict(v, floating=True), v, 3, [v]), "floating")
        self.assertTrue(apply.unsafe_to_restore(dict(v, scratchpad=True), v, 3, [v]), "scratchpad")
        w = dict(v, omniwm_workspace=3)
        self.assertIsNone(apply.unsafe_to_unrestore(w, [w]))
        # Names can differ from titles (titles lag), so a duplicate name is
        # checked on its own, not only through the title match.
        self.assertTrue(apply.unsafe_to_unrestore(w, [w, dict(w, id="x", omniwm_id="ow_x")]))
        self.assertTrue(apply.unsafe_to_unrestore(w, [w, dict(w, id="x", name="x")]))
        self.assertTrue(apply.unsafe_to_unrestore(dict(w, floating=True), [w]))

    def test_hand_written_restore_cannot_pull_a_window_off_one(self):
        with FakeDesktop({"mine": ("mine", 1, "r"), "x": ("x", 3, "r")}) as d:
            rs = {"id": "mine", "name": "mine", "from": 5, "to": 1}
            for placements in (None, [], [{"name": "mine", "workspace": 5}],
                               [{"name": "mine", "workspace": 1, "carried": True, "pile": 5}],
                               [{"name": "mine", "workspace": 1}, {"name": "mine", "workspace": 1}]):
                entry = {"kind": "apply", "restores": [rs]}
                if placements is not None:
                    entry["placements"] = placements
                state.append(entry)
                code, out = apply.undo(dry=False)
                self.assertEqual((code, d.ws_of("mine")), (0, 1), placements)
                self.assertTrue(out.get("ignored"), placements)
            # A real restore onto 1 records the window there when the run ends.
            state.append({"kind": "apply", "restores": [rs], "placements": [{"name": "mine", "workspace": 1}]})
            self.assertEqual(apply.undo(dry=False)[0], 0)
            self.assertEqual(d.ws_of("mine"), 5)

    def test_reopened_window_on_one_is_not_a_restart(self):
        # 'notes' (logged on 5) is closed; a new 'notes' (same repo) and a new
        # 'y' open on 1, next to 'jan', which kept its id.
        with FakeDesktop({"jan": ("jan", 1, "rel"), "notes": ("notes", 5, "n")}) as d:
            apply.apply(full_plan(d), dry=False)
            del d.w["notes"]
            d.w["n2"] = dict(name="notes", ws=1, repo="n")
            d.w["y"] = dict(name="y", ws=1, repo="y")
            inv = d.collect()
            self.assertEqual((inv["restart"], inv["restart_workspace"]), (False, None))
            self.assertEqual({w["restore_to"] for w in inv["windows"]}, {None})

    def test_reopened_window_is_not_offered_onto_one(self):
        # The same on 3, with 'notes' logged on 1: no brand-new window onto 1.
        with FakeDesktop({"jan": ("jan", 3, "rel"), "notes": ("notes", 1, "n")}) as d:
            apply.apply(full_plan(d), dry=False)
            del d.w["notes"]
            d.w["n2"] = dict(name="notes", ws=3, repo="n")
            d.w["y"] = dict(name="y", ws=3, repo="y")
            inv = d.collect()
            self.assertEqual((inv["restart"], inv["restart_workspace"]), (False, None))
            self.assertEqual({w["restore_to"] for w in inv["windows"]}, {None})

    def test_reopened_windows_on_a_pool_workspace_are_not_a_restart(self):
        # 'jan' and 'a' closed and reopened (same names and repos) on 5, with
        # a new 'scratch', next to 'b', which kept its id.
        with FakeDesktop({"jan": ("jan", 1, "rel"), "a": ("a", 3, "x"), "b": ("b", 5, "y")}) as d:
            apply.apply(full_plan(d), dry=False)
            d.w = {"n1": dict(name="jan", ws=5, repo="rel"), "n2": dict(name="a", ws=5, repo="x"),
                   "b": d.w["b"], "n3": dict(name="scratch", ws=5, repo="y")}
            inv = d.collect()
            self.assertEqual((inv["restart"], inv["restart_workspace"]), (False, None))
            self.assertEqual({w["restore_to"] for w in inv["windows"]}, {None})

    def test_a_pile_of_unknown_names_is_not_a_restart(self):
        # Every window on 5 is new, but the log knows only three of the six.
        with FakeDesktop({"a": ("a", 3, "x"), "b": ("b", 4, "y"), "c": ("c", 6, "y")}) as d:
            apply.apply(full_plan(d), dry=False)
            d.restart(on=5)
            for i in "pqr":
                d.w[i] = dict(name=i, ws=5, repo="z")
            self.assertIs(d.collect()["restart"], False)
            del d.w["r"]
            self.assertIs(d.collect()["restart"], False)  # 3 of 5
            del d.w["q"]
            self.assertIs(d.collect()["restart"], True)  # 3 of 4

    def test_reopened_windows_on_a_busy_workspace_are_not_a_restart(self):
        # 'a', 'b' and 'c' closed and reopened on 6, where two windows live
        # with their old ids: three came back, but a restart renews them all.
        homes = {"a": 3, "b": 4, "c": 11, "d": 6, "e": 6}
        with FakeDesktop({i: (i, ws, None) for i, ws in homes.items()}) as d:
            apply.apply(full_plan(d), dry=False)
            for i in "abc":
                d.w["n" + i] = dict(d.w.pop(i), ws=6)
            inv = d.collect()
            self.assertEqual((inv["restart"], inv["restart_workspace"]), (False, None))
            self.assertEqual({w["restore_to"] for w in inv["windows"]}, {None})

    def test_windows_bound_for_one_do_not_prove_a_restart(self):
        # Only windows that go onto 1 came back: that is the claim to prove,
        # so it can't be the evidence.
        with FakeDesktop({"jan": ("jan", 1, "rel"), "k": ("k", 1, "rel"),
                          "r1": ("r1", 7, "r"), "r2": ("r2", 7, "r")}) as d:
            apply.apply(full_plan(d), dry=False)
            d.restart(on=7)
            inv = d.collect()
            self.assertIs(inv["restart"], False)
            self.assertEqual({w["restore_to"] for w in inv["windows"]}, {None})

    def test_restart_after_the_only_run_was_undone(self):
        with FakeDesktop({"jan": ("jan", 1, "rel"), "a": ("a", 3, "x"), "b": ("b", 6, "y"),
                          "c": ("c", 6, "y")}) as d:
            self.assertEqual(apply.apply(full_plan(d, c={"action": "move", "to": 5}), dry=False)[0], 0)
            self.assertEqual(apply.undo(dry=False)[0], 0)
            self.assertIsNone(state.last_snapshot())
            d.restart(on=1)
            inv = d.collect()
            self.assertEqual((inv["restart"], inv["restart_workspace"]), (True, 1))
            self.assertEqual({w["name"]: w["restore_to"] for w in inv["windows"] if w["restore_to"]},
                             {"a": 3, "b": 6, "c": 6})

    def test_the_pile_has_no_misplaced_or_home_flags(self):
        # On a pile, the mix of windows says nothing about where they belong.
        windows = {"jan": ("jan", 1, "release"), "a": ("a", 3, "x"), "a2": ("a2", 3, "x"),
                   "rel": ("rel", 7, "rel"), "rel2": ("rel2", 7, "rel")}
        with FakeDesktop(windows) as d:
            plan = full_plan(d)
            plan["workspaces"] = [{"number": 3, "label": "3 x", "repos": ["x"]},
                                  {"number": 7, "label": "F2 rel", "repos": ["rel"]}]
            self.assertEqual(apply.apply(plan, dry=False)[0], 0)
            d.restart(on=7)
            inv = d.collect()
            self.assertEqual(inv["restart_workspace"], 7)
            for w in inv["windows"]:
                self.assertEqual((w["misplaced"], w["home"]), (None, None), w["name"])
            self.assertEqual(apply.validate(self.restores(d), inv), [])

    def test_hand_written_restore_cannot_push_a_window_onto_one(self):
        with FakeDesktop({"jan": ("jan", 1, "rel"), "a": ("a", 5, "x"), "b": ("b", 6, "y")}) as d:
            rs = {"id": "a", "name": "a", "from": 1, "to": 5}
            for placements in (None, [], [{"name": "a", "workspace": 1}],
                               [{"name": "a", "workspace": 5, "carried": True, "pile": 1}],
                               [{"name": "a", "workspace": 5}, {"name": "a", "workspace": 5}]):
                entry = {"kind": "apply", "restores": [rs], "snapshot": ["a", "b", "jan"]}
                if placements is not None:
                    entry["placements"] = placements
                state.append(entry)
                code, out = apply.undo(dry=False)
                self.assertEqual((code, d.ws_of("a")), (0, 5), placements)
                self.assertTrue(out.get("ignored"), placements)
            # A real restore off 1 records the window where it went.
            state.append({"kind": "apply", "restores": [rs], "placements": [{"name": "a", "workspace": 5}]})
            self.assertEqual(apply.undo(dry=False)[0], 0)
            self.assertEqual(d.ws_of("a"), 1)

    def test_hand_written_carry_onto_one_is_not_restorable(self):
        with FakeDesktop({"jan": ("jan", 1, "rel"), "a": ("a", 5, "x"), "b": ("b", 6, "y"),
                          "c": ("c", 7, "z")}) as d:
            state.append({"kind": "apply", "snapshot": ["a", "b", "c", "jan"], "placements": [
                {"name": "a", "workspace": 1, "carried": True, "pile": 5, "id": "a"},
                {"name": "b", "workspace": 6}, {"name": "c", "workspace": 7}, {"name": "jan", "workspace": 1}]})
            inv = d.collect()
            self.assertIs(inv["restart"], False)
            self.assertEqual({w["restore_to"] for w in inv["windows"]}, {None})
            self.assertTrue(apply.validate(full_plan(d, a={"action": "restore"}), inv))
            self.assertEqual(apply.apply(full_plan(d, a={"action": "restore"}), dry=False)[0], 2)
            self.assertEqual(d.ws_of("a"), 5)
        # Backed by an earlier placement on 1 only if that one names one window.
        # An unbacked one says nothing about where the window belongs: not 1.
        for earlier, ok in (([{"name": "a", "workspace": 1}, {"name": "a", "workspace": 1}], False),
                            ([{"name": "a", "workspace": 3}], False), ([{"name": "a", "workspace": 1}], True)):
            reset_log()
            state.append({"kind": "apply", "placements": earlier})
            state.append({"kind": "apply", "snapshot": ["a"], "placements": [
                {"name": "a", "workspace": 1, "carried": True, "pile": 5, "id": "a"}]})
            self.assertEqual(state.last_placements().get("a", {}).get("carried"), ok or None, earlier)

    def test_retried_undo_moves_a_window_already_renamed_back(self):
        # The first undo renamed 'alloc' back to 'junk' but couldn't move it:
        # the retry still knows it by its name from before the run.
        with FakeDesktop({"a": ("junk", 6, "x"), "b": ("b", 2, "x"), "c": ("c", 3, "y")}) as d:
            plan = full_plan(d, a={"action": "move", "to": 2, "rename": "alloc"})
            self.assertEqual(apply.apply(plan, dry=False)[0], 0)
            d.fail.add(("window", "move-to-workspace", "ow_a", "6"))
            self.assertEqual(apply.undo(dry=False)[0], 1)
            self.assertEqual(d.w["a"], dict(name="junk", ws=2, repo="x"))
            d.fail.clear()
            code, out = apply.undo(dry=False)
            self.assertEqual((code, d.ws_of("a")), (0, 6), out)

    def test_undo_move_needs_the_same_name(self):
        # An id is a positional ref when cmux gives no UUID, and refs are
        # reused: a different window under the same id isn't moved back.
        with FakeDesktop({"a": ("a", 3, "x"), "b": ("b", 6, "y")}) as d:
            self.assertEqual(apply.apply(full_plan(d, a={"action": "move", "to": 5}), dry=False)[0], 0)
            d.w["a"]["name"] = "other"
            code, out = apply.undo(dry=False)
            self.assertEqual((code, d.ws_of("a")), (0, 5), out)
            self.assertTrue(any("its id is now 'other'" in line for line in out["report"]), out)

    def test_real_log_entry_parses(self):
        # The shape of the 2026-09-30 entry: placements with no carried/pile.
        state.append({"kind": "apply", "renames": [], "moves": [{"id": "X", "name": "pi", "from": 7, "to": 3}],
                      "restores": [], "layouts": [], "labels": [], "failed": [],
                      "placements": [{"name": "pi", "workspace": 3, "repo": "workspace"},
                                     {"name": "deb verifier", "workspace": 7, "repo": "release"},
                                     {"name": "π - mohib", "workspace": 10, "repo": "mohib"}]})
        self.assertEqual(spots(), {"pi": 3, "deb verifier": 7, "π - mohib": 10})
        self.assertFalse(any(p["carried"] for p in state.last_placements().values()))


if __name__ == "__main__":
    unittest.main(verbosity=1)
