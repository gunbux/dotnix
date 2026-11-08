package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	_ "modernc.org/sqlite"
)

// SchemaVersion is stored in PRAGMA user_version. A bump recreates the views.
const SchemaVersion = 10

const tablesSQL = `
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
  note TEXT,
  subgoal TEXT,
  -- A person or outside event the step waits on, in words.
  waits_on TEXT,
  -- The item that must be done or dropped before this step.
  needs INTEGER
);
CREATE TABLE IF NOT EXISTS pr_events (
  id INTEGER PRIMARY KEY,
  sprint_id INTEGER NOT NULL REFERENCES sprints(id),
  at INTEGER NOT NULL,
  url TEXT NOT NULL,
  title TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('opened', 'ready', 'merged', 'closed')),
  subgoal TEXT
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
  link TEXT,
  subgoal TEXT
);
-- A removal hides a benchmark's results up to bench_results.id = last_id from
-- the views. The rows stay.
CREATE TABLE IF NOT EXISTS bench_removals (
  id INTEGER PRIMARY KEY,
  sprint_id INTEGER NOT NULL REFERENCES sprints(id),
  at INTEGER NOT NULL,
  last_id INTEGER NOT NULL,
  suite TEXT NOT NULL,
  metric TEXT NOT NULL,
  subgoal TEXT,
  reason TEXT
);
CREATE TABLE IF NOT EXISTS log (
  id INTEGER PRIMARY KEY,
  sprint_id INTEGER NOT NULL REFERENCES sprints(id),
  at INTEGER NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('decision', 'steer', 'deploy', 'note', 'end')),
  text TEXT NOT NULL,
  link TEXT,
  subgoal TEXT
);
-- A subgoal is one stage of the sprint goal, with its own goal and exit
-- check. key is its slug, and every change adds a row.
CREATE TABLE IF NOT EXISTS subgoal_events (
  id INTEGER PRIMARY KEY,
  sprint_id INTEGER NOT NULL REFERENCES sprints(id),
  key TEXT NOT NULL,
  at INTEGER NOT NULL,
  title TEXT NOT NULL,
  goal TEXT NOT NULL,
  done_when TEXT,
  status TEXT NOT NULL CHECK (status IN ('planned', 'active', 'done', 'dropped')),
  position REAL NOT NULL,
  reason TEXT NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('user', 'agent'))
);
-- Context sections: Markdown that explains the work (architecture, how to
-- run it, caveats, findings). An empty body removes the section.
CREATE TABLE IF NOT EXISTS context_versions (
  id INTEGER PRIMARY KEY,
  sprint_id INTEGER NOT NULL REFERENCES sprints(id),
  subgoal TEXT,
  key TEXT NOT NULL,
  at INTEGER NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  position REAL NOT NULL
);
-- A PR's row on the PR board, logged by "sprint pr sync" when it changes:
-- what GitHub says (head, checks, threads, review bot scores as JSON) and
-- where the board puts it (grp, steps as JSON, rank in review order).
CREATE TABLE IF NOT EXISTS pr_reviews (
  id INTEGER PRIMARY KEY,
  sprint_id INTEGER NOT NULL REFERENCES sprints(id),
  at INTEGER NOT NULL,
  url TEXT NOT NULL,
  number INTEGER NOT NULL,
  head TEXT NOT NULL,
  base TEXT NOT NULL,
  draft INTEGER NOT NULL,
  failing TEXT NOT NULL,
  running INTEGER NOT NULL,
  threads INTEGER NOT NULL,
  bots TEXT NOT NULL,
  grp TEXT NOT NULL CHECK (grp IN ('merge', 'fix', 'wait')),
  steps TEXT NOT NULL,
  rank INTEGER NOT NULL,
  why TEXT NOT NULL,
  stack TEXT NOT NULL
);
-- The user's own next step for a PR. An empty text removes it.
CREATE TABLE IF NOT EXISTS pr_notes (
  id INTEGER PRIMARY KEY,
  sprint_id INTEGER NOT NULL REFERENCES sprints(id),
  at INTEGER NOT NULL,
  url TEXT NOT NULL,
  text TEXT NOT NULL
);
-- One row per finished PR board sync, so the dashboard can tell fresh data
-- from a sync that stopped.
CREATE TABLE IF NOT EXISTS pr_syncs (
  id INTEGER PRIMARY KEY,
  sprint_id INTEGER NOT NULL REFERENCES sprints(id),
  at INTEGER NOT NULL
);
-- Patterns (Go regular expressions, any case) that "sprint pr sync" skips
-- when it finds the user's open PRs: matched on head branch, title, and URL.
-- The latest row per pattern wins; active = 0 removes it.
CREATE TABLE IF NOT EXISTS pr_ignores (
  id INTEGER PRIMARY KEY,
  sprint_id INTEGER NOT NULL REFERENCES sprints(id),
  at INTEGER NOT NULL,
  pattern TEXT NOT NULL,
  active INTEGER NOT NULL CHECK (active IN (0, 1))
);
CREATE INDEX IF NOT EXISTS pr_reviews_latest ON pr_reviews (sprint_id, url, id);
CREATE INDEX IF NOT EXISTS pr_notes_latest ON pr_notes (sprint_id, url, id);
CREATE INDEX IF NOT EXISTS item_events_latest ON item_events (sprint_id, item, at, id);
CREATE INDEX IF NOT EXISTS pr_events_latest ON pr_events (sprint_id, url, id);
CREATE INDEX IF NOT EXISTS goal_versions_latest ON goal_versions (sprint_id, at, id);
CREATE INDEX IF NOT EXISTS subgoal_events_latest ON subgoal_events (sprint_id, key, at, id);
CREATE INDEX IF NOT EXISTS context_versions_latest ON context_versions (sprint_id, subgoal, key, id);
`

// Columns added after the first release: table, column, type. ADD COLUMN is
// not an UPDATE, so the append-only triggers allow it, and old rows read as
// NULL (no subgoal, waits on nothing, needs nothing).
var addedColumns = [][3]string{
	{"item_events", "subgoal", "TEXT"}, {"pr_events", "subgoal", "TEXT"}, {"bench_results", "subgoal", "TEXT"},
	{"log", "subgoal", "TEXT"}, {"item_events", "waits_on", "TEXT"}, {"item_events", "needs", "INTEGER"},
}

var tables = []string{"sprints", "goal_versions", "item_events", "pr_events", "bench_results", "log",
	"subgoal_events", "context_versions", "bench_removals", "pr_reviews", "pr_notes",
	"pr_syncs", "pr_ignores"}

// Views hold no data, so a schema bump drops and recreates them.
var views = []string{"item_state", "pr_state", "goal_current", "progress", "burnup",
	"subgoal_state", "subgoal_progress", "do_now", "timeline", "context_state", "scoped_burnup", "bench_live", "bench_summary", "activity",
	"pr_review_state", "pr_note_state", "pr_ignore_state"}

var viewsSQL = []string{`
CREATE VIEW item_state AS
  SELECT e.* FROM item_events e
  WHERE e.id = (SELECT e2.id FROM item_events e2
                WHERE e2.sprint_id = e.sprint_id AND e2.item = e.item
                ORDER BY e2.at DESC, e2.id DESC LIMIT 1)`, `
-- The latest recorded state wins, not the latest timestamp: a merge synced
-- after a ready keeps the earlier GitHub merge time but must still win.
CREATE VIEW pr_state AS
  SELECT p.* FROM pr_events p
  WHERE p.id = (SELECT MAX(p2.id) FROM pr_events p2
                WHERE p2.sprint_id = p.sprint_id AND p2.url = p.url)`, `
CREATE VIEW pr_review_state AS
  SELECT r.* FROM pr_reviews r
  WHERE r.id = (SELECT MAX(r2.id) FROM pr_reviews r2
                WHERE r2.sprint_id = r.sprint_id AND r2.url = r.url)`, `
CREATE VIEW pr_note_state AS
  SELECT n.* FROM pr_notes n
  WHERE n.id = (SELECT MAX(n2.id) FROM pr_notes n2
                WHERE n2.sprint_id = n.sprint_id AND n2.url = n.url)
    AND n.text != ''`, `
CREATE VIEW pr_ignore_state AS
  SELECT i.* FROM pr_ignores i
  WHERE i.id = (SELECT MAX(i2.id) FROM pr_ignores i2
                WHERE i2.sprint_id = i.sprint_id AND i2.pattern = i.pattern)
    AND i.active = 1`, `
CREATE VIEW goal_current AS
  SELECT g.sprint_id, g.at, g.text, g.reason, g.source,
         (SELECT COUNT(*) FROM goal_versions g2 WHERE g2.sprint_id = g.sprint_id) AS versions
  FROM goal_versions g
  WHERE g.id = (SELECT g2.id FROM goal_versions g2 WHERE g2.sprint_id = g.sprint_id
                ORDER BY g2.at DESC, g2.id DESC LIMIT 1)`, `
CREATE VIEW progress AS
  SELECT s.id AS sprint_id,
         COALESCE(SUM(i.status = 'done'), 0) AS done,
         COALESCE(SUM(i.status != 'dropped'), 0) AS in_scope,
         COALESCE(SUM(i.status = 'dropped'), 0) AS dropped,
         CASE WHEN SUM(i.status != 'dropped') > 0
              THEN ROUND(100.0 * SUM(i.status = 'done') / SUM(i.status != 'dropped'))
              ELSE 0 END AS percent
  FROM sprints s LEFT JOIN item_state i ON i.sprint_id = s.id
  GROUP BY s.id`, `
-- Done and in-scope counts after every item event. Each event adds the
-- change it makes to the counts, and running sums give the totals.
CREATE VIEW burnup AS
  WITH ev AS (
    SELECT sprint_id, at,
           (status != 'dropped')
             - COALESCE(LAG(status != 'dropped') OVER w, 0) AS d_scope,
           (status = 'done') - COALESCE(LAG(status = 'done') OVER w, 0) AS d_done
    FROM item_events
    WINDOW w AS (PARTITION BY sprint_id, item ORDER BY at, id)
  ),
  per_time AS (
    SELECT sprint_id, at, SUM(d_scope) AS d_scope, SUM(d_done) AS d_done
    FROM ev GROUP BY sprint_id, at
  )
  SELECT sprint_id, at AS time,
         SUM(d_scope) OVER (PARTITION BY sprint_id ORDER BY at) AS in_scope,
         SUM(d_done) OVER (PARTITION BY sprint_id ORDER BY at) AS done
  FROM per_time`, `
CREATE VIEW subgoal_state AS
  SELECT e.* FROM subgoal_events e
  WHERE e.id = (SELECT e2.id FROM subgoal_events e2
                WHERE e2.sprint_id = e.sprint_id AND e2.key = e.key
                ORDER BY e2.at DESC, e2.id DESC LIMIT 1)`, `
CREATE VIEW subgoal_progress AS
  SELECT g.sprint_id, g.key,
         COALESCE(SUM(i.status = 'done'), 0) AS done,
         COALESCE(SUM(i.status != 'dropped'), 0) AS in_scope,
         CASE WHEN SUM(i.status != 'dropped') > 0
              THEN ROUND(100.0 * SUM(i.status = 'done') / SUM(i.status != 'dropped'))
              ELSE 0 END AS percent
  FROM subgoal_state g
  LEFT JOIN item_state i ON i.sprint_id = g.sprint_id AND i.subgoal = g.key
  GROUP BY g.sprint_id, g.key`, `
-- The user's open steps, in one order for the whole sprint. state says
-- whether the user can act now:
--   waiting  waits_on is set, or the legacy status blocked (why in its note)
--   later    needs an item that is not done or dropped yet
--   ready    otherwise
-- Ready steps come first, then waiting, then later, so a fold hides the
-- steps the user can't act on first (6 Nov: a ready step sank to step 10
-- behind blocked ones). Within each part: steps without a subgoal first,
-- then each subgoal's steps in the order the stages list shows them
-- (active, then planned, then done, then by position), then by item
-- position. A subgoal's view filters this list and keeps rank, so a step has
-- the same number in every view. since is when a waiting step started to
-- wait on what it waits on now.
CREATE VIEW do_now AS
  WITH open AS (
    SELECT i.*,
           CASE WHEN i.waits_on IS NOT NULL OR i.status = 'blocked' THEN 'waiting'
                WHEN n.status NOT IN ('done', 'dropped') THEN 'later'
                ELSE 'ready' END AS state
    FROM item_state i
    LEFT JOIN item_state n ON n.sprint_id = i.sprint_id AND n.item = i.needs
    WHERE i.owner = 'user' AND i.status NOT IN ('done', 'dropped')
  )
  SELECT o.sprint_id, o.item, o.title, o.status, o.owner, o.note, o.subgoal, o.waits_on, o.needs, o.state,
         COALESCE(g.title, '') AS stage,
         ROW_NUMBER() OVER (PARTITION BY o.sprint_id ORDER BY
           CASE o.state WHEN 'ready' THEN 0 WHEN 'waiting' THEN 1 ELSE 2 END,
           g.key IS NOT NULL,
           CASE g.status WHEN 'active' THEN 0 WHEN 'done' THEN 2 ELSE 1 END,
           g.position, o.position, o.item) AS rank,
         COUNT(*) OVER (PARTITION BY o.sprint_id) AS total,
         CASE WHEN o.state = 'waiting' THEN
           (SELECT MIN(e.at) FROM item_events e
            WHERE e.sprint_id = o.sprint_id AND e.item = o.item
              AND e.id > COALESCE((SELECT MAX(e2.id) FROM item_events e2
                                   WHERE e2.sprint_id = o.sprint_id AND e2.item = o.item
                                     AND NOT (e2.waits_on IS o.waits_on
                                              AND (e2.status = 'blocked') = (o.status = 'blocked'))), 0))
         END AS since
  FROM open o
  LEFT JOIN subgoal_state g ON g.sprint_id = o.sprint_id AND g.key = o.subgoal`, `
-- The user's steps the Timeline panel draws as chains of needs links: every
-- open step from do_now, and each done step that a needs link touches. at is
-- when a done step was done, and when a waiting step started to wait.
CREATE VIEW timeline AS
  SELECT sprint_id, item, title, subgoal, stage, waits_on, needs, note, state, rank, since AS at
  FROM do_now
  UNION ALL
  SELECT i.sprint_id, i.item, i.title, i.subgoal, COALESCE(g.title, ''), i.waits_on, i.needs, i.note,
         'done', NULL, i.at
  FROM item_state i
  LEFT JOIN subgoal_state g ON g.sprint_id = i.sprint_id AND g.key = i.subgoal
  WHERE i.owner = 'user' AND i.status = 'done'
    AND (i.needs IS NOT NULL
         OR EXISTS (SELECT 1 FROM item_state x WHERE x.sprint_id = i.sprint_id AND x.needs = i.item))`, `
CREATE VIEW context_state AS
  SELECT c.* FROM context_versions c
  WHERE c.id = (SELECT MAX(c2.id) FROM context_versions c2
                WHERE c2.sprint_id = c.sprint_id AND c2.key = c.key
                  AND c2.subgoal IS c.subgoal)
    AND c.body != ''`, `
-- Burn-up per scope: '-' is the whole sprint, any other scope is one
-- subgoal. An item counts in a subgoal only while it belongs there, so a
-- move takes it off the old subgoal's line and onto the new one.
CREATE VIEW scoped_burnup AS
  WITH scopes AS (
    SELECT id AS sprint_id, '-' AS scope FROM sprints
    UNION SELECT DISTINCT sprint_id, key FROM subgoal_events
  ),
  ev AS (
    SELECT s.sprint_id, s.scope, e.item, e.at, e.id,
           (s.scope = '-' OR e.subgoal IS s.scope) AND e.status != 'dropped' AS in_scope,
           (s.scope = '-' OR e.subgoal IS s.scope) AND e.status = 'done' AS done
    FROM scopes s JOIN item_events e ON e.sprint_id = s.sprint_id
  ),
  delta AS (
    SELECT sprint_id, scope, at,
           in_scope - COALESCE(LAG(in_scope) OVER w, 0) AS d_scope,
           done - COALESCE(LAG(done) OVER w, 0) AS d_done
    FROM ev
    WINDOW w AS (PARTITION BY sprint_id, scope, item ORDER BY at, id)
  ),
  per_time AS (
    SELECT sprint_id, scope, at, SUM(d_scope) AS d_scope, SUM(d_done) AS d_done
    FROM delta GROUP BY sprint_id, scope, at
  )
  SELECT sprint_id, scope, at AS time,
         SUM(d_scope) OVER (PARTITION BY sprint_id, scope ORDER BY at) AS in_scope,
         SUM(d_done) OVER (PARTITION BY sprint_id, scope ORDER BY at) AS done
  FROM per_time`, `
-- Benchmark results that no later removal hides.
CREATE VIEW bench_live AS
  SELECT b.* FROM bench_results b
  WHERE NOT EXISTS (SELECT 1 FROM bench_removals r
                    WHERE r.sprint_id = b.sprint_id AND r.suite = b.suite AND r.metric = b.metric
                      AND r.subgoal IS b.subgoal AND r.last_id >= b.id)`, `
-- The latest run and the latest baseline of each benchmark, per subgoal: a
-- baseline in one stage is never compared with a run in another.
CREATE VIEW bench_summary AS
  WITH ranked AS (
    SELECT b.*, ROW_NUMBER() OVER (
             PARTITION BY sprint_id, subgoal, suite, metric, unit, is_baseline
             ORDER BY at DESC, id DESC) AS rn
    FROM bench_live b
  ),
  grouped AS (
    SELECT sprint_id, subgoal, suite, metric, unit,
           MAX(CASE WHEN is_baseline = 0 AND rn = 1 THEN value END) AS latest,
           MAX(CASE WHEN is_baseline = 1 AND rn = 1 THEN value END) AS baseline,
           SUM(is_baseline = 0) AS runs, MAX(at) AS last_at
    FROM ranked GROUP BY sprint_id, subgoal, suite, metric, unit
  )
  SELECT g.*, CASE WHEN baseline != 0
                   THEN ROUND(100.0 * (latest - baseline) / baseline, 1) END AS change
  FROM grouped g`, `
-- Every change in the log as one line of plain text, for the activity list.
CREATE VIEW activity AS
  SELECT sprint_id, NULL AS subgoal, at, id, 'goal' AS kind,
         'Goal v' || ROW_NUMBER() OVER (PARTITION BY sprint_id ORDER BY at, id) || ': ' || text
           || CASE WHEN reason = 'sprint start' THEN '' ELSE ' — ' || reason END AS text,
         NULL AS link
  FROM goal_versions
  UNION ALL
  SELECT sprint_id, key, at, id, 'subgoal',
         CASE WHEN rn = 1 THEN 'Subgoal added: ' || title || ' — ' || goal
              ELSE title || ': ' || COALESCE(NULLIF(RTRIM(
                CASE WHEN status != p_status THEN p_status || ' → ' || status || '; ' ELSE '' END
                || CASE WHEN goal != p_goal THEN 'goal changed: ' || goal || '; ' ELSE '' END
                || CASE WHEN done_when IS NOT p_done_when
                        THEN 'done when changed: ' || COALESCE(p_done_when, 'none') || ' → '
                             || COALESCE(done_when, 'none') || '; ' ELSE '' END
                || CASE WHEN title != p_title THEN 'renamed from ' || p_title || '; ' ELSE '' END,
                '; '), ''), 'edited')
                || CASE WHEN reason IN ('edited', 'now ' || status) THEN '' ELSE ' — ' || reason END
         END,
         NULL
  FROM (SELECT e.*, ROW_NUMBER() OVER w AS rn, LAG(status) OVER w AS p_status,
               LAG(goal) OVER w AS p_goal, LAG(done_when) OVER w AS p_done_when,
               LAG(title) OVER w AS p_title
        FROM subgoal_events e WINDOW w AS (PARTITION BY sprint_id, key ORDER BY at, id))
  UNION ALL
  SELECT sprint_id, subgoal, at, id, 'item',
         CASE WHEN rn = 1 THEN 'Planned #' || item || ' ' || title
                               || CASE WHEN owner = 'user' THEN ' (your step)' ELSE '' END
              WHEN status != p_status THEN '#' || item || ' ' || title || ': ' || status
              WHEN subgoal IS NOT p_subgoal THEN '#' || item || ' ' || title || ' moved to '
                || COALESCE((SELECT g.title FROM subgoal_state g
                             WHERE g.sprint_id = x.sprint_id AND g.key = x.subgoal), 'the whole sprint')
              ELSE '#' || item || ' ' || title || ' updated'
         END || CASE WHEN COALESCE(note, '') != '' THEN ' — ' || note ELSE '' END,
         NULL
  FROM (SELECT e.*, ROW_NUMBER() OVER w AS rn, LAG(status) OVER w AS p_status,
               LAG(subgoal) OVER w AS p_subgoal
        FROM item_events e WINDOW w AS (PARTITION BY sprint_id, item ORDER BY at, id)) x
  UNION ALL
  SELECT sprint_id, subgoal, at, id, 'pr',
         CASE WHEN state = p_state AND subgoal IS NOT p_subgoal
              THEN 'PR moved to ' || COALESCE((SELECT g.title FROM subgoal_state g
                                               WHERE g.sprint_id = x.sprint_id AND g.key = x.subgoal), 'the whole sprint')
                   || ': ' || title
              ELSE 'PR ' || state || ': ' || title END,
         url
  FROM (SELECT p.*, LAG(state) OVER w AS p_state, LAG(subgoal) OVER w AS p_subgoal
        FROM pr_events p WINDOW w AS (PARTITION BY sprint_id, url ORDER BY id)) x
  UNION ALL
  SELECT sprint_id, subgoal, at, id, 'bench',
         'Benchmark ' || suite || ' ' || metric || ' = ' || printf('%g', value) || ' ' || unit
           || CASE WHEN is_baseline = 1 THEN ' (baseline)' ELSE '' END,
         link
  FROM bench_results
  UNION ALL
  SELECT sprint_id, subgoal, at, id, 'bench',
         'Benchmark removed: ' || suite || ' ' || metric || COALESCE(' (' || reason || ')', ''), NULL
  FROM bench_removals
  UNION ALL
  SELECT sprint_id, subgoal, at, id, 'context',
         'Section ' || CASE WHEN body = '' THEN 'removed'
                            WHEN COALESCE(p_body, '') = '' THEN 'added'
                            ELSE 'updated' END || ': ' || title,
         NULL
  FROM (SELECT c.*, LAG(body) OVER (PARTITION BY sprint_id, subgoal, key ORDER BY id) AS p_body
        FROM context_versions c)
  UNION ALL
  SELECT sprint_id, subgoal, at, id, kind, text, link FROM log`,
}

// userError is a mistake in the command line or the request, shown as is.
type userError struct{ msg string }

func (e userError) Error() string { return e.msg }

func fail(format string, args ...any) { panic(userError{fmt.Sprintf(format, args...)}) }

func check(err error) {
	if err != nil {
		panic(err)
	}
}

type querier interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

// Store runs queries on one pinned connection. Query errors panic, and run
// turns them into messages.
type Store struct{ q querier }

var bg = context.Background()

func (s Store) exec(query string, args ...any) sql.Result {
	r, err := s.q.ExecContext(bg, query, args...)
	check(err)
	return r
}

func (s Store) insert(query string, args ...any) int64 {
	id, err := s.exec(query, args...).LastInsertId()
	check(err)
	return id
}

// one scans a single row into dest and reports whether there was one.
func (s Store) one(query string, args []any, dest ...any) bool {
	err := s.q.QueryRowContext(bg, query, args...).Scan(dest...)
	if errors.Is(err, sql.ErrNoRows) {
		return false
	}
	check(err)
	return true
}

func (s Store) int(query string, args ...any) int64 {
	var n sql.NullInt64
	s.one(query, args, &n)
	return n.Int64
}

func (s Store) float(query string, args ...any) (float64, bool) {
	var n sql.NullFloat64
	s.one(query, args, &n)
	return n.Float64, n.Valid
}

// each calls scan for every row. The rows are closed before it returns.
func (s Store) each(query string, args []any, scan func(*sql.Rows)) {
	rows, err := s.q.QueryContext(bg, query, args...)
	check(err)
	defer rows.Close()
	for rows.Next() {
		scan(rows)
	}
	check(rows.Err())
}

func (s Store) strings(query string, args ...any) []string {
	var out []string
	s.each(query, args, func(r *sql.Rows) {
		var v string
		check(r.Scan(&v))
		out = append(out, v)
	})
	return out
}

// null stores "" as NULL, for optional text columns.
func null(v string) any {
	if v == "" {
		return nil
	}
	return v
}

func dsn(path string, extra string) string {
	return "file:" + path + "?_pragma=busy_timeout(30000)&_pragma=foreign_keys(1)" + extra
}

// openWrite opens the log on one pinned connection and brings the schema up
// to date. close releases the connection and the pool.
func openWrite(path string) (s Store, close func()) {
	abs, err := filepath.Abs(path)
	check(err)
	check(os.MkdirAll(filepath.Dir(abs), 0o755))
	db, err := sql.Open("sqlite", dsn(abs, ""))
	check(err)
	db.SetMaxOpenConns(1)
	conn, err := db.Conn(bg)
	check(err)
	s = Store{conn}
	close = func() { conn.Close(); db.Close() }
	s.exec("PRAGMA journal_mode=WAL")
	s.write(func() {
		s.exec(tablesSQL)
		for _, t := range tables {
			for _, op := range []string{"UPDATE", "DELETE"} {
				s.exec(fmt.Sprintf("CREATE TRIGGER IF NOT EXISTS %s_no_%s BEFORE %s ON %s "+
					"BEGIN SELECT RAISE(ABORT, 'sprint log is append-only'); END", t, strings.ToLower(op), op, t))
			}
		}
		for _, tc := range addedColumns {
			if s.int(fmt.Sprintf("SELECT COUNT(*) FROM pragma_table_info('%s') WHERE name = ?", tc[0]), tc[1]) == 0 {
				s.exec(fmt.Sprintf("ALTER TABLE %s ADD COLUMN %s %s", tc[0], tc[1], tc[2]))
			}
		}
		if s.int("PRAGMA user_version") < SchemaVersion {
			for _, v := range views {
				s.exec("DROP VIEW IF EXISTS " + v)
			}
			for _, v := range viewsSQL {
				s.exec(v)
			}
			s.exec(fmt.Sprintf("PRAGMA user_version = %d", SchemaVersion))
		}
	})
	return s, close
}

// write runs fn in one write transaction. BEGIN IMMEDIATE takes the write
// lock before any read, so parallel agents can't both read the same next
// item number.
func (s Store) write(fn func()) {
	s.exec("BEGIN IMMEDIATE")
	ok := false
	defer func() {
		if !ok {
			s.q.ExecContext(bg, "ROLLBACK")
		}
	}()
	fn()
	s.exec("COMMIT")
	ok = true
}
