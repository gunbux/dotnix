package main

import (
	"database/sql"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Live items are things in flight (a benchmark, a CI run, a deploy) that the
// dashboard's Live section shows as cards. They change in place, so they live
// in their own file (live.db beside the log), not in the append-only log.

const liveSQL = `
CREATE TABLE IF NOT EXISTS live_items (
  sprint TEXT NOT NULL,
  key TEXT NOT NULL,
  subgoal TEXT,
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  done_n REAL,
  total_n REAL,
  ends_at INTEGER,
  stale_after INTEGER,
  link TEXT,
  state TEXT NOT NULL DEFAULT 'live' CHECK (state IN ('live', 'done')),
  -- The last failed update, shown on the card. A good update clears it.
  error TEXT,
  created_at INTEGER NOT NULL,
  -- The last good update.
  updated_at INTEGER NOT NULL,
  -- The last update of any kind. The card is stale when it is older than
  -- stale_after seconds.
  seen_at INTEGER NOT NULL,
  done_at INTEGER,
  PRIMARY KEY (sprint, key)
);`

// liveDoneFor is how long the dashboard keeps showing a done item.
const liveDoneFor = time.Hour

// livePath is $SPRINT_LIVE_DB, else live.db beside the log.
func livePath(dbPath string) string {
	if v := os.Getenv("SPRINT_LIVE_DB"); v != "" {
		return v
	}
	return filepath.Join(filepath.Dir(dbPath), "live.db")
}

// openLive opens the live file and creates its table. Each write is one
// statement, so it needs no pinned connection.
func openLive(path string) (Store, func()) {
	abs, err := filepath.Abs(path)
	check(err)
	check(os.MkdirAll(filepath.Dir(abs), 0o755))
	db, err := sql.Open("sqlite", dsn(abs, ""))
	check(err)
	s := Store{db}
	s.exec("PRAGMA journal_mode=WAL")
	s.exec(liveSQL)
	return s, func() { db.Close() }
}

type LiveItem struct {
	Sprint, Key, Subgoal, Title, Body string
	Done, Total                       sql.NullFloat64
	EndsAt, StaleAfter                sql.NullInt64
	Link, State, Error                string
	UpdatedAt, SeenAt                 int64
}

const liveCols = "sprint, key, COALESCE(subgoal, ''), title, body, done_n, total_n, ends_at, stale_after, " +
	"COALESCE(link, ''), state, COALESCE(error, ''), updated_at, seen_at"

func scanLive(r interface{ Scan(...any) error }) LiveItem {
	var l LiveItem
	check(r.Scan(&l.Sprint, &l.Key, &l.Subgoal, &l.Title, &l.Body, &l.Done, &l.Total, &l.EndsAt, &l.StaleAfter,
		&l.Link, &l.State, &l.Error, &l.UpdatedAt, &l.SeenAt))
	return l
}

func (s Store) liveItem(sprint, key string) (LiveItem, bool) {
	var out LiveItem
	found := false
	s.each("SELECT "+liveCols+" FROM live_items WHERE sprint = ? AND key = ?", []any{sprint, key},
		func(r *sql.Rows) { out, found = scanLive(r), true })
	return out, found
}

// liveChange is one update to an item: column -> value, nil for NULL.
type liveChange map[string]any

// liveSet creates or updates an item and makes it live again. A new item
// needs a title.
func liveSet(s Store, sprint, key string, ch liveChange) (created bool) {
	at := now()
	if _, ok := s.liveItem(sprint, key); !ok {
		if ch["title"] == nil || ch["title"] == "" {
			fail("new live item %q needs --title", key)
		}
		s.exec("INSERT INTO live_items (sprint, key, title, created_at, updated_at, seen_at) VALUES (?, ?, ?, ?, ?, ?)",
			sprint, key, ch["title"], at, at, at)
		created = true
	}
	ch["state"], ch["done_at"], ch["error"], ch["updated_at"], ch["seen_at"] = "live", nil, nil, at, at
	liveUpdate(s, sprint, key, ch)
	return created
}

func liveUpdate(s Store, sprint, key string, ch liveChange) {
	cols := make([]string, 0, len(ch))
	args := make([]any, 0, len(ch)+2)
	for col, v := range ch {
		cols = append(cols, col+" = ?")
		args = append(args, v)
	}
	s.exec("UPDATE live_items SET "+strings.Join(cols, ", ")+" WHERE sprint = ? AND key = ?",
		append(args, sprint, key)...)
}

// clearable reads a flag whose value "-" means "clear it".
func clearable(c *call, name string, parse func(string) any, ch liveChange, cols ...string) {
	if !c.has(name) {
		return
	}
	v := c.flag(name)
	if v == "-" {
		for _, col := range cols {
			ch[col] = nil
		}
		return
	}
	switch p := parse(v).(type) {
	case [2]float64:
		ch[cols[0]], ch[cols[1]] = p[0], p[1]
	default:
		ch[cols[0]] = p
	}
}

func parseProgress(v string) any {
	n, m, ok := strings.Cut(v, "/")
	done, err1 := strconv.ParseFloat(strings.TrimSpace(n), 64)
	total, err2 := strconv.ParseFloat(strings.TrimSpace(m), 64)
	if !ok || err1 != nil || err2 != nil || total <= 0 || done < 0 {
		fail("--progress must look like 7/12, not %q", v)
	}
	return [2]float64{done, total}
}

// parseTime takes RFC 3339 (seconds optional), unix seconds, or +<duration>
// from now.
func parseTime(v string) any {
	if d, ok := strings.CutPrefix(v, "+"); ok {
		dur, err := time.ParseDuration(d)
		if err != nil {
			fail("bad time %q: %v", v, err)
		}
		return now() + int64(dur.Seconds())
	}
	if n, err := strconv.ParseInt(v, 10, 64); err == nil {
		return n
	}
	for _, layout := range []string{time.RFC3339, "2006-01-02T15:04Z07:00"} {
		if t, err := time.Parse(layout, v); err == nil {
			return t.Unix()
		}
	}
	fail("bad time %q: use 2026-11-04T18:30+08:00, unix seconds, or +45m", v)
	return nil
}

func parseSeconds(v string) any {
	d, err := time.ParseDuration(v)
	if err != nil || d < time.Second {
		fail("bad duration %q: use 90s, 3m or 1h", v)
	}
	return int64(d.Seconds())
}

func parseText(v string) any { return v }

// readLiveBody reads --file before the write lock, like readBody, but an
// empty body is allowed.
func readLiveBody(c *call) {
	if !c.has("file") {
		return
	}
	var data []byte
	var err error
	if c.flag("file") == "-" {
		data, err = io.ReadAll(os.Stdin)
	} else {
		data, err = os.ReadFile(c.flag("file"))
	}
	check(err)
	c.fetched = strings.TrimSpace(string(data))
}

// liveScope resolves the sprint in the log and opens the live file.
func liveScope(c *call) (Sprint, Store, func()) {
	sp := c.store.resolve(c.flag("sprint"))
	checkKey("live item", c.pos["key"])
	s, closeLive := openLive(livePath(c.dbPath))
	return sp, s, closeLive
}

func cmdLiveSet(c *call) {
	sp, s, closeLive := liveScope(c)
	defer closeLive()
	ch := liveChange{}
	if c.has("title") {
		ch["title"] = c.flag("title")
	}
	if c.has("subgoal") {
		ch["subgoal"] = null(c.store.pickSubgoal(sp.ID, c.flag("subgoal"), true, false))
	}
	if body, ok := c.fetched.(string); ok {
		ch["body"] = body
	}
	clearable(c, "progress", parseProgress, ch, "done_n", "total_n")
	clearable(c, "ends-at", parseTime, ch, "ends_at")
	clearable(c, "stale-after", parseSeconds, ch, "stale_after")
	clearable(c, "link", parseText, ch, "link")
	verb := "updated"
	if liveSet(s, sp.Slug, c.pos["key"], ch) {
		verb = "added"
	}
	c.printf("live %s: %s\n", c.pos["key"], verb)
}

func cmdLiveDone(c *call) {
	sp, s, closeLive := liveScope(c)
	defer closeLive()
	cur, ok := s.liveItem(sp.Slug, c.pos["key"])
	if !ok {
		fail("no live item %q", c.pos["key"])
	}
	at := now()
	ch := liveChange{"state": "done", "done_at": at, "error": nil, "updated_at": at, "seen_at": at}
	if body, ok := c.fetched.(string); ok {
		ch["body"] = body
	}
	liveUpdate(s, sp.Slug, cur.Key, ch)
	c.printf("live %s: done; the dashboard shows it for %s more\n", cur.Key, liveDoneFor)
}

func cmdLiveRm(c *call) {
	sp, s, closeLive := liveScope(c)
	defer closeLive()
	n, err := s.exec("DELETE FROM live_items WHERE sprint = ? AND key = ?", sp.Slug, c.pos["key"]).RowsAffected()
	check(err)
	if n == 0 {
		fail("no live item %q", c.pos["key"])
	}
	c.printf("live %s: removed\n", c.pos["key"])
}

func ago(at int64) string {
	d := time.Duration(now()-at) * time.Second
	switch {
	case d < 2*time.Minute:
		return fmt.Sprintf("%d s ago", int(d.Seconds()))
	case d < 2*time.Hour:
		return fmt.Sprintf("%d min ago", int(d.Minutes()))
	}
	return fmt.Sprintf("%.1f h ago", d.Hours())
}

func (l LiveItem) stale() bool {
	return l.State == "live" && l.StaleAfter.Valid && now()-l.SeenAt > l.StaleAfter.Int64
}

func cmdLiveLs(c *call) {
	sp := c.store.resolve(c.flag("sprint"))
	s, closeLive := openLive(livePath(c.dbPath))
	defer closeLive()
	s.each("SELECT "+liveCols+" FROM live_items WHERE sprint = ? ORDER BY state = 'done', created_at, key",
		[]any{sp.Slug}, func(r *sql.Rows) {
			l := scanLive(r)
			state := l.State
			if l.stale() {
				state = "stale"
			}
			where := "-"
			if l.Subgoal != "" {
				where = l.Subgoal
			}
			progress := ""
			if l.Total.Valid {
				progress = fmt.Sprintf(" %s/%s", fmtNum(l.Done.Float64), fmtNum(l.Total.Float64))
			}
			c.printf("%s\t%s\t%s\t%s%s\t%s\n", l.Key, state, where, ago(l.UpdatedAt), progress, l.Title)
			if l.Error != "" {
				c.printf("\terror: %s\n", l.Error)
			}
		})
}
