package main

import (
	"database/sql"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// slugRE keeps slugs and keys safe in URLs and SQL literals.
var slugRE = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{0,63}$`)

// wholeSprint as a --subgoal value means "not in any subgoal".
const wholeSprint = "-"

func now() int64 {
	if v := os.Getenv("SPRINT_NOW"); v != "" {
		n, err := strconv.ParseInt(v, 10, 64)
		if err == nil {
			return n
		}
	}
	return time.Now().Unix()
}

// dashboardURL links to the Grafana dashboard (modules/home/sprint.nix) for
// a sprint, or for one subgoal of it, from the sprint's start until now.
// SPRINT_DASHBOARD_URL moves the base.
func dashboardURL(slug, subgoal string, startedAt int64) string {
	base := "http://127.0.0.1:3001"
	if v := os.Getenv("SPRINT_DASHBOARD_URL"); v != "" {
		base = strings.TrimRight(v, "/")
	}
	if subgoal == "" {
		subgoal = wholeSprint
	}
	q := url.Values{"var-sprint": {slug}, "var-subgoal": {subgoal},
		"from": {strconv.FormatInt(startedAt*1000, 10)}, "to": {"now"}}
	return base + "/d/sprint/sprint?" + q.Encode()
}

func checkKey(kind, key string) {
	if !slugRE.MatchString(key) {
		fail("bad %s %q: use lowercase letters, digits, '.', '_' or '-'", kind, key)
	}
}

type Sprint struct {
	ID        int64
	Slug      string
	Title     string
	StartedAt int64
}

const sprintCols = "id, slug, title, started_at"

func scanSprint(r interface{ Scan(...any) error }) Sprint {
	var s Sprint
	check(r.Scan(&s.ID, &s.Slug, &s.Title, &s.StartedAt))
	return s
}

type Goal struct {
	At                   int64
	Text, Reason, Source string
}

type Subgoal struct {
	Key                   string
	At                    int64
	Title, Goal, DoneWhen string
	Status                string
	Position              float64
	Reason, Source        string
	Done, InScope         int64 // filled from subgoal_progress where asked
}

const subgoalCols = "key, at, title, goal, COALESCE(done_when, ''), status, position, reason, source"

func scanSubgoal(r interface{ Scan(...any) error }) Subgoal {
	var g Subgoal
	check(r.Scan(&g.Key, &g.At, &g.Title, &g.Goal, &g.DoneWhen, &g.Status, &g.Position, &g.Reason, &g.Source))
	return g
}

type Item struct {
	Item                 int64
	At                   int64
	Title, Status, Owner string
	Position             float64
	Note, Subgoal        string
	// Step is the item's number in Do now (the do_now view's rank), or 0
	// when it is not an open user step. Only the PR board sets it.
	Step int
}

const itemCols = "item, at, title, status, owner, position, COALESCE(note, ''), COALESCE(subgoal, '')"

func scanItem(r interface{ Scan(...any) error }) Item {
	var i Item
	check(r.Scan(&i.Item, &i.At, &i.Title, &i.Status, &i.Owner, &i.Position, &i.Note, &i.Subgoal))
	return i
}

type PR struct {
	ID                         int64
	At                         int64
	URL, Title, State, Subgoal string
}

const prCols = "id, at, url, title, state, COALESCE(subgoal, '')"

func scanPR(r interface{ Scan(...any) error }) PR {
	var p PR
	check(r.Scan(&p.ID, &p.At, &p.URL, &p.Title, &p.State, &p.Subgoal))
	return p
}

type Bench struct {
	At                    int64
	Suite, Metric         string
	Value                 float64
	Unit                  string
	Baseline              bool
	Commit, Link, Subgoal string
}

const benchCols = "at, suite, metric, value, unit, is_baseline, COALESCE(commit_sha, ''), COALESCE(link, ''), COALESCE(subgoal, '')"

func scanBench(r interface{ Scan(...any) error }) Bench {
	var b Bench
	check(r.Scan(&b.At, &b.Suite, &b.Metric, &b.Value, &b.Unit, &b.Baseline, &b.Commit, &b.Link, &b.Subgoal))
	return b
}

type LogRow struct {
	At                        int64
	Kind, Text, Link, Subgoal string
}

const logCols = "at, kind, text, COALESCE(link, ''), COALESCE(subgoal, '')"

func scanLog(r interface{ Scan(...any) error }) LogRow {
	var l LogRow
	check(r.Scan(&l.At, &l.Kind, &l.Text, &l.Link, &l.Subgoal))
	return l
}

type Context struct {
	Subgoal, Key string
	At           int64
	Title, Body  string
	Position     float64
}

const contextCols = "COALESCE(subgoal, ''), key, at, title, body, position"

func scanContext(r interface{ Scan(...any) error }) Context {
	var c Context
	check(r.Scan(&c.Subgoal, &c.Key, &c.At, &c.Title, &c.Body, &c.Position))
	return c
}

func (s Store) openSprints() []Sprint {
	var out []Sprint
	s.each("SELECT "+sprintCols+" FROM sprints s WHERE NOT EXISTS "+
		"(SELECT 1 FROM log l WHERE l.sprint_id = s.id AND l.kind = 'end') "+
		"ORDER BY s.started_at DESC, s.id DESC", nil, func(r *sql.Rows) { out = append(out, scanSprint(r)) })
	return out
}

func (s Store) sprintBySlug(slug string) (Sprint, bool) {
	var sp Sprint
	ok := s.one("SELECT "+sprintCols+" FROM sprints WHERE slug = ?", []any{slug},
		&sp.ID, &sp.Slug, &sp.Title, &sp.StartedAt)
	return sp, ok
}

// resolve picks the sprint: --sprint, then $SPRINT, then the only open one.
func (s Store) resolve(slug string) Sprint {
	if slug == "" {
		slug = os.Getenv("SPRINT")
	}
	if slug != "" {
		sp, ok := s.sprintBySlug(slug)
		if !ok {
			fail("no sprint named %q", slug)
		}
		return sp
	}
	open := s.openSprints()
	switch len(open) {
	case 1:
		return open[0]
	case 0:
		fail("no open sprint; run `sprint start`")
	}
	names := make([]string, len(open))
	for i, sp := range open {
		names[i] = sp.Slug
	}
	fail("several open sprints (%s); pass --sprint or set SPRINT", strings.Join(names, ", "))
	return Sprint{}
}

func (s Store) latestItem(sprintID, item int64) Item {
	var it Item
	ok := s.one("SELECT "+itemCols+" FROM item_state WHERE sprint_id = ? AND item = ?", []any{sprintID, item},
		&it.Item, &it.At, &it.Title, &it.Status, &it.Owner, &it.Position, &it.Note, &it.Subgoal)
	if !ok {
		fail("no item %d in this sprint", item)
	}
	return it
}

func (s Store) latestSubgoal(sprintID int64, key string) Subgoal {
	var g Subgoal
	ok := s.one("SELECT "+subgoalCols+" FROM subgoal_state WHERE sprint_id = ? AND key = ?", []any{sprintID, key},
		&g.Key, &g.At, &g.Title, &g.Goal, &g.DoneWhen, &g.Status, &g.Position, &g.Reason, &g.Source)
	if !ok {
		fail("no subgoal %q in this sprint", key)
	}
	return g
}

// pickSubgoal names the subgoal a new record belongs to: --subgoal, then
// $SPRINT_SUBGOAL, then the only active subgoal. "-" means the whole sprint.
// "" means no subgoal.
func (s Store) pickSubgoal(sprintID int64, given string, isSet, required bool) string {
	key := given
	if !isSet {
		key = os.Getenv("SPRINT_SUBGOAL")
	}
	if key == wholeSprint {
		return ""
	}
	if key != "" {
		return s.latestSubgoal(sprintID, key).Key
	}
	active := s.strings("SELECT key FROM subgoal_state WHERE sprint_id = ? AND status = 'active' ORDER BY position", sprintID)
	if len(active) == 1 {
		return active[0]
	}
	if len(active) > 1 && required {
		fail("several active subgoals (%s); pass --subgoal, or --subgoal - for the whole sprint", strings.Join(active, ", "))
	}
	return ""
}

// positionAfter gives a position at the end, or between before and the next row.
func (s Store) positionAfter(view string, sprintID int64, before *float64) float64 {
	if before == nil {
		v, _ := s.float("SELECT COALESCE(MAX(position), 0) + 1 FROM "+view+" WHERE sprint_id = ?", sprintID)
		return v
	}
	after, ok := s.float("SELECT MIN(position) FROM "+view+" WHERE sprint_id = ? AND position > ?", sprintID, *before)
	if !ok {
		return *before + 1
	}
	return (*before + after) / 2
}
