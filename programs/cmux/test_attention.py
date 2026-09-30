"""Tests for attention.py's pure logic: keys, labels, the join, the hook.

Run: python3 test_attention.py   (no cmux, OmniWM or sketchybar needed)
"""

import json
import os
import tempfile
import unittest

os.environ["TRIAGE_STATE_DIR"] = tempfile.mkdtemp(prefix="attention-test-")
os.environ["CMUX_ATTENTION_DIR"] = tempfile.mkdtemp(prefix="attention-test-")

import attention as a  # noqa: E402


def ow_win(oid, wid, title, n, app="cmux"):
    return {"id": oid, "windowId": wid, "title": title, "app": {"name": app},
            "workspace": {"number": n}}


def ow_workspaces():
    return [{"number": n, "rawName": str(n), "displayName": d} for n, d in
            [(1, "💼"), (2, "2 alloc"), (5, "luke pr review"), (6, "F1 dotfiles"), (7, "F2"), (8, "8")]]


def tree(*windows):
    """windows: (window id, selected tab id, [(tab id, title)])"""
    return {"windows": [{"id": wid, "selected_workspace_id": sel,
                         "workspaces": [{"id": t, "title": title} for t, title in tabs]}
                        for wid, sel, tabs in windows]}


class Keys(unittest.TestCase):
    def test_digits_then_function_keys(self):
        self.assertEqual([a.key_for(n) for n in range(1, 11)],
                         ["1", "2", "3", "4", "5", "F1", "F2", "F3", "F4", "F5"])

    def test_out_of_range_is_none(self):
        for n in (0, 11, None, "6", 6.0, True):
            self.assertIsNone(a.key_for(n))

    def test_location(self):
        self.assertEqual(a.location(6, "dotfiles"), "Caps+F1 dotfiles")
        self.assertEqual(a.location(3, None), "Caps+3")
        self.assertIsNone(a.location(None, "x"))


class Labels(unittest.TestCase):
    def test_key_prefix_is_dropped(self):
        self.assertEqual(a.project_label(6, "F1 dotfiles", "6"), "dotfiles")
        self.assertEqual(a.project_label(2, "2 alloc", "2"), "alloc")
        self.assertEqual(a.project_label(6, "f1 dotfiles", "6"), "dotfiles")

    def test_label_that_is_only_the_key_has_no_project(self):
        self.assertIsNone(a.project_label(7, "F2", "7"))
        self.assertIsNone(a.project_label(8, "8", "8"))
        self.assertIsNone(a.project_label(8, None, "8"))

    def test_hand_label_is_kept_whole(self):
        self.assertEqual(a.project_label(5, "luke pr review", "5"), "luke pr review")
        self.assertEqual(a.project_label(1, "💼", "1"), "💼")
        # Starts with a word that is not this workspace's key.
        self.assertEqual(a.project_label(6, "F2 thing", "6"), "F2 thing")

    def test_newlines_and_length(self):
        self.assertEqual(a.project_label(6, "F1 a\nb\tc\x1b[31m", "6"), "a b c [31m")
        long = a.project_label(5, "x" * 80, "5")
        self.assertEqual(len(long), a.LABEL_CHARS)
        self.assertTrue(long.endswith("…"))


class Subtitle(unittest.TestCase):
    def test_prepends(self):
        self.assertEqual(a.prefix_subtitle("Waiting", "Caps+F1 dotfiles"), "Caps+F1 dotfiles · Waiting")

    def test_empty_subtitle(self):
        self.assertEqual(a.prefix_subtitle("", "Caps+3"), "Caps+3")
        self.assertEqual(a.prefix_subtitle(None, "Caps+3"), "Caps+3")
        self.assertEqual(a.prefix_subtitle(42, "Caps+3"), "Caps+3")

    def test_idempotent(self):
        once = a.prefix_subtitle("Waiting", "Caps+F1 dotfiles")
        self.assertEqual(a.prefix_subtitle(once, "Caps+2 alloc"), "Caps+2 alloc · Waiting")


class Mapping(unittest.TestCase):
    def test_every_tab_goes_where_its_window_is(self):
        t = tree(("W1", "t1", [("t1", "dotfiles"), ("t2", "other tab")]),
                 ("W2", "t3", [("t3", "alloc")]))
        ow = [ow_win("ow1", 11, "dotfiles", 6), ow_win("ow2", 12, "alloc", 2)]
        m = a.map_workspaces(t, ow, ow_workspaces(), {})
        self.assertEqual(m["t1"], {"window": "W1", "ow": "ow1", "ws": 6, "key": "F1", "label": "dotfiles"})
        self.assertEqual(m["t2"]["ws"], 6)
        self.assertEqual(m["t3"]["key"], "2")

    def test_live_title_wins_over_omniwm_stale_one(self):
        t = tree(("W1", "t1", [("t1", "renamed")]))
        ow = [ow_win("ow1", 11, "old name", 6)]
        m = a.map_workspaces(t, ow, ow_workspaces(), {11: "renamed"})
        self.assertEqual(m["t1"]["ws"], 6)

    def test_ambiguous_title_is_not_guessed(self):
        t = tree(("W1", "t1", [("t1", "same")]), ("W2", "t2", [("t2", "same")]))
        ow = [ow_win("ow1", 11, "same", 6), ow_win("ow2", 12, "same", 2)]
        m = a.map_workspaces(t, ow, ow_workspaces(), {})
        self.assertIsNone(m["t1"]["ws"])
        self.assertIsNone(m["t2"]["ow"])

    def test_non_cmux_window_with_same_title_is_ignored(self):
        t = tree(("W1", "t1", [("t1", "dotfiles")]))
        ow = [ow_win("ow1", 11, "dotfiles", 6), ow_win("ow9", 19, "dotfiles", 3, app="Google Chrome")]
        self.assertEqual(a.map_workspaces(t, ow, ow_workspaces(), {})["t1"]["ws"], 6)

    def test_garbage_in(self):
        self.assertEqual(a.map_workspaces(None, None, None, None), {})
        self.assertEqual(a.map_workspaces({"windows": [None, 3, {"workspaces": [None]}]}, [], [], {}), {})
        m = a.map_workspaces(tree(("W1", "missing", [("t1", "x")])), None, None, None)
        self.assertIsNone(m["t1"]["ws"])


def sessions(*rows, active=None):
    """rows: (session id, workspace, lifecycle, pid)"""
    doc = {"sessions": {sid: {"workspaceId": ws, "agentLifecycle": life, "pid": pid}
                        for sid, ws, life, pid in rows}}
    doc["activeSessionsByWorkspace"] = active if active is not None else {
        ws: {"sessionId": sid} for sid, ws, _, _ in rows}
    return doc


class Waiting(unittest.TestCase):
    def test_needs_input(self):
        doc = sessions(("s1", "A", "needsInput", 1), ("s2", "B", "running", 2), ("s3", "C", "idle", 3))
        self.assertEqual(a.waiting_workspaces(doc, {"A", "B", "C"}, alive=lambda p: True), {"A"})

    def test_closed_workspace_does_not_count(self):
        doc = sessions(("s1", "A", "needsInput", 1))
        self.assertEqual(a.waiting_workspaces(doc, {"B"}, alive=lambda p: True), set())

    def test_superseded_session_does_not_count(self):
        # The store keeps an old session that asked a question, then a new
        # session took over the workspace (the case seen live).
        doc = sessions(("old", "A", "needsInput", 1), ("new", "A", "running", 2),
                       active={"A": {"sessionId": "new"}})
        self.assertEqual(a.waiting_workspaces(doc, {"A"}, alive=lambda p: True), set())

    def test_dead_process_does_not_count(self):
        doc = sessions(("s1", "A", "needsInput", 1))
        self.assertEqual(a.waiting_workspaces(doc, {"A"}, alive=lambda p: False), set())

    def test_malformed_store(self):
        for doc in (None, [], {"sessions": []}, {"sessions": {"x": None}},
                    {"sessions": {"x": {"agentLifecycle": "needsInput"}}, "activeSessionsByWorkspace": []}):
            self.assertEqual(a.waiting_workspaces(doc, {"A"}), set())

    def test_alive_real_pid(self):
        self.assertTrue(a._alive(os.getpid()))
        self.assertTrue(a._alive(None))


class Unread(unittest.TestCase):
    def test_only_unread_on_live_workspaces(self):
        notes = [{"workspace_id": "A", "is_read": False}, {"workspace_id": "B", "is_read": True},
                 {"workspace_id": "gone", "is_read": False}, None, {"is_read": False}]
        self.assertEqual(a.unread_workspaces(notes, {"A", "B"}), {"A"})
        self.assertEqual(a.unread_workspaces(None, {"A"}), set())


class Summary(unittest.TestCase):
    def mapping(self):
        return {"A": {"ow": "owA", "ws": 6}, "B": {"ow": "owB", "ws": 2},
                "C": {"ow": None, "ws": None}, "D": {"ow": "owA", "ws": 6}}

    def test_waiting_beats_unread(self):
        s = a.summarize(self.mapping(), need={"A"}, unread={"A", "B"})
        self.assertEqual((s["need"]["count"], s["need"]["keys"]), (1, "F1"))
        self.assertEqual((s["done"]["count"], s["done"]["keys"]), (1, "2"))
        self.assertEqual(s["windows"], {"owA": "need", "owB": "unread"})

    def test_window_with_one_waiting_tab_is_waiting(self):
        s = a.summarize(self.mapping(), need={"A"}, unread={"D"})
        self.assertEqual(s["windows"], {"owA": "need"})

    def test_unplaced_session_shows_question_mark(self):
        s = a.summarize(self.mapping(), need={"B", "C"}, unread=set())
        self.assertEqual(s["need"]["keys"], "2 ?")

    def test_keys_capped(self):
        self.assertEqual(a.format_keys([9, 1, 6, 3, 3]), "1 3 F1+")
        self.assertEqual(a.format_keys([]), "")
        self.assertEqual(a.format_keys([], unplaced=True), "?")

    def test_state_is_json(self):
        json.dumps(a.summarize(self.mapping(), {"A"}, {"B"}))


class Hook(unittest.TestCase):
    def policy(self, ws="A", subtitle="Completed in dotfiles"):
        return json.dumps({"notification": {"workspaceId": ws, "surfaceId": "s", "title": "Claude Code",
                                            "subtitle": subtitle, "body": "b"},
                           "effects": {"desktop": True, "sound": True}, "agent": {"kind": "claude"}})

    def state(self):
        return {"workspaces": {"A": {"ow": "owA", "ws": 6, "label": "dotfiles"},
                               "U": {"ow": None, "ws": None, "label": None}}}

    def test_prefixes_cached_location(self):
        out = json.loads(a.rewrite(self.policy(), self.state(), None, None))
        self.assertEqual(out["notification"]["subtitle"], "Caps+F1 dotfiles · Completed in dotfiles")
        self.assertEqual(out["effects"], {"desktop": True, "sound": True})

    def test_live_omniwm_position_wins(self):
        # The window was moved to 2 since the daemon last looked.
        ow = [{"id": "owA", "workspace": {"number": 2}}]
        out = json.loads(a.rewrite(self.policy(), self.state(), ow, ow_workspaces()))
        self.assertEqual(out["notification"]["subtitle"], "Caps+2 alloc · Completed in dotfiles")

    def test_unknown_or_unplaced_workspace_is_unchanged(self):
        for ws in ("nope", "U", None):
            raw = self.policy(ws=ws)
            self.assertIs(a.rewrite(raw, self.state(), None, None), raw)

    def test_unicode_and_newlines_survive(self):
        raw = self.policy(subtitle='"quoted"\nline two ✳ 日本')
        out = json.loads(a.rewrite(raw, self.state(), None, None))
        self.assertEqual(out["notification"]["subtitle"], 'Caps+F1 dotfiles · "quoted"\nline two ✳ 日本')

    def test_odd_shapes_are_unchanged(self):
        for raw in ("[]", "{}", '{"notification": 3}', "null"):
            self.assertEqual(a.rewrite(raw, self.state(), None, None), raw)
        with self.assertRaises(ValueError):
            a.rewrite("not json", self.state(), None, None)


class Jump(unittest.TestCase):
    def test_newest_unread_on_a_waiting_workspace(self):
        notes = [
            {"id": "old", "workspace_id": "A", "is_read": False, "created_at": "2026-09-30T10:00:00Z"},
            {"id": "new", "workspace_id": "A", "is_read": False, "created_at": "2026-09-30T11:00:00Z"},
            {"id": "read", "workspace_id": "A", "is_read": True, "created_at": "2026-09-30T12:00:00Z"},
            {"id": "done", "workspace_id": "B", "is_read": False, "created_at": "2026-09-30T13:00:00Z"},
        ]
        self.assertEqual(a.pick_notification(notes, {"A"}), "new")
        self.assertIsNone(a.pick_notification(notes, {"C"}))
        self.assertIsNone(a.pick_notification(None, {"A"}))
        self.assertIsNone(a.pick_notification([{"workspace_id": "A", "is_read": False}], {"A"}))


class Debounce(unittest.TestCase):
    def test_trailing_edge(self):
        d = a.Debounce(0)
        d.done(0)
        d.event(10.0)
        d.event(10.2)
        self.assertFalse(d.due(10.5))
        self.assertTrue(d.due(10.2 + a.QUIET))

    def test_busy_stream_still_refreshes(self):
        d = a.Debounce(0)
        d.done(0)
        t = 10.0
        while t < 10.0 + a.MAX_WAIT:
            d.event(t)
            t += 0.1
        self.assertTrue(d.due(10.0 + a.MAX_WAIT))

    def test_safety(self):
        d = a.Debounce(0)
        self.assertTrue(d.due(0))
        d.done(0)
        self.assertFalse(d.due(a.SAFETY - 1))
        self.assertTrue(d.due(a.SAFETY))


class Events(unittest.TestCase):
    def test_counts_relevant_and_keeps_partial_line(self):
        ev = lambda name, typ="event": json.dumps({"type": typ, "name": name}).encode()  # noqa: E731
        chunk = b"\n".join([ev("notification.created"), ev("agent.hook.Stop"), ev("x", "heartbeat"),
                            ev("window.keyed"), b"{broken", b'{"type": "event", "name": "notif'])
        hits, rest = a.events_in(b"", chunk)
        self.assertEqual(hits, 2)
        hits, rest = a.events_in(rest, b'ication.read"}\n')
        self.assertEqual((hits, rest), (1, b""))

    def test_runaway_line_is_dropped(self):
        _, rest = a.events_in(b"", b"x" * ((1 << 20) + 1))
        self.assertEqual(rest, b"")


if __name__ == "__main__":
    unittest.main()
