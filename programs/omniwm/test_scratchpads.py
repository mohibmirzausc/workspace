"""Tests for scratchpads.py, against a fake omniwmctl.

Run: python3 -m unittest   (from programs/omniwm; no OmniWM needed)

FakeOmniWM models the parts of OmniWM 0.7.4 the script leans on, as read in
its source: opaque ids carry a per-launch session token (a stale one is
refused), slots hold several windows, assign acts on the focused window and
TOGGLES (assigning a window to the slot it is in releases it), an assigned
window is hidden unless its slot is showing, and focusing a window shows its
workspace on its display.
"""

import base64
import json
import os
import stat
import tempfile
import unittest
from unittest import mock

os.environ["OMNIWM_SCRATCHPADS_STATE"] = os.path.join(tempfile.mkdtemp(prefix="scratchpads-test-"), "s.json")

import scratchpads as sp  # noqa: E402

CHROME, OBSIDIAN = "com.google.Chrome", "md.obsidian"


def oid(token, pid, wid):
    return "ow_" + base64.urlsafe_b64encode(f"{token}:{pid}:{wid}".encode()).decode().rstrip("=")


class FakeOmniWM:
    def __init__(self, pid=88009, started="Fri Oct  2 18:59:02 2026", epoch=1000.0):
        self.pid, self.started, self.epoch = pid, started, epoch
        self.token = f"TOKEN-{pid}"
        self.running = True
        self.mismatch = False
        self.wins = {}        # (pid, wid) -> dict
        self.focus = None     # (pid, wid)
        self.displays = [{"id": "display:3", "ws": 3, "current": True, "owns": {1, 2, 3, 4, 5, 11}},
                         {"id": "display:1", "ws": 6, "current": False, "owns": {6, 7, 8, 9, 10}}]
        self.revealed = None
        self.calls = []
        self.focus_lag = 0    # focused-window polls before a focus lands
        self._lag = 0
        self._pending_focus = None
        self.on_focus = None  # hook(fake, key) after `window focus`, before it lands
        self.on_assign = None  # hook(fake, slot) before an assign is applied
        self.glitch_empty = False
        self.alive_pids = set()

    # -- setup ---------------------------------------------------------------

    def add(self, pid, wid, bundle, title, ws=3, slot=None, app=None):
        self.wins[(pid, wid)] = {"pid": pid, "windowId": wid, "bundleId": bundle,
                                 "app": app or (bundle or "java"), "title": title,
                                 "ws": ws, "slot": slot, "hidden": slot is not None}
        self.alive_pids.add(pid)
        return (pid, wid)

    def restart(self, pid=None, epoch=None):
        """A new OmniWM: new pid/start, new session token, every slot empty,
        hidden scratchpad windows come back as ordinary windows."""
        self.pid = pid or self.pid + 1
        self.started = f"Sat Oct  3 10:00:{self.pid % 60:02d} 2026"
        self.epoch = epoch if epoch is not None else self.epoch + 5000
        self.token = f"TOKEN-{self.pid}"
        self.running, self.mismatch, self.revealed = True, False, None
        for w in self.wins.values():
            w["slot"], w["hidden"] = None, False

    def instance(self):
        if not self.running:
            return None
        return {"pid": self.pid, "started": self.started, "epoch": self.epoch}

    def alive(self, pid):
        return pid in self.alive_pids

    # -- omniwmctl -----------------------------------------------------------

    def run(self, args, timeout=5.0):
        args = [a for a in args if a != "--json"]
        self.calls.append(args)
        if not self.running:
            return 1, json.dumps({"ok": False, "source": "cli", "code": "transport_failure",
                                  "message": "omniwmctl: connection refused"})
        if self.mismatch:
            return 1, json.dumps({"ok": False, "code": "protocol_mismatch", "kind": "query",
                                  "result": {"kind": "version", "payload": {
                                      "appVersion": "0.7.3", "protocolVersion": 16}}})
        if args[:2] == ["query", "windows"]:
            return self.ok({"windows": [] if self.glitch_empty else [self.snap(w) for w in self.wins.values()]})
        if args[:2] == ["query", "focused-window"]:
            if self._pending_focus is not None:
                if self._lag <= 0:
                    self.focus, self._pending_focus = self._pending_focus, None
                else:
                    self._lag -= 1
            w = self.wins.get(self.focus)
            return self.ok({"window": None if w is None else
                            {"id": oid(self.token, w["pid"], w["windowId"]), "pid": w["pid"], "title": w["title"]}})
        if args[:2] == ["query", "displays"]:
            return self.ok({"displays": [{"id": d["id"], "isCurrent": d["current"],
                                          "activeWorkspace": {"number": d["ws"]}} for d in self.displays]})
        if args[:2] == ["window", "focus"]:
            k = self.decode(args[2])
            if k == "stale":
                return self.fail("stale_window_id")
            if k not in self.wins:
                return self.fail("not_found")
            self.show_ws(self.wins[k]["ws"])
            self._pending_focus, self._lag = k, self.focus_lag
            if self.on_focus:
                self.on_focus(self, k)
            if self.focus_lag == 0 and self._pending_focus is not None:
                self.focus, self._pending_focus = self._pending_focus, None
            return self.ok({})
        if args[:3] == ["command", "scratchpad", "assign"]:
            n = int(args[3])
            if self.on_assign:
                self.on_assign(self, n)
            w = self.wins.get(self.focus)
            if w is None:
                return self.fail("not_found")
            if w["slot"] == n:
                if w["hidden"]:
                    return self.fail("not_found")
                w["slot"] = None  # toggles OUT
                return self.ok({})
            w["slot"], w["hidden"] = n, self.revealed != n
            if w["hidden"]:
                self.focus = None
            return self.ok({})
        if args[:2] == ["command", "switch-workspace"]:
            self.show_ws(int(args[2]))
            return self.ok({})
        raise AssertionError(f"unexpected omniwmctl call {args}")

    def ok(self, payload):
        return 0, json.dumps({"ok": True, "status": "success", "result": {"kind": "x", "payload": payload}})

    def fail(self, code):
        return 1, json.dumps({"ok": False, "status": "error", "code": code})

    def decode(self, value):
        raw = value[3:]
        token, pid, wid = base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)).decode().rsplit(":", 2)
        return "stale" if token != self.token else (int(pid), int(wid))

    def snap(self, w):
        app = {"name": w["app"]}
        if w["bundleId"]:
            app["bundleId"] = w["bundleId"]
        out = {"id": oid(self.token, w["pid"], w["windowId"]), "pid": w["pid"], "windowId": w["windowId"],
               "app": app, "title": w["title"], "workspace": {"number": w["ws"]},
               "isVisible": not w["hidden"]}
        if w["slot"] is not None:
            out["scratchpadIndex"] = w["slot"]
        return out

    def show_ws(self, n):
        for d in self.displays:
            if n in d["owns"]:
                d["ws"] = n
                for o in self.displays:
                    o["current"] = o is d

    # -- assertions ----------------------------------------------------------

    def slot_of(self, k):
        return self.wins[k]["slot"]

    def view(self):
        return [(d["id"], d["ws"], d["current"]) for d in self.displays], self.focus


class Base(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="scratchpads-test-")
        self.path = os.path.join(self.dir, "state.json")
        self.ow = FakeOmniWM()
        self.now = 100000.0
        patches = [mock.patch.object(sp, "run_ctl", lambda args, timeout=5.0: self.ow.run(args, timeout)),
                   mock.patch.object(sp, "sleep", lambda s: None),
                   mock.patch.object(sp, "log", lambda *p: self.logs.append(" ".join(map(str, p))))]
        self.logs = []
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def keeper(self):
        return sp.Keeper(path=self.path, instance=self.ow.instance, alive=self.ow.alive,
                         age=lambda pid: 1000.0, clock=lambda: self.now)

    def saved(self):
        with open(self.path) as f:
            return json.load(f)

    def saved_keys(self, doc=None):
        doc = doc or self.saved()
        return {int(s): sorted((e["pid"], e["windowId"]) for e in es) for s, es in doc["slots"].items()}

    def mtime(self):
        return os.stat(self.path).st_mtime_ns if os.path.exists(self.path) else None

    def log_has(self, text):
        return any(text in line for line in self.logs)


class Identity(unittest.TestCase):
    def test_decodes_a_real_id(self):
        # From the live machine: Chrome's window in slot 4.
        self.assertEqual(sp.decode_id("ow_QjczOUYyN0UtMDkxNC00MDJELTk0RjktOTBFMEQ5QjZERjkwOjU2MjQ5OjQyMDE4"),
                         (56249, 42018))

    def test_bad_ids(self):
        for v in (None, "", "ow_", "ow_!!!", "x_QjczOQ", 7, "ow_" + base64.urlsafe_b64encode(b"a:b:c").decode()):
            self.assertIsNone(sp.decode_id(v))

    def test_app_key_falls_back_to_name(self):
        self.assertEqual(sp.app_key({"bundleId": CHROME, "app": "Google Chrome"}), CHROME)
        self.assertEqual(sp.app_key({"bundleId": None, "app": "java"}), "name:java")
        self.assertIsNone(sp.app_key({"bundleId": None, "app": None}))


class Ctl(Base):
    def test_protocol_mismatch_json(self):
        self.ow.mismatch = True
        with self.assertRaises(sp.Unavailable) as cm:
            sp.windows()
        self.assertEqual(cm.exception.mismatch, {"appVersion": "0.7.3", "protocolVersion": 16})

    def test_protocol_mismatch_text(self):
        with mock.patch.object(sp, "run_ctl", lambda a, t=5.0: (1, "error: protocol_mismatch (server protocol 16, app 0.7.3)\n")):
            with self.assertRaises(sp.Unavailable) as cm:
                sp.windows()
        self.assertEqual(cm.exception.mismatch, {})

    def test_not_running_is_unavailable_not_rejected(self):
        self.ow.running = False
        with self.assertRaises(sp.Unavailable) as cm:
            sp.windows()
        self.assertIsNone(cm.exception.mismatch)

    def test_refusal_is_rejected(self):
        with self.assertRaises(sp.Rejected) as cm:
            sp.ctl("window", "focus", oid("OLD-TOKEN", 1, 2))
        self.assertEqual(cm.exception.code, "stale_window_id")


class RealSubprocess(unittest.TestCase):
    """The subprocess layer, through a fake omniwmctl executable."""

    def fake_ctl(self, body):
        d = tempfile.mkdtemp(prefix="scratchpads-ctl-")
        path = os.path.join(d, "omniwmctl")
        with open(path, "w") as f:
            f.write("#!/bin/sh\n" + body)
        os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)
        return path

    def test_mismatch_from_a_real_process(self):
        path = self.fake_ctl("echo 'error: protocol_mismatch (server protocol 16, app 0.7.3)'\nexit 1\n")
        with mock.patch.object(sp, "OMNIWMCTL", path):
            with self.assertRaises(sp.Unavailable) as cm:
                sp.windows()
        self.assertIsNotNone(cm.exception.mismatch)

    def test_windows_from_a_real_process(self):
        doc = {"ok": True, "result": {"payload": {"windows": [
            {"id": oid("T", 5, 6), "pid": 5, "windowId": 6, "app": {"name": "X", "bundleId": "x"},
             "title": "t", "scratchpadIndex": 2, "isVisible": False}]}}}
        path = self.fake_ctl(f"cat <<'EOF'\n{json.dumps(doc)}\nEOF\n")
        with mock.patch.object(sp, "OMNIWMCTL", path):
            (w,) = sp.windows()
        self.assertEqual((w["pid"], w["windowId"], w["slot"], w["bundleId"]), (5, 6, 2, "x"))

    def test_missing_binary_is_unavailable(self):
        with mock.patch.object(sp, "OMNIWMCTL", "/nonexistent/omniwmctl"):
            with self.assertRaises(sp.Unavailable):
                sp.windows()


def W(pid, wid, bundle, title, slot=None, app=None):
    return {"id": oid("T", pid, wid), "pid": pid, "windowId": wid, "bundleId": bundle,
            "app": app or bundle, "title": title, "slot": slot, "workspace": 3, "visible": slot is None}


def E(pid, wid, bundle, title, app=None):
    return {"pid": pid, "windowId": wid, "bundleId": bundle, "app": app or bundle, "title": title}


class Matching(unittest.TestCase):
    old = staticmethod(lambda pid: 1000.0)

    def m(self, e, wins, alive=lambda pid: True, age=None):
        return sp.match(e, wins, alive, age or self.old)

    def test_same_window(self):
        out, w, _ = self.m(E(1, 10, CHROME, "a"), [W(1, 10, CHROME, "renamed")])
        self.assertEqual((out, w["windowId"]), ("found", 10))

    def test_pid_reused_by_another_app_is_not_a_match(self):
        out, _, _ = self.m(E(1, 10, CHROME, "a"), [W(1, 10, "com.other", "a")], alive=lambda pid: False)
        self.assertEqual(out, "missing")

    def test_closed_while_app_runs_has_no_title_fallback(self):
        # Same pid alive, the window gone, another Chrome window with the
        # same title: that is a different window, not this one.
        out, _, why = self.m(E(1, 10, CHROME, "Inbox"), [W(1, 11, CHROME, "Inbox")])
        self.assertEqual(out, "missing")
        self.assertIn("closed", why)

    def test_app_restarted_unique_title(self):
        out, w, _ = self.m(E(1, 10, CHROME, "Inbox"), [W(2, 50, CHROME, "Inbox"), W(2, 51, CHROME, "Other")],
                           alive=lambda pid: False)
        self.assertEqual((out, w["windowId"]), ("found", 50))

    def test_app_restarted_two_same_titles_is_ambiguous(self):
        out, _, _ = self.m(E(1, 10, CHROME, "New Tab"), [W(2, 50, CHROME, "New Tab"), W(2, 51, CHROME, "New Tab")],
                           alive=lambda pid: False)
        self.assertEqual(out, "ambiguous")

    def test_app_just_started_waits(self):
        out, _, _ = self.m(E(1, 10, CHROME, "Inbox"), [W(2, 50, CHROME, "Inbox")],
                           alive=lambda pid: False, age=lambda pid: 3.0)
        self.assertEqual(out, "wait")

    def test_title_fallback_never_crosses_apps(self):
        out, _, _ = self.m(E(1, 10, CHROME, "Inbox"), [W(2, 50, "com.apple.Safari", "Inbox")],
                           alive=lambda pid: False)
        self.assertEqual(out, "missing")

    def test_plan_outcomes(self):
        wins = [W(1, 10, CHROME, "a", slot=4), W(1, 11, CHROME, "b", slot=2), W(1, 12, CHROME, "c")]
        rows = sp.plan([(4, E(1, 10, CHROME, "a")), (4, E(1, 11, CHROME, "b")), (1, E(1, 12, CHROME, "c"))],
                       wins, lambda pid: True, self.old)
        self.assertEqual([r[2] for r in rows], ["in-place", "taken", "assign"])

    def test_two_slots_on_one_window_are_both_skipped(self):
        wins = [W(2, 50, CHROME, "Inbox")]
        rows = sp.plan([(1, E(1, 10, CHROME, "Inbox")), (4, E(1, 11, CHROME, "Inbox"))],
                       wins, lambda pid: False, self.old)
        self.assertEqual([r[2] for r in rows], ["ambiguous", "ambiguous"])


class DebounceTest(unittest.TestCase):
    def test_quiet_cap_and_safety(self):
        d = sp.Debounce(0.0)
        self.assertTrue(d.due(0.0))
        d.done(0.0)
        self.assertEqual(d.deadline(), sp.SAFETY)
        d.event(1.0)
        self.assertEqual(d.deadline(), 1.0 + sp.QUIET)
        for t in range(2, 30):  # a steady trickle never goes quiet
            d.event(1.0 + t * 0.5)
        self.assertEqual(d.deadline(), 1.0 + sp.MAX_WAIT)
        d.done(20.0)
        d.wake_at(25.0)
        self.assertEqual(d.deadline(), 25.0)


class Saving(Base):
    def test_first_run_saves_live_slots(self):
        c = self.ow.add(56249, 42018, CHROME, "Master", slot=4)
        self.ow.add(56249, 42019, CHROME, "Other")
        self.keeper().tick()
        self.assertEqual(self.saved_keys(), {4: [c]})
        self.assertEqual(self.saved()["omniwm"], {"pid": 88009, "started": "Fri Oct  2 18:59:02 2026"})

    def test_no_rewrite_when_nothing_changed(self):
        self.ow.add(1, 10, CHROME, "a", slot=4)
        k = self.keeper()
        k.tick()
        before = self.mtime()
        os.utime(self.path, ns=(1, 1))
        k.tick()
        self.assertEqual(self.mtime(), 1)
        self.assertIsNotNone(before)

    def test_assign_and_title_change_are_saved(self):
        a = self.ow.add(1, 10, CHROME, "a", slot=4)
        k = self.keeper()
        k.tick()
        b = self.ow.add(2014, 69, OBSIDIAN, "Notes")
        self.ow.wins[b]["slot"] = 3
        self.ow.wins[a]["title"] = "a, later"
        k.tick()
        doc = self.saved()
        self.assertEqual(self.saved_keys(doc), {3: [b], 4: [a]})
        self.assertEqual(doc["slots"]["4"][0]["title"], "a, later")

    def test_unassign_within_one_lifetime_saves_the_slot_empty(self):
        a = self.ow.add(1, 10, CHROME, "a", slot=4)
        b = self.ow.add(2, 20, OBSIDIAN, "n", slot=3)
        k = self.keeper()
        k.tick()
        self.ow.wins[a]["slot"] = None  # the user's Caps+Shift+C on it
        k.tick()
        self.assertEqual(self.saved_keys(), {3: [b]})

    def test_moving_a_window_to_another_slot(self):
        a = self.ow.add(1, 10, CHROME, "a", slot=4)
        k = self.keeper()
        k.tick()
        self.ow.wins[a]["slot"] = 1
        k.tick()
        self.assertEqual(self.saved_keys(), {1: [a]})

    def test_closed_window_is_dropped_after_the_grace(self):
        a = self.ow.add(1, 10, CHROME, "a", slot=4)
        b = self.ow.add(2, 20, OBSIDIAN, "n", slot=3)
        k = self.keeper()
        k.tick()
        del self.ow.wins[a]
        k.tick()
        self.assertEqual(self.saved_keys(), {3: [b], 4: [a]})  # held
        self.now += sp.VANISH_GRACE + 1
        k.tick()
        self.assertEqual(self.saved_keys(), {3: [b]})

    def test_many_unassigned_at_once_are_held(self):
        # No hotkey unassigns several windows at once; OmniWM losing its
        # slots does. Held for the grace, then believed.
        a = self.ow.add(1, 10, CHROME, "a", slot=4)
        b = self.ow.add(2, 20, OBSIDIAN, "n", slot=3)
        k = self.keeper()
        k.tick()
        self.ow.wins[a]["slot"] = self.ow.wins[b]["slot"] = None
        k.tick()
        self.assertEqual(self.saved_keys(), {3: [b], 4: [a]})
        self.now += sp.VANISH_GRACE + 1
        k.tick()
        self.assertEqual(self.saved_keys(), {})

    def test_empty_window_list_is_never_saved(self):
        self.ow.add(1, 10, CHROME, "a", slot=4)
        k = self.keeper()
        k.tick()
        self.ow.glitch_empty = True
        for _ in range(3):
            self.now += sp.VANISH_GRACE + 1
            k.tick()
        self.assertEqual(self.saved_keys(), {4: [(1, 10)]})


class Restart(Base):
    def setUp(self):
        super().setUp()
        self.master = self.ow.add(56249, 42018, CHROME, "Master", slot=4)
        self.other = self.ow.add(56249, 42019, CHROME, "Other", ws=2)
        self.mc = self.ow.add(83127, 42676, None, "Minecraft 26.3", slot=2, app="java")
        self.notes = self.ow.add(2014, 69, OBSIDIAN, "Useful Links", ws=6, slot=3)
        self.ow.add(75354, 29693, "com.cmuxterm.app", "PR conflicts", ws=3)
        self.k = self.keeper()
        self.k.tick()
        self.before = self.saved()

    def restart(self):
        before = self.saved()
        self.ow.running = False
        self.assertIsNone(self.k.tick())
        self.assertEqual(self.saved(), before)  # down: untouched
        self.ow.restart()
        self.now = self.ow.epoch + 1  # just started

    def test_restart_restores_every_slot(self):
        self.restart()
        self.ow.focus = (75354, 29693)
        self.k.tick()
        self.assertEqual(self.saved(), self.before, "nothing is written before the restore")
        self.assertTrue(all(self.ow.slot_of(k) is None for k in self.ow.wins))
        self.now = self.ow.epoch + sp.SETTLE + 1
        view = self.ow.view()
        self.k.tick()
        self.assertEqual(self.ow.slot_of(self.master), 4)
        self.assertEqual(self.ow.slot_of(self.mc), 2)
        self.assertEqual(self.ow.slot_of(self.notes), 3)
        self.assertIsNone(self.ow.slot_of(self.other), "the other Chrome window stays out")
        self.assertEqual(self.ow.view(), view, "focus and each display's workspace are put back")
        doc = self.saved()
        self.assertEqual(self.saved_keys(doc), self.saved_keys(self.before))
        self.assertEqual(doc["omniwm"]["pid"], self.ow.pid)
        self.assertEqual(doc["pending"], {})

    def test_restore_is_idempotent(self):
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1
        self.k.tick()
        self.ow.calls.clear()
        self.k.tick()
        self.assertFalse([c for c in self.ow.calls if c[0] in ("window", "command")])
        # and a hand-run restore leaves slots alone rather than toggling them out
        self.assertEqual(sp.restore(sp.saved_entries(self.saved()), self.ow.alive, lambda p: 1000.0,
                                    self.ow.instance(), self.ow.instance),
                         {(s, p, w): ("in-place", "same window") for s, p, w in
                          [(2, 83127, 42676), (3, 2014, 69), (4, 56249, 42018)]})
        self.assertEqual(self.ow.slot_of(self.master), 4)

    def test_unassign_after_restart_is_kept_across_the_next_restart(self):
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1
        self.k.tick()
        self.ow.wins[self.mc]["slot"] = None  # the user empties slot 2
        self.k.tick()
        self.assertNotIn("2", self.saved()["slots"])
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1
        self.k.tick()
        self.assertIsNone(self.ow.slot_of(self.mc))
        self.assertEqual(self.ow.slot_of(self.master), 4)

    def test_mismatch_after_an_upgrade_keeps_the_file(self):
        self.ow.mismatch = True
        for _ in range(3):
            self.now += 60
            self.k.tick()
        self.assertEqual(self.saved(), self.before)
        self.assertEqual(sum("was upgraded; restart it" in line for line in self.logs), 1)
        # the user restarts OmniWM: restored
        self.ow.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1
        self.k.tick()
        self.assertEqual(self.ow.slot_of(self.master), 4)
        self.assertTrue(self.log_has("reachable again"))

    def test_closed_window_is_skipped_and_logged(self):
        del self.ow.wins[self.notes]  # Obsidian still running: closed
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1
        self.k.tick()
        self.assertEqual(self.ow.slot_of(self.master), 4)
        self.assertTrue(self.log_has("closed"))
        doc = self.saved()
        self.assertNotIn("3", doc["slots"])
        self.assertEqual([e["windowId"] for e in doc["pending"]["3"]], [69], "kept while it may come back")
        self.now += sp.PENDING_GRACE + 1
        self.k.tick()
        self.assertEqual(self.saved()["pending"], {})
        self.assertTrue(self.log_has("not found within"))

    def test_a_window_that_shows_up_late_is_restored(self):
        late = self.ow.wins.pop(self.notes)
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1
        self.k.tick()
        self.ow.wins[self.notes] = late  # admitted late
        self.now += 5
        self.k.tick()
        self.assertEqual(self.ow.slot_of(self.notes), 3)
        self.assertEqual(self.saved()["pending"], {})

    def test_app_restart_two_same_titles_skips_that_slot_only(self):
        # A reboot: Chrome comes back as a new process with two "Master" windows.
        del self.ow.wins[self.master], self.ow.wins[self.other]
        self.ow.alive_pids.discard(56249)
        self.ow.add(60000, 1, CHROME, "Master")
        self.ow.add(60000, 2, CHROME, "Master")
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1
        self.k.tick()
        self.assertIsNone(self.ow.slot_of((60000, 1)))
        self.assertIsNone(self.ow.slot_of((60000, 2)))
        self.assertEqual(self.ow.slot_of(self.mc), 2)
        self.assertTrue(self.log_has("2 of its windows are titled 'Master'"))

    def test_app_restart_unique_title_is_restored(self):
        del self.ow.wins[self.master]
        self.ow.alive_pids.discard(56249)
        new = self.ow.add(60000, 1, CHROME, "Master")
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1
        self.k.tick()
        self.assertEqual(self.ow.slot_of(new), 4)

    def test_slot_filled_by_hand_since_the_restart_wins(self):
        self.restart()
        self.ow.wins[self.master]["slot"] = 1  # user put the master on S before the restore
        self.now = self.ow.epoch + sp.SETTLE + 1
        self.k.tick()
        self.assertEqual(self.ow.slot_of(self.master), 1)
        self.assertEqual(self.saved_keys()[1], [self.master])
        self.assertNotIn(4, self.saved_keys())

    def test_daemon_restart_under_the_same_omniwm_does_nothing(self):
        self.ow.calls.clear()
        k = self.keeper()
        k.tick()
        self.assertFalse([c for c in self.ow.calls if c[0] in ("window", "command")])
        self.assertEqual(self.saved_keys(), self.saved_keys(self.before))

    def test_omniwm_restarting_mid_restore(self):
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1

        def die(ow, k):
            ow.on_focus = None
            ow.restart()  # tokens change: the next focus is stale, the instance differs
        self.ow.on_focus = die
        self.k.tick()
        self.assertEqual(self.saved_keys(), self.saved_keys(self.before), "nothing saved mid-restore")
        self.now = self.ow.epoch + sp.SETTLE + 1
        self.k.tick()
        self.assertEqual(self.ow.slot_of(self.master), 4)
        self.assertEqual(self.ow.slot_of(self.mc), 2)
        self.assertEqual(self.ow.slot_of(self.notes), 3)

    def test_hotkey_on_the_target_during_restore_is_not_toggled_out(self):
        # The user presses Caps+Shift+C while the restore has the master
        # focused: OmniWM assigns it; our assign must not then toggle it out.
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1

        def user(ow, k):
            if k == self.master:
                ow.wins[k]["slot"], ow.wins[k]["hidden"] = 4, True
        self.ow.on_focus = user
        self.k.tick()
        self.assertEqual(self.ow.slot_of(self.master), 4)

    def test_focus_moving_away_before_assign_stops_the_restore(self):
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1
        cmux = (75354, 29693)

        def user(ow, n):
            ow.on_assign = None
            ow.focus = cmux  # a click lands between our check and the assign
        self.ow.on_assign = user
        view = self.ow.view()
        self.k.tick()
        self.assertTrue(self.log_has("instead (focus moved)"))
        self.assertEqual(self.ow.view()[0], view[0], "workspaces put back even when stopped")
        self.assertEqual(self.saved()["omniwm"]["pid"], self.before["omniwm"]["pid"], "not saved")

    def test_focus_that_never_lands_is_retried_then_given_up(self):
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1
        self.ow.focus_lag = 10 ** 9
        with mock.patch.object(sp, "FOCUS_TIMEOUT", 0.01):
            for _ in range(sp.MAX_ATTEMPTS):
                self.k.tick()
                self.now += sp.RETRY_AFTER + 1
            self.k.tick()
        self.assertTrue(self.log_has("gave up"))
        self.assertEqual(self.saved()["pending"], {})

    def test_slow_focus_still_lands(self):
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1
        self.ow.focus_lag = 3
        self.k.tick()
        self.assertEqual(self.ow.slot_of(self.master), 4)

    def test_a_display_removed_during_restore(self):
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1

        def unplug(ow, k):
            ow.on_focus = None
            ow.displays = [d for d in ow.displays if d["id"] != "display:1"]
            ow.displays[0]["owns"] |= set(range(6, 11))
        self.ow.on_focus = unplug
        self.k.tick()
        self.assertEqual(self.ow.slot_of(self.notes), 3)
        self.assertEqual(self.ow.slot_of(self.master), 4)

    def test_previously_focused_window_now_hidden_is_not_refocused(self):
        self.restart()
        self.ow.focus = self.master  # focused before the restore, then assigned + hidden
        self.now = self.ow.epoch + sp.SETTLE + 1
        self.k.tick()
        self.assertEqual(self.ow.slot_of(self.master), 4)
        self.assertNotEqual(self.ow.focus, self.master, "refocusing it would reveal slot 4")

    def test_status_and_restore_cli(self):
        printed = []
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1
        with mock.patch.object(sp, "STATE_FILE", self.path), \
                mock.patch.object(sp, "omniwm_instance", self.ow.instance), \
                mock.patch.object(sp, "pid_alive", self.ow.alive), \
                mock.patch.object(sp, "app_age", lambda pid, now: 1000.0), \
                mock.patch("builtins.print", side_effect=lambda *a, **k: printed.append(a)) as out:
            self.assertEqual(sp.status(), 0)
            self.assertIn("assign", " ".join(str(c) for c in out.call_args_list))
            self.assertEqual(sp.restore_now(), 0, printed)
            self.ow.mismatch = True
            self.assertEqual(sp.status(), 1)
            self.assertEqual(sp.restore_now(), 1)
        self.assertEqual(self.ow.slot_of(self.master), 4)
        self.assertEqual(self.saved(), self.before, "the CLI never writes the file")

    def test_restore_waits_for_a_held_lock(self):
        self.restart()
        self.now = self.ow.epoch + sp.SETTLE + 1
        with sp.Lock(self.path) as got:
            self.assertTrue(got)
            self.k.tick()
            self.assertIsNone(self.ow.slot_of(self.master))
        self.now += 3
        self.k.tick()
        self.assertEqual(self.ow.slot_of(self.master), 4)


if __name__ == "__main__":
    unittest.main()
