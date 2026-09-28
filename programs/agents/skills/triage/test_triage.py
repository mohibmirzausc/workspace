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
                      "labels": [{"workspace": 2, "to": "2 alloc", "repos": ["internal-allocations"]},
                                 {"workspace": 3, "to": "3 agents", "repos": ["workspace"]},
                                 {"workspace": 4, "to": "4 imogen", "repos": ["imogen-a", "imogen-b"]},
                                 {"workspace": 6, "to": "F1 dotfiles", "repos": ["workspace"]}]})
        w = self.flagged()
        self.assertTrue(w["allocmisc"]["new"])
        self.assertIn("its repo's windows are on workspace 2", w["allocmisc"]["misplaced"])
        flagged = {i for i, x in w.items() if x["misplaced"]}
        self.assertEqual(flagged, {"allocmisc"})  # nothing else, incl. the two-repo imogen project
        self.assertFalse(w["omni"]["new"])
        self.assertIsNone(w["omni"]["home"])  # dotfiles repo owns 3 and 6: no single home

    def test_hand_edited_label_drops_the_recorded_repo(self):
        state.append({"kind": "apply", "labels": [{"workspace": 6, "to": "F1 dotfiles", "repos": ["workspace"]}]})
        wss = workspaces()
        next(ws for ws in wss if ws["number"] == 6)["label"] = "F1 renamed"
        self.assertEqual(state.label_repos({ws["number"]: ws["label"] for ws in wss}), {})

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

    def test_unmatched_window_needs_a_rename_to_move(self):
        next(w for w in self.inv["windows"] if w["id"] == "pi")["omniwm_match"] = "ambiguous"
        self.assertTrue(apply.validate(self.plan(pi={"action": "review"}), self.inv))
        self.assertEqual(apply.validate(self.plan(pi={"action": "review", "rename": "pi shell"}), self.inv), [])

    def test_labels_carry_their_key(self):
        for n, label, ok in [(2, "2 alloc", True), (6, "F1 dotfiles", True), (10, "F5 review", True),
                             (6, "dotfiles", False), (6, "6 dotfiles", False), (2, "F1 alloc", False),
                             (7, "F2 a-very-long-name", False), (1, "1 mine", False)]:
            plan = self.plan()
            plan["workspaces"] = [{"number": n, "label": label}]
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
        state.append({"kind": "undo", "undoes": b["ts"]})
        self.assertEqual(state.last_undoable()["ts"], a["ts"])
        state.append({"kind": "undo", "undoes": a["ts"]})
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


if __name__ == "__main__":
    unittest.main(verbosity=1)
