"""Append-only sprint log: goal versions, plan items, PRs, benchmarks, decisions.

Agents and the user write through this CLI. A local Grafana reads the same
SQLite file. No row is ever updated or deleted; current state is the latest
row per key, computed by the views below.
"""

import argparse
import calendar
import json
import os
import sqlite3
import subprocess
import sys
import time

DASHBOARD_URL = os.environ.get("SPRINT_DASHBOARD_URL", "http://127.0.0.1:3001/d/sprint/sprint")

SCHEMA = """
CREATE TABLE IF NOT EXISTS sprints (
  id INTEGER PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  started_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS goal_versions (
  id INTEGER PRIMARY KEY,
  sprint_id INTEGER NOT NULL REFERENCES sprints(id),
  at INTEGER NOT NULL,
  text TEXT NOT NULL,
  reason TEXT NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('user', 'agent'))
);
CREATE TABLE IF NOT EXISTS item_events (
  id INTEGER PRIMARY KEY,
  sprint_id INTEGER NOT NULL REFERENCES sprints(id),
  item INTEGER NOT NULL,
  at INTEGER NOT NULL,
  title TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('planned', 'doing', 'blocked', 'done', 'dropped')),
  owner TEXT NOT NULL CHECK (owner IN ('agent', 'user')),
  position REAL NOT NULL,
  note TEXT
);
CREATE TABLE IF NOT EXISTS pr_events (
  id INTEGER PRIMARY KEY,
  sprint_id INTEGER NOT NULL REFERENCES sprints(id),
  at INTEGER NOT NULL,
  url TEXT NOT NULL,
  title TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('opened', 'ready', 'merged', 'closed'))
);
CREATE TABLE IF NOT EXISTS bench_results (
  id INTEGER PRIMARY KEY,
  sprint_id INTEGER NOT NULL REFERENCES sprints(id),
  at INTEGER NOT NULL,
  suite TEXT NOT NULL,
  metric TEXT NOT NULL,
  value REAL NOT NULL,
  unit TEXT NOT NULL,
  is_baseline INTEGER NOT NULL CHECK (is_baseline IN (0, 1)),
  commit_sha TEXT,
  link TEXT
);
CREATE TABLE IF NOT EXISTS log (
  id INTEGER PRIMARY KEY,
  sprint_id INTEGER NOT NULL REFERENCES sprints(id),
  at INTEGER NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('decision', 'steer', 'deploy', 'note', 'end')),
  text TEXT NOT NULL,
  link TEXT
);

CREATE VIEW IF NOT EXISTS item_state AS
  SELECT e.* FROM item_events e
  WHERE e.id = (SELECT e2.id FROM item_events e2
                WHERE e2.sprint_id = e.sprint_id AND e2.item = e.item
                ORDER BY e2.at DESC, e2.id DESC LIMIT 1);

CREATE VIEW IF NOT EXISTS pr_state AS
  SELECT p.* FROM pr_events p
  WHERE p.id = (SELECT p2.id FROM pr_events p2
                WHERE p2.sprint_id = p.sprint_id AND p2.url = p.url
                ORDER BY p2.at DESC, p2.id DESC LIMIT 1);

CREATE VIEW IF NOT EXISTS goal_current AS
  SELECT g.sprint_id, g.at, g.text, g.reason, g.source,
         (SELECT COUNT(*) FROM goal_versions g2 WHERE g2.sprint_id = g.sprint_id) AS versions
  FROM goal_versions g
  WHERE g.id = (SELECT g2.id FROM goal_versions g2 WHERE g2.sprint_id = g.sprint_id
                ORDER BY g2.at DESC, g2.id DESC LIMIT 1);

CREATE VIEW IF NOT EXISTS progress AS
  SELECT s.id AS sprint_id,
         COALESCE(SUM(i.status = 'done'), 0) AS done,
         COALESCE(SUM(i.status != 'dropped'), 0) AS in_scope,
         COALESCE(SUM(i.status = 'dropped'), 0) AS dropped,
         CASE WHEN SUM(i.status != 'dropped') > 0
              THEN ROUND(100.0 * SUM(i.status = 'done') / SUM(i.status != 'dropped'))
              ELSE 0 END AS percent
  FROM sprints s LEFT JOIN item_state i ON i.sprint_id = s.id
  GROUP BY s.id;

-- Done and in-scope counts after every item event, for the burn-up chart.
CREATE VIEW IF NOT EXISTS burnup AS
  WITH times AS (SELECT DISTINCT sprint_id, at FROM item_events),
  snap AS (
    SELECT t.sprint_id, t.at AS time, e.status
    FROM times t JOIN item_events e ON e.sprint_id = t.sprint_id
    WHERE e.id = (SELECT e2.id FROM item_events e2
                  WHERE e2.sprint_id = t.sprint_id AND e2.item = e.item AND e2.at <= t.at
                  ORDER BY e2.at DESC, e2.id DESC LIMIT 1)
  )
  SELECT sprint_id, time,
         SUM(status != 'dropped') AS in_scope,
         SUM(status = 'done') AS done
  FROM snap GROUP BY sprint_id, time;
"""

TABLES = ("sprints", "goal_versions", "item_events", "pr_events", "bench_results", "log")


class SprintError(Exception):
    pass


def now():
    return int(os.environ.get("SPRINT_NOW") or time.time())


def connect(path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA foreign_keys=ON")
    db.executescript(SCHEMA)
    for table in TABLES:
        for op in ("UPDATE", "DELETE"):
            db.execute(
                f"CREATE TRIGGER IF NOT EXISTS {table}_no_{op.lower()} BEFORE {op} ON {table} "
                "BEGIN SELECT RAISE(ABORT, 'sprint log is append-only'); END"
            )
    db.commit()
    return db


def open_sprints(db):
    return db.execute(
        "SELECT s.* FROM sprints s WHERE NOT EXISTS "
        "(SELECT 1 FROM log l WHERE l.sprint_id = s.id AND l.kind = 'end') "
        "ORDER BY s.started_at DESC, s.id DESC"
    ).fetchall()


def resolve(db, slug):
    slug = slug or os.environ.get("SPRINT")
    if slug:
        row = db.execute("SELECT * FROM sprints WHERE slug = ?", (slug,)).fetchone()
        if row is None:
            raise SprintError(f"no sprint named {slug!r}")
        return row
    rows = open_sprints(db)
    if len(rows) == 1:
        return rows[0]
    if not rows:
        raise SprintError("no open sprint; run `sprint start`")
    names = ", ".join(r["slug"] for r in rows)
    raise SprintError(f"several open sprints ({names}); pass --sprint or set SPRINT")


def latest_item(db, sprint_id, item):
    row = db.execute(
        "SELECT * FROM item_state WHERE sprint_id = ? AND item = ?", (sprint_id, item)
    ).fetchone()
    if row is None:
        raise SprintError(f"no item {item} in this sprint")
    return row


def cmd_start(db, a):
    if db.execute("SELECT 1 FROM sprints WHERE slug = ?", (a.slug,)).fetchone():
        raise SprintError(f"sprint {a.slug!r} already exists")
    at = now()
    cur = db.execute(
        "INSERT INTO sprints (slug, title, started_at) VALUES (?, ?, ?)", (a.slug, a.title, at)
    )
    db.execute(
        "INSERT INTO goal_versions (sprint_id, at, text, reason, source) VALUES (?, ?, ?, ?, ?)",
        (cur.lastrowid, at, a.goal, "sprint start", a.source),
    )
    print(f"started {a.slug}")


def cmd_goal(db, a):
    s = resolve(db, a.sprint)
    at = now()
    db.execute(
        "INSERT INTO goal_versions (sprint_id, at, text, reason, source) VALUES (?, ?, ?, ?, ?)",
        (s["id"], at, a.text, a.reason, a.source),
    )
    db.execute(
        "INSERT INTO log (sprint_id, at, kind, text) VALUES (?, ?, 'steer', ?)",
        (s["id"], at, f"goal changed: {a.reason}"),
    )
    n = db.execute("SELECT versions FROM goal_current WHERE sprint_id = ?", (s["id"],)).fetchone()[0]
    print(f"goal version {n}")


def cmd_item_add(db, a):
    s = resolve(db, a.sprint)
    item = db.execute(
        "SELECT COALESCE(MAX(item), 0) + 1 FROM item_events WHERE sprint_id = ?", (s["id"],)
    ).fetchone()[0]
    if a.after is None:
        position = db.execute(
            "SELECT COALESCE(MAX(position), 0) + 1 FROM item_state WHERE sprint_id = ?", (s["id"],)
        ).fetchone()[0]
    else:
        before = latest_item(db, s["id"], a.after)["position"]
        after = db.execute(
            "SELECT MIN(position) FROM item_state WHERE sprint_id = ? AND position > ?",
            (s["id"], before),
        ).fetchone()[0]
        position = before + 1 if after is None else (before + after) / 2
    db.execute(
        "INSERT INTO item_events (sprint_id, item, at, title, status, owner, position, note) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (s["id"], item, now(), a.title, a.status, a.owner, position, a.note),
    )
    print(item)


def cmd_item_set(db, a):
    s = resolve(db, a.sprint)
    cur = latest_item(db, s["id"], a.item)
    db.execute(
        "INSERT INTO item_events (sprint_id, item, at, title, status, owner, position, note) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (s["id"], a.item, now(), a.title or cur["title"], a.status or cur["status"],
         a.owner or cur["owner"], cur["position"], a.note),
    )
    print(f"item {a.item}: {a.status or cur['status']}")


def gh_pr(url):
    out = subprocess.run(
        ["gh", "pr", "view", url, "--json", "title,url,state,createdAt,mergedAt,closedAt"],
        check=True, capture_output=True, text=True,
    ).stdout
    return json.loads(out)


def epoch(stamp):
    if not stamp:
        return None
    return calendar.timegm(time.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ"))


def pr_states(db, sprint_id):
    return {r["url"]: r for r in db.execute("SELECT * FROM pr_state WHERE sprint_id = ?", (sprint_id,))}


def record_pr(db, sprint_id, info):
    """Write the events that GitHub shows and the log doesn't have yet."""
    url, title = info["url"], info["title"]
    have = {r["state"] for r in db.execute(
        "SELECT state FROM pr_events WHERE sprint_id = ? AND url = ?", (sprint_id, url))}
    wrote = []
    if "opened" not in have:
        wrote.append(("opened", epoch(info["createdAt"]) or now()))
    if info["state"] == "MERGED" and "merged" not in have:
        wrote.append(("merged", epoch(info["mergedAt"]) or now()))
    elif info["state"] == "CLOSED" and "closed" not in have:
        wrote.append(("closed", epoch(info["closedAt"]) or now()))
    for state, at in wrote:
        db.execute(
            "INSERT INTO pr_events (sprint_id, at, url, title, state) VALUES (?, ?, ?, ?, ?)",
            (sprint_id, at, url, title, state),
        )
    return [s for s, _ in wrote]


def cmd_pr_add(db, a):
    s = resolve(db, a.sprint)
    for url in a.urls:
        wrote = record_pr(db, s["id"], gh_pr(url))
        print(f"{url}: {', '.join(wrote) or 'already tracked'}")


def cmd_pr_ready(db, a):
    s = resolve(db, a.sprint)
    cur = pr_states(db, s["id"]).get(a.url)
    if cur is None:
        raise SprintError(f"{a.url} is not in this sprint; run `sprint pr add` first")
    db.execute(
        "INSERT INTO pr_events (sprint_id, at, url, title, state) VALUES (?, ?, ?, ?, 'ready')",
        (s["id"], now(), a.url, cur["title"]),
    )
    print(f"{a.url}: ready")


def cmd_pr_sync(db, a):
    s = resolve(db, a.sprint)
    for url, cur in pr_states(db, s["id"]).items():
        if cur["state"] in ("merged", "closed"):
            continue
        wrote = record_pr(db, s["id"], gh_pr(url))
        if wrote:
            print(f"{url}: {', '.join(wrote)}")


def cmd_bench(db, a):
    s = resolve(db, a.sprint)
    db.execute(
        "INSERT INTO bench_results (sprint_id, at, suite, metric, value, unit, is_baseline, commit_sha, link) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (s["id"], now(), a.suite, a.metric, a.value, a.unit, int(a.baseline), a.commit, a.link),
    )
    print(f"{a.suite} {a.metric} = {a.value} {a.unit}")


def cmd_log(db, a):
    s = resolve(db, a.sprint)
    db.execute(
        "INSERT INTO log (sprint_id, at, kind, text, link) VALUES (?, ?, ?, ?, ?)",
        (s["id"], now(), a.kind, a.text, a.link),
    )


def cmd_end(db, a):
    s = resolve(db, a.sprint)
    db.execute(
        "INSERT INTO log (sprint_id, at, kind, text) VALUES (?, ?, 'end', ?)",
        (s["id"], now(), a.note or "sprint ended"),
    )
    print(f"ended {s['slug']}")


def summary(db, s):
    goal = db.execute("SELECT * FROM goal_current WHERE sprint_id = ?", (s["id"],)).fetchone()
    prog = db.execute("SELECT * FROM progress WHERE sprint_id = ?", (s["id"],)).fetchone()
    items = db.execute(
        "SELECT item, title, status, owner FROM item_state WHERE sprint_id = ? ORDER BY position",
        (s["id"],),
    ).fetchall()
    prs = db.execute(
        "SELECT url, title, state FROM pr_state WHERE sprint_id = ? ORDER BY at", (s["id"],)
    ).fetchall()
    return {
        "sprint": s["slug"],
        "title": s["title"],
        "goal": goal["text"],
        "goal_version": goal["versions"],
        "done": prog["done"],
        "in_scope": prog["in_scope"],
        "dropped": prog["dropped"],
        "percent": int(prog["percent"]),
        "do_now": [dict(r) for r in items if r["owner"] == "user" and r["status"] not in ("done", "dropped")],
        "items": [dict(r) for r in items],
        "prs": [dict(r) for r in prs],
        "dashboard": f"{DASHBOARD_URL}?var-sprint={s['slug']}",
    }


def cmd_show(db, a):
    data = summary(db, resolve(db, a.sprint))
    if a.json:
        print(json.dumps(data, indent=2))
        return
    print(f"{data['title']} ({data['sprint']})")
    print(f"Goal v{data['goal_version']}: {data['goal']}")
    print(f"Progress: {data['percent']}% ({data['done']} of {data['in_scope']} done, {data['dropped']} dropped)")
    if data["do_now"]:
        print("Do now:")
        for n, r in enumerate(data["do_now"], 1):
            print(f"  {n}. {r['title']} [{r['status']}]")
    for r in data["items"]:
        print(f"  #{r['item']} {r['status']:8} {r['owner']:5} {r['title']}")
    for r in data["prs"]:
        print(f"  PR {r['state']:7} {r['url']}")
    print(data["dashboard"])


def cmd_list(db, a):
    open_ids = {r["id"] for r in open_sprints(db)}
    for s in db.execute("SELECT * FROM sprints ORDER BY started_at DESC"):
        print(f"{s['slug']}\t{'open' if s['id'] in open_ids else 'ended'}\t{s['title']}")


def cmd_init(db, a):
    pass


def parser():
    p = argparse.ArgumentParser(prog="sprint", description=__doc__.splitlines()[0])
    p.add_argument("--db", default=os.environ.get("SPRINT_DB") or os.path.expanduser(
        os.path.join(os.environ.get("XDG_STATE_HOME", "~/.local/state"), "sprint", "sprint.db")))
    p.add_argument("--sprint", help="sprint slug (default: $SPRINT, or the only open sprint)")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("init", help="create the database and schema").set_defaults(fn=cmd_init)
    sub.add_parser("list", help="list sprints").set_defaults(fn=cmd_list)

    s = sub.add_parser("start", help="start a sprint")
    s.add_argument("slug")
    s.add_argument("title")
    s.add_argument("--goal", required=True, help="the goal in the user's words")
    s.add_argument("--source", choices=["user", "agent"], default="user")
    s.set_defaults(fn=cmd_start)

    s = sub.add_parser("goal", help="add a goal version; the old one stays")
    s.add_argument("text")
    s.add_argument("--reason", required=True, help="why it changed, in the user's words")
    s.add_argument("--source", choices=["user", "agent"], default="user")
    s.set_defaults(fn=cmd_goal)

    item = sub.add_parser("item", help="plan items").add_subparsers(dest="item_cmd", required=True)
    s = item.add_parser("add")
    s.add_argument("title")
    s.add_argument("--owner", choices=["agent", "user"], default="agent")
    s.add_argument("--status", choices=["planned", "doing", "blocked", "done"], default="planned")
    s.add_argument("--after", type=int, help="place after this item number")
    s.add_argument("--note")
    s.set_defaults(fn=cmd_item_add)
    s = item.add_parser("set")
    s.add_argument("item", type=int)
    s.add_argument("status", nargs="?", choices=["planned", "doing", "blocked", "done", "dropped"])
    s.add_argument("--owner", choices=["agent", "user"])
    s.add_argument("--title")
    s.add_argument("--note")
    s.set_defaults(fn=cmd_item_set)

    pr = sub.add_parser("pr", help="pull requests").add_subparsers(dest="pr_cmd", required=True)
    s = pr.add_parser("add", help="track PRs; records their GitHub history")
    s.add_argument("urls", nargs="+")
    s.set_defaults(fn=cmd_pr_add)
    s = pr.add_parser("ready", help="mark a PR ready to merge (review gate passed)")
    s.add_argument("url")
    s.set_defaults(fn=cmd_pr_ready)
    pr.add_parser("sync", help="record merges and closes from GitHub").set_defaults(fn=cmd_pr_sync)

    s = sub.add_parser("bench", help="record a benchmark result")
    s.add_argument("suite")
    s.add_argument("metric")
    s.add_argument("value", type=float)
    s.add_argument("unit")
    s.add_argument("--baseline", action="store_true")
    s.add_argument("--commit")
    s.add_argument("--link")
    s.set_defaults(fn=cmd_bench)

    s = sub.add_parser("log", help="record a decision, steer, deploy, or note")
    s.add_argument("kind", choices=["decision", "steer", "deploy", "note"])
    s.add_argument("text")
    s.add_argument("--link")
    s.set_defaults(fn=cmd_log)

    s = sub.add_parser("end", help="end the sprint")
    s.add_argument("--note")
    s.set_defaults(fn=cmd_end)

    s = sub.add_parser("show", help="goal, progress, do-now list, PRs, dashboard link")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_show)
    return p


def main(argv=None):
    a = parser().parse_args(argv)
    db = connect(a.db)
    try:
        with db:
            a.fn(db, a)
    except (SprintError, subprocess.CalledProcessError) as e:
        msg = e.stderr.strip() if isinstance(e, subprocess.CalledProcessError) else str(e)
        print(f"sprint: {msg}", file=sys.stderr)
        return 1
    finally:
        db.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
