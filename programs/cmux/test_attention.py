"""Tests for attention.py's pure logic: keys, labels, the join, the hook.

Run: python3 test_attention.py   (no cmux, OmniWM or sketchybar needed)
"""

import json
import os
import subprocess
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
        self.assertEqual([a.key_for(n) for n in range(1, 12)],
                         ["1", "2", "3", "4", "5", "F1", "F2", "F3", "F4", "F5",
                          "6"])

    def test_out_of_range_is_none(self):
        for n in (0, 12, None, "6", 6.0, True):
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
        self.assertEqual(a.waiting_workspaces(doc, {"A", "B", "C"}, alive=lambda p, st: True), {"A"})

    def test_closed_workspace_does_not_count(self):
        doc = sessions(("s1", "A", "needsInput", 1))
        self.assertEqual(a.waiting_workspaces(doc, {"B"}, alive=lambda p, st: True), set())

    def test_superseded_session_does_not_count(self):
        # The store keeps an old session that asked a question, then a new
        # session took over the workspace (the case seen live).
        doc = sessions(("old", "A", "needsInput", 1), ("new", "A", "running", 2),
                       active={"A": {"sessionId": "new"}})
        self.assertEqual(a.waiting_workspaces(doc, {"A"}, alive=lambda p, st: True), set())

    def test_dead_process_does_not_count(self):
        doc = sessions(("s1", "A", "needsInput", 1))
        self.assertEqual(a.waiting_workspaces(doc, {"A"}, alive=lambda p, st: False), set())

    def test_malformed_store(self):
        for doc in (None, [], {"sessions": []}, {"sessions": {"x": None}},
                    {"sessions": {"x": {"agentLifecycle": "needsInput"}}, "activeSessionsByWorkspace": []}):
            self.assertEqual(a.waiting_workspaces(doc, {"A"}), set())

    def test_alive_real_pid(self):
        self.assertTrue(a._alive(os.getpid()))
        self.assertTrue(a._alive(None))
        me = a._started(os.getpid())
        self.assertIsNotNone(me)
        self.assertTrue(a._alive(os.getpid(), me))

    def test_reused_pid_is_not_alive(self):
        # Same pid, different start time: another process took the pid.
        self.assertFalse(a._alive(os.getpid(), 1000.0, started=lambda p: 5000.0))
        self.assertTrue(a._alive(os.getpid(), 5001.0, started=lambda p: 5000.0))
        # Start time unknown: fall back to the bare pid check.
        self.assertTrue(a._alive(os.getpid(), 1000.0, started=lambda p: None))


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

    def test_output_is_ascii_even_with_lone_surrogate(self):
        raw = '{"notification": {"workspaceId": "A", "subtitle": "s", "body": "cut \\ud83d here"}}'
        out = a.rewrite(raw, self.state(), None, None)
        out.encode("ascii")  # would raise if a surrogate leaked through unescaped
        self.assertEqual(json.loads(out)["notification"]["body"], "cut \ud83d here")

    def test_hook_process_passes_bad_bytes_through(self):
        import subprocess
        import sys
        for data in (b'{"notification": {"subtitle": "\xff"}}', b"", b"not json"):
            out = subprocess.run([sys.executable, a.__file__, "hook"], input=data,
                                 capture_output=True, timeout=10)
            self.assertEqual((out.returncode, out.stdout), (0, data))

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


    def test_waiting_without_unread_goes_to_its_window(self):
        state = {"workspaces": {"A": {"window": "W1", "ws": 8}, "B": {"window": "W2", "ws": 3},
                                "C": {"window": None, "ws": 1}},
                 "need": {"workspaces": ["A", "B", "C", "gone"]}}
        self.assertEqual(a.pick_waiting(state), ("W2", "B"))
        self.assertIsNone(a.pick_waiting({"need": {"workspaces": []}}))
        self.assertIsNone(a.pick_waiting(None))
        self.assertIsNone(a.pick_waiting({"need": [], "workspaces": []}))


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


class OmniwmUnreachable(unittest.TestCase):
    """OmniWM running but omniwmctl failing: what a cask upgrade under a
    running app does, differently per release."""

    MISMATCH = "error: protocol_mismatch (server protocol 16, app 0.7.3)"  # 0.7.3 -> 0.7.4, exit 1
    NO_SOCKET = 'omniwmctl: Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"'  # 0.7.4 -> 0.7.5, exit 2

    def desktop(self, running=True, ping=("pong\n", ""), raises=None):
        """Stub subprocess.run for pgrep and omniwmctl ping."""
        calls = []

        def run(cmd, **kw):
            calls.append(cmd)
            if cmd[0] == "pgrep":
                return type("R", (), {"returncode": 0 if running else 1})()
            if raises:
                raise raises
            return type("R", (), {"stdout": ping[0], "stderr": ping[1], "returncode": 0})()
        real = a.subprocess.run
        a.subprocess.run = run
        self.addCleanup(setattr, a.subprocess, "run", real)
        return calls

    def tearDown(self):
        a.omniwm_failed, a.mismatch_reported = False, None

    def test_both_upgrade_failures_are_caught(self):
        for said in (self.MISMATCH, self.NO_SOCKET):
            with self.subTest(said=said):
                for ping in ((said + "\n", ""), ("", said + "\n")):  # stdout or stderr
                    self.desktop(ping=ping)
                    self.assertEqual(a.omniwm_unreachable(), said)

    def test_not_running_says_nothing_and_does_not_ping(self):
        calls = self.desktop(running=False, ping=("", self.NO_SOCKET))
        self.assertIsNone(a.omniwm_unreachable())
        self.assertEqual([c[0] for c in calls], ["pgrep"])
        self.assertEqual(calls[0][:4], ["pgrep", "-x", "-U", str(os.getuid())])

    def test_pong_is_fine(self):
        self.desktop()
        self.assertIsNone(a.omniwm_unreachable())

    def test_a_hung_ping_is_unreachable(self):
        self.desktop(raises=a.subprocess.TimeoutExpired("omniwmctl", 3))
        self.assertEqual(a.omniwm_unreachable(), "no answer")
        self.desktop(raises=OSError("gone"))
        self.assertIsNone(a.omniwm_unreachable())

    def test_failed_query_sets_the_flag_and_a_good_one_clears_it(self):
        real = a.run_json
        self.addCleanup(setattr, a, "run_json", real)
        a.run_json = lambda cmd, timeout: None
        self.assertIsNone(a.omniwm("workspaces", 1))
        self.assertTrue(a.omniwm_failed)
        a.run_json = lambda cmd, timeout: {"ok": True, "result": {"payload": {"workspaces": []}}}
        self.assertEqual(a.omniwm("workspaces", 1), [])
        self.assertFalse(a.omniwm_failed)

    def logged(self):
        lines = []
        real = a.log
        a.log = lambda *parts: lines.append(" ".join(map(str, parts)))
        self.addCleanup(setattr, a, "log", real)
        return lines

    def test_reported_once_per_episode(self):
        lines = self.logged()
        self.desktop(ping=("", self.NO_SOCKET))
        a.omniwm_failed = True
        a.report_mismatch()
        a.report_mismatch()
        self.assertEqual(len(lines), 1)
        self.assertIn("restart OmniWM", lines[0])
        self.assertIn("Code=2", lines[0])
        a.omniwm_failed = False  # it answers again
        a.report_mismatch()
        a.omniwm_failed = True  # and breaks again: a new episode
        a.report_mismatch()
        self.assertEqual(len(lines), 2)

    def test_a_failed_query_with_omniwm_not_running_says_nothing(self):
        lines = self.logged()
        self.desktop(running=False)
        a.omniwm_failed = True
        a.report_mismatch()
        self.assertEqual(lines, [])

    def test_reported_once_even_after_a_failed_refresh(self):
        lines = self.logged()
        self.desktop(ping=(self.MISMATCH + "\n", ""))
        real = a.compute
        self.addCleanup(setattr, a, "compute", real)

        def boom(previous):
            a.omniwm_failed = True
            raise ValueError("bad tree")
        a.compute = boom
        a.refresh(None)
        a.refresh(None)
        self.assertEqual(sum("restart OmniWM" in line for line in lines), 1)

    def test_note_once_per_episode(self):
        self.assertIn("restart OmniWM", a.mismatch_note(None, self.MISMATCH))
        self.assertIsNone(a.mismatch_note(self.MISMATCH, self.MISMATCH))
        self.assertIsNone(a.mismatch_note(self.MISMATCH, self.NO_SOCKET))
        self.assertIsNone(a.mismatch_note(self.MISMATCH, None))
        self.assertIsNone(a.mismatch_note(None, None))


class IpcCheck(unittest.TestCase):
    """programs/omniwm/ipc-check.sh, the activation warning, against fake
    pgrep and omniwmctl."""

    SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "omniwm", "ipc-check.sh")

    def check(self, running, ping_out, ping_code=0, ctl=True):
        d = tempfile.mkdtemp(prefix="ipc-check-")
        bins = os.path.join(d, "bin")
        os.mkdir(bins)

        def script(name, body):
            path = os.path.join(bins, name)
            with open(path, "w") as f:
                f.write("#!/bin/sh\n" + body + "\n")
            os.chmod(path, 0o755)
            return path
        script("pgrep", f"exit {0 if running else 1}")
        timeout = script("timeout", 'shift; exec "$@"')
        omniwmctl = script("omniwmctl", f"printf '%s\\n' '{ping_out}'; exit {ping_code}") if ctl \
            else os.path.join(bins, "missing")
        env = {"PATH": bins + ":/usr/bin:/bin", "OMNIWMCTL": omniwmctl, "TIMEOUT": timeout}
        out = subprocess.run(["/bin/sh", self.SCRIPT], capture_output=True, text=True, env=env)
        return out.returncode, out.stderr

    def test_warns_on_both_upgrade_failures(self):
        for said, code in ((OmniwmUnreachable.MISMATCH, 1), (OmniwmUnreachable.NO_SOCKET.replace("'", ""), 2)):
            with self.subTest(said=said):
                rc, err = self.check(True, said, code)
                self.assertEqual(rc, 0)
                self.assertIn("cannot reach it", err)
                self.assertIn(said, err)
                self.assertIn("restart it", err)

    def test_quiet_when_healthy_not_running_or_not_installed(self):
        self.assertEqual(self.check(True, "pong"), (0, ""))
        self.assertEqual(self.check(False, "omniwmctl: Error Domain=NSPOSIXErrorDomain Code=2", 2), (0, ""))
        self.assertEqual(self.check(True, "x", ctl=False), (0, ""))

if __name__ == "__main__":
    unittest.main()
