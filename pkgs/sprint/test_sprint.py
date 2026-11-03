import contextlib
import io
import json
import os
import sqlite3
import stat
import tempfile
import unittest

import sprint


class SprintTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.db = os.path.join(self.dir.name, "state", "sprint.db")
        self.env = dict(os.environ)
        os.environ.pop("SPRINT", None)
        self.clock(1000)

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self.env)
        self.dir.cleanup()

    def clock(self, t):
        os.environ["SPRINT_NOW"] = str(t)

    def run_cli(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = sprint.main(["--db", self.db, *args])
        return code, out.getvalue(), err.getvalue()

    def ok(self, *args):
        code, out, err = self.run_cli(*args)
        self.assertEqual(code, 0, err)
        return out

    def show(self, *args):
        return json.loads(self.ok(*args, "show", "--json"))

    def query(self, sql, *params):
        db = sqlite3.connect(self.db)
        try:
            return db.execute(sql, params).fetchall()
        finally:
            db.close()

    def test_rows_cannot_be_updated_or_deleted(self):
        self.ok("start", "s1", "Sprint one", "--goal", "ship it")
        db = sqlite3.connect(self.db)
        for sql in ("UPDATE goal_versions SET text = 'x'", "DELETE FROM goal_versions",
                    "UPDATE sprints SET title = 'x'", "DELETE FROM sprints"):
            with self.subTest(sql=sql), self.assertRaisesRegex(sqlite3.IntegrityError, "append-only"):
                db.execute(sql)
        db.close()

    def test_goal_change_keeps_every_version(self):
        self.ok("start", "s1", "Sprint one", "--goal", "watch face")
        self.clock(2000)
        self.ok("goal", "watch face and bus app", "--reason", "add the bus app too")
        data = self.show()
        self.assertEqual(data["goal"], "watch face and bus app")
        self.assertEqual(data["goal_version"], 2)
        self.assertEqual(
            self.query("SELECT text, reason FROM goal_versions ORDER BY at"),
            [("watch face", "sprint start"), ("watch face and bus app", "add the bus app too")],
        )
        self.assertEqual(self.query("SELECT kind FROM log"), [("steer",)])

    def test_progress_counts_done_over_in_scope_and_skips_dropped(self):
        self.ok("start", "s1", "Sprint one", "--goal", "g")
        for title in ("a", "b", "c", "d"):
            self.ok("item", "add", title)
        self.ok("item", "set", "1", "done")
        self.ok("item", "set", "2", "done")
        self.ok("item", "set", "3", "dropped")
        data = self.show()
        self.assertEqual((data["done"], data["in_scope"], data["dropped"], data["percent"]), (2, 3, 1, 67))

    def test_burnup_shows_scope_growth_over_time(self):
        self.ok("start", "s1", "Sprint one", "--goal", "g")
        self.ok("item", "add", "a")
        self.ok("item", "add", "b")
        self.clock(2000)
        self.ok("item", "set", "1", "done")
        self.clock(3000)
        self.ok("item", "add", "c")
        self.ok("item", "set", "2", "dropped")
        self.assertEqual(
            self.query("SELECT time, in_scope, done FROM burnup ORDER BY time"),
            [(1000, 2, 0), (2000, 2, 1), (3000, 2, 1)],
        )

    def test_item_set_keeps_title_owner_and_position(self):
        self.ok("start", "s1", "Sprint one", "--goal", "g")
        self.ok("item", "add", "plug in the watch", "--owner", "user")
        self.ok("item", "add", "build")
        self.ok("item", "add", "merge", "--owner", "user", "--after", "1")
        self.ok("item", "set", "1", "blocked", "--note", "watch at home")
        data = self.show()
        self.assertEqual([i["title"] for i in data["items"]], ["plug in the watch", "merge", "build"])
        self.assertEqual([(i["title"], i["status"]) for i in data["do_now"]],
                         [("plug in the watch", "blocked"), ("merge", "planned")])

    def test_sprint_resolution(self):
        code, _, err = self.run_cli("show")
        self.assertEqual(code, 1)
        self.assertIn("no open sprint", err)
        self.ok("start", "s1", "One", "--goal", "g")
        self.assertEqual(self.show()["sprint"], "s1")
        self.ok("start", "s2", "Two", "--goal", "g")
        code, _, err = self.run_cli("show")
        self.assertIn("several open sprints", err)
        self.assertEqual(self.show("--sprint", "s1")["sprint"], "s1")
        os.environ["SPRINT"] = "s2"
        self.assertEqual(self.show()["sprint"], "s2")
        del os.environ["SPRINT"]
        self.ok("--sprint", "s2", "end")
        self.assertEqual(self.show()["sprint"], "s1")

    def test_duplicate_slug_is_refused(self):
        self.ok("start", "s1", "One", "--goal", "g")
        code, _, err = self.run_cli("start", "s1", "Again", "--goal", "g")
        self.assertEqual(code, 1)
        self.assertIn("already exists", err)

    def fake_gh(self, state, merged_at=None):
        bindir = os.path.join(self.dir.name, "bin")
        os.makedirs(bindir, exist_ok=True)
        info = {"title": "Add T3 Ask", "url": "https://github.com/o/r/pull/3", "state": state,
                "createdAt": "2026-11-02T10:00:00Z", "mergedAt": merged_at, "closedAt": None}
        path = os.path.join(bindir, "gh")
        with open(path, "w") as f:
            f.write(f"#!/bin/sh\ncat <<'EOF'\n{json.dumps(info)}\nEOF\n")
        os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)
        os.environ["PATH"] = bindir + os.pathsep + self.env.get("PATH", "")

    def test_pr_history_comes_from_github_times(self):
        self.ok("start", "s1", "One", "--goal", "g")
        url = "https://github.com/o/r/pull/3"
        self.fake_gh("OPEN")
        self.ok("pr", "add", url)
        self.clock(5000)
        self.ok("pr", "ready", url)
        self.fake_gh("MERGED", merged_at="2026-11-03T01:00:00Z")
        self.ok("pr", "sync")
        self.ok("pr", "sync")
        self.assertEqual(
            self.query("SELECT state, at FROM pr_events ORDER BY id"),
            [("opened", 1793613600), ("ready", 5000), ("merged", 1793667600)],
        )
        self.assertEqual(self.show()["prs"][0]["state"], "merged")

    def test_bench_and_log(self):
        self.ok("start", "s1", "One", "--goal", "g")
        self.ok("bench", "build", "seconds", "48", "s", "--baseline")
        self.ok("bench", "build", "seconds", "31", "s", "--commit", "abc123")
        self.ok("log", "decision", "keep the bridge on legion-nix", "--link", "https://example.com")
        self.assertEqual(self.query("SELECT value, is_baseline FROM bench_results ORDER BY id"),
                         [(48.0, 1), (31.0, 0)])
        self.assertEqual(self.query("SELECT kind, text FROM log"),
                         [("decision", "keep the bridge on legion-nix")])


if __name__ == "__main__":
    unittest.main()
