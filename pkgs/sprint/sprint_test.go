package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

type harness struct {
	t   *testing.T
	dir string
	db  string
}

func newHarness(t *testing.T) *harness {
	dir := t.TempDir()
	h := &harness{t: t, dir: dir, db: filepath.Join(dir, "state", "sprint.db")}
	t.Setenv("SPRINT", "")
	t.Setenv("SPRINT_SUBGOAL", "")
	h.clock(1000)
	return h
}

func (h *harness) clock(at int64) { h.t.Setenv("SPRINT_NOW", strconv.FormatInt(at, 10)) }

func (h *harness) run(args ...string) (int, string, string) {
	var out, errOut bytes.Buffer
	code := run(append([]string{"--db", h.db}, args...), &out, &errOut)
	return code, out.String(), errOut.String()
}

func (h *harness) ok(args ...string) string {
	h.t.Helper()
	code, out, errOut := h.run(args...)
	if code != 0 {
		h.t.Fatalf("sprint %v: exit %d: %s", args, code, errOut)
	}
	return out
}

// fails runs a command that must fail and returns its error text.
func (h *harness) fails(args ...string) string {
	h.t.Helper()
	code, _, errOut := h.run(args...)
	if code == 0 {
		h.t.Fatalf("sprint %v: want failure", args)
	}
	return errOut
}

func (h *harness) show(args ...string) summary {
	h.t.Helper()
	var s summary
	if err := json.Unmarshal([]byte(h.ok(append(args, "show", "--json")...)), &s); err != nil {
		h.t.Fatal(err)
	}
	return s
}

// query returns the rows as text, for short comparisons.
func (h *harness) query(q string, args ...any) string {
	h.t.Helper()
	db, err := sql.Open("sqlite", "file:"+h.db)
	if err != nil {
		h.t.Fatal(err)
	}
	defer db.Close()
	rows, err := db.Query(q, args...)
	if err != nil {
		h.t.Fatal(err)
	}
	defer rows.Close()
	cols, _ := rows.Columns()
	var out []string
	for rows.Next() {
		vals := make([]any, len(cols))
		ptrs := make([]any, len(cols))
		for i := range vals {
			ptrs[i] = &vals[i]
		}
		if err := rows.Scan(ptrs...); err != nil {
			h.t.Fatal(err)
		}
		parts := make([]string, len(vals))
		for i, v := range vals {
			if b, ok := v.([]byte); ok {
				v = string(b)
			}
			parts[i] = fmt.Sprint(v)
		}
		out = append(out, "("+strings.Join(parts, ", ")+")")
	}
	return strings.Join(out, " ")
}

func (h *harness) file(name, text string) string {
	path := filepath.Join(h.dir, name)
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		h.t.Fatal(err)
	}
	return path
}

func eq[T comparable](t *testing.T, got, want T) {
	t.Helper()
	if got != want {
		t.Fatalf("\ngot:  %v\nwant: %v", got, want)
	}
}

func contains_(t *testing.T, text, want string) {
	t.Helper()
	if !strings.Contains(text, want) {
		t.Fatalf("%q does not contain %q", text, want)
	}
}

// fakeGH makes every GitHub call return this PR.
func fakeGH(t *testing.T, state, mergedAt, closedAt, url string) {
	stubGH(t, func(string) (prInfo, error) {
		return prInfo{Title: "Add T3 Ask", URL: url, State: state, CreatedAt: "2026-11-02T10:00:00Z",
			MergedAt: mergedAt, ClosedAt: closedAt}, nil
	})
}

func stubGH(t *testing.T, fn func(string) (prInfo, error)) {
	real := ghPR
	ghPR = fn
	t.Cleanup(func() { ghPR = real })
}

const pr3 = "https://github.com/o/r/pull/3"

func TestRowsCannotBeUpdatedOrDeleted(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "Sprint one", "--goal", "ship it")
	db, _ := sql.Open("sqlite", "file:"+h.db)
	defer db.Close()
	for _, q := range []string{"UPDATE goal_versions SET text = 'x'", "DELETE FROM goal_versions",
		"UPDATE sprints SET title = 'x'", "DELETE FROM sprints"} {
		_, err := db.Exec(q)
		if err == nil || !strings.Contains(err.Error(), "append-only") {
			t.Fatalf("%s: %v", q, err)
		}
	}
}

func TestGoalChangeKeepsEveryVersion(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "Sprint one", "--goal", "watch face")
	h.clock(2000)
	h.ok("goal", "watch face and bus app", "--reason", "add the bus app too")
	d := h.show()
	eq(t, d.Goal, "watch face and bus app")
	eq(t, d.GoalVersion, 2)
	eq(t, h.query("SELECT text, reason FROM goal_versions ORDER BY at"),
		"(watch face, sprint start) (watch face and bus app, add the bus app too)")
	eq(t, h.query("SELECT kind FROM log"), "(steer)")
}

func TestProgressCountsDoneOverInScopeAndSkipsDropped(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "Sprint one", "--goal", "g")
	for _, title := range []string{"a", "b", "c", "d"} {
		h.ok("item", "add", title)
	}
	h.ok("item", "set", "1", "done")
	h.ok("item", "set", "2", "done")
	h.ok("item", "set", "3", "dropped")
	d := h.show()
	eq(t, fmt.Sprint(d.Done, d.InScope, d.Dropped, d.Percent), "2 3 1 67")
}

func TestBurnupShowsScopeGrowthOverTime(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "Sprint one", "--goal", "g")
	h.ok("item", "add", "a")
	h.ok("item", "add", "b")
	h.clock(2000)
	h.ok("item", "set", "1", "done")
	h.clock(3000)
	h.ok("item", "add", "c")
	h.ok("item", "set", "2", "dropped")
	eq(t, h.query("SELECT time, in_scope, done FROM burnup ORDER BY time"), "(1000, 2, 0) (2000, 2, 1) (3000, 2, 1)")
}

func TestItemSetKeepsTitleOwnerAndPosition(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "Sprint one", "--goal", "g")
	h.ok("item", "add", "plug in the watch", "--owner", "user")
	h.ok("item", "add", "build")
	h.ok("item", "add", "merge", "--owner", "user", "--after", "1")
	h.ok("item", "set", "1", "blocked", "--note", "watch at home")
	d := h.show()
	var titles, doNow []string
	for _, i := range d.Items {
		titles = append(titles, i.Title)
	}
	for _, i := range d.DoNow {
		doNow = append(doNow, i.Title+":"+i.Status)
	}
	eq(t, strings.Join(titles, ","), "plug in the watch,merge,build")
	eq(t, strings.Join(doNow, ","), "plug in the watch:blocked,merge:planned")
}

func TestSprintResolution(t *testing.T) {
	h := newHarness(t)
	contains_(t, h.fails("show"), "no open sprint")
	h.ok("start", "s1", "One", "--goal", "g")
	eq(t, h.show().Sprint, "s1")
	h.ok("start", "s2", "Two", "--goal", "g")
	contains_(t, h.fails("show"), "several open sprints")
	eq(t, h.show("--sprint", "s1").Sprint, "s1")
	t.Setenv("SPRINT", "s2")
	eq(t, h.show().Sprint, "s2")
	t.Setenv("SPRINT", "")
	h.ok("--sprint", "s2", "end")
	eq(t, h.show().Sprint, "s1")
}

func TestDuplicateSlugIsRefused(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "One", "--goal", "g")
	contains_(t, h.fails("start", "s1", "Again", "--goal", "g"), "already exists")
}

func TestParallelItemAddsGetDistinctNumbers(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "One", "--goal", "g")
	var wg sync.WaitGroup
	var mu sync.Mutex
	var errs []string
	for n := 0; n < 6; n++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < 5; i++ {
				var e bytes.Buffer
				if run([]string{"--db", h.db, "item", "add", fmt.Sprintf("t%d-%d", n, i)}, io.Discard, &e) != 0 {
					mu.Lock()
					errs = append(errs, e.String())
					mu.Unlock()
				}
			}
		}()
	}
	wg.Wait()
	eq(t, strings.Join(errs, ""), "")
	eq(t, h.query("SELECT COUNT(DISTINCT item), COUNT(*) FROM item_events"), "(30, 30)")
}

func TestSlugMustBeURLAndSQLSafe(t *testing.T) {
	h := newHarness(t)
	for _, bad := range []string{"a&b", "it's", "Big", "a b", ""} {
		contains_(t, h.fails("start", bad, "x", "--goal", "g"), "bad slug")
	}
	h.ok("start", "garmin.v2_x-1", "ok", "--goal", "g")
	if !strings.HasSuffix(h.show().Page, "/s/garmin.v2_x-1") {
		t.Fatal(h.show().Page)
	}
}

func TestOldViewsAreReplacedOnUpgrade(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "One", "--goal", "g")
	db, _ := sql.Open("sqlite", "file:"+h.db)
	for _, q := range []string{"DROP VIEW burnup",
		"CREATE VIEW burnup AS SELECT 1 AS sprint_id, 0 AS time, 0 AS in_scope, 0 AS done",
		"PRAGMA user_version = 1"} {
		if _, err := db.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	db.Close()
	h.ok("item", "add", "a")
	eq(t, h.query("PRAGMA user_version"), fmt.Sprintf("(%d)", SchemaVersion))
	eq(t, h.query("SELECT time, in_scope, done FROM burnup"), "(1000, 1, 0)")
}

func TestSubgoalColumnsAreAddedToAnOldLog(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "One", "--goal", "g")
	h.ok("item", "add", "a")
	db, _ := sql.Open("sqlite", "file:"+h.db)
	for _, v := range views {
		db.Exec("DROP VIEW " + v)
	}
	for _, tc := range addedColumns {
		if _, err := db.Exec(fmt.Sprintf("ALTER TABLE %s DROP COLUMN %s", tc[0], tc[1])); err != nil {
			t.Fatal(err)
		}
	}
	db.Exec("PRAGMA user_version = 2")
	db.Close()
	h.ok("item", "add", "b")
	eq(t, h.query("SELECT title, subgoal FROM item_state ORDER BY item"), "(a, <nil>) (b, <nil>)")
}

func TestPRHistoryComesFromGitHubTimes(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "One", "--goal", "g")
	fakeGH(t, "OPEN", "", "", pr3)
	h.ok("pr", "add", pr3)
	h.clock(5000)
	h.ok("pr", "ready", pr3)
	fakeGH(t, "MERGED", "2026-11-03T01:00:00Z", "", pr3)
	h.ok("pr", "sync")
	h.ok("pr", "sync")
	eq(t, h.query("SELECT state, at FROM pr_events ORDER BY id"), "(opened, 1793613600) (ready, 5000) (merged, 1793667600)")
	eq(t, h.show().PRs[0].State, "merged")
}

func TestReopenedPRIsTrackedAgain(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "One", "--goal", "g")
	fakeGH(t, "CLOSED", "", "2026-11-02T12:00:00Z", pr3)
	h.ok("pr", "add", pr3)
	h.clock(1793700000)
	fakeGH(t, "OPEN", "", "", pr3)
	h.ok("pr", "sync")
	fakeGH(t, "MERGED", "2026-11-03T12:00:00Z", "", pr3)
	h.ok("pr", "sync")
	eq(t, h.query("SELECT state FROM pr_events ORDER BY id"), "(opened) (closed) (opened) (merged)")
	eq(t, h.show().PRs[0].State, "merged")
}

func TestReadyNeverReplacesAMerge(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "One", "--goal", "g")
	fakeGH(t, "MERGED", "2026-11-03T01:00:00Z", "", pr3)
	h.ok("pr", "add", pr3)
	contains_(t, h.fails("pr", "ready", pr3), "already merged")
	// Ready recorded before the merge is synced: the later-recorded merge
	// wins even though GitHub's merge time is earlier than ready.
	other := "https://github.com/o/r/pull/4"
	fakeGH(t, "OPEN", "", "", other)
	h.ok("pr", "add", other)
	h.clock(1793700000)
	h.ok("pr", "ready", other)
	fakeGH(t, "MERGED", "2026-11-03T01:00:00Z", "", other)
	h.ok("pr", "sync")
	for _, p := range h.show().PRs {
		if p.URL == other {
			eq(t, p.State, "merged")
		}
	}
}

// stubDuring replaces the GitHub call and runs during while it is in flight.
func stubDuring(t *testing.T, during func(), state string) {
	stubGH(t, func(url string) (prInfo, error) {
		during()
		return prInfo{Title: "T", URL: url, State: state, CreatedAt: "2026-11-02T10:00:00Z",
			ClosedAt: "2026-11-02T12:00:00Z"}, nil
	})
}

func TestSyncKeepsTheSprintItStartedWith(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "a", "A", "--goal", "g")
	fakeGH(t, "OPEN", "", "", pr3)
	h.ok("pr", "add", pr3)
	stubDuring(t, func() {
		run([]string{"--db", h.db, "--sprint", "a", "end"}, io.Discard, io.Discard)
		run([]string{"--db", h.db, "start", "b", "B", "--goal", "g"}, io.Discard, io.Discard)
	}, "CLOSED")
	h.ok("pr", "sync")
	eq(t, h.query("SELECT s.slug, p.state FROM pr_events p JOIN sprints s ON s.id = p.sprint_id ORDER BY p.id"),
		"(a, opened) (a, closed)")
}

func TestStaleGitHubResultIsDropped(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "a", "A", "--goal", "g")
	fakeGH(t, "OPEN", "", "", pr3)
	h.ok("pr", "add", pr3)
	stubDuring(t, func() { run([]string{"--db", h.db, "pr", "ready", pr3}, io.Discard, io.Discard) }, "CLOSED")
	contains_(t, h.ok("pr", "sync"), "changed during the GitHub call")
	eq(t, h.query("SELECT state FROM pr_events ORDER BY id"), "(opened) (ready)")
}

func TestRenamedRepoKeepsSyncing(t *testing.T) {
	h := newHarness(t)
	old := "https://github.com/o/old-name/pull/3"
	h.ok("start", "a", "A", "--goal", "g")
	fakeGH(t, "OPEN", "", "", old)
	h.ok("pr", "add", old)
	fakeGH(t, "MERGED", "2026-11-03T01:00:00Z", "", "https://github.com/o/new-name/pull/3")
	h.ok("pr", "sync")
	eq(t, h.query("SELECT url, state FROM pr_events ORDER BY id"), fmt.Sprintf("(%s, opened) (%s, merged)", old, old))
	h.ok("pr", "add", old)
	eq(t, h.query("SELECT COUNT(DISTINCT url) FROM pr_events"), "(1)")
}

func TestPRAddByNumberUsesGitHubsURL(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "a", "A", "--goal", "g")
	fakeGH(t, "OPEN", "", "", pr3)
	h.ok("pr", "add", "3")
	h.ok("pr", "add", pr3)
	eq(t, h.query("SELECT url, state FROM pr_events"), "("+pr3+", opened)")
}

func TestSyncSkipsAPRItCannotRead(t *testing.T) {
	h := newHarness(t)
	gone := "https://github.com/o/gone/pull/1"
	h.ok("start", "a", "A", "--goal", "g")
	fakeGH(t, "OPEN", "", "", gone)
	h.ok("pr", "add", gone)
	fakeGH(t, "OPEN", "", "", pr3)
	h.ok("pr", "add", pr3)
	stubGH(t, func(url string) (prInfo, error) {
		if url == gone {
			return prInfo{}, fmt.Errorf("Could not resolve to a Repository")
		}
		return prInfo{Title: "T", URL: url, State: "MERGED", CreatedAt: "2026-11-02T10:00:00Z",
			MergedAt: "2026-11-03T01:00:00Z"}, nil
	})
	code, _, errOut := h.run("pr", "sync")
	eq(t, code, 0)
	contains_(t, errOut, "could not read "+gone)
	states := map[string]string{}
	for _, p := range h.show().PRs {
		states[p.URL] = p.State
	}
	eq(t, states[gone]+","+states[pr3], "opened,merged")
}

func TestBenchAndLog(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "One", "--goal", "g")
	h.ok("bench", "build", "seconds", "48", "s", "--baseline")
	h.ok("bench", "build", "seconds", "31", "s", "--commit", "abc123")
	h.ok("bench", "delta", "x", "-5", "s")
	h.ok("log", "decision", "keep the bridge on legion-nix", "--link", "https://example.com")
	eq(t, h.query("SELECT value, is_baseline FROM bench_results ORDER BY id"), "(48, 1) (31, 0) (-5, 0)")
	eq(t, h.query("SELECT kind, text FROM log"), "(decision, keep the bridge on legion-nix)")
}

func TestFlagsAndArgsAreChecked(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "One", "--goal", "g")
	contains_(t, h.fails("item", "add", "x", "--owner", "bob"), "--owner must be one of agent, user")
	contains_(t, h.fails("item", "set", "1", "finished"), "status must be one of")
	contains_(t, h.fails("item", "add"), "missing title")
	contains_(t, h.fails("item", "add", "a", "b"), `unexpected "b"`)
	contains_(t, h.fails("item", "add", "a", "--nope"), "unknown flag --nope")
	contains_(t, h.fails("goal", "x"), "--reason is required")
	contains_(t, h.fails("frobnicate"), "unknown command")
	contains_(t, h.ok("item", "add", "--help"), "usage: sprint item add <title>")
}

func TestSubgoalsHoldTheirOwnGoalAndItems(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "k8s", "K8s backend", "--goal", "Kubernetes backend for Grepbox")
	h.ok("item", "add", "sprint-wide chore")
	h.ok("sub", "add", "parity", "Parity", "--goal", "same results as Firecracker",
		"--done-when", "bench within 5%", "--status", "active")
	h.ok("sub", "add", "hot-snap", "Hot snapshotting", "--goal", "resume from a warm snapshot")
	h.ok("item", "add", "port the runner") // the only active subgoal
	h.ok("item", "add", "snapshot API", "--subgoal", "hot-snap")
	h.ok("item", "set", "2", "done")
	d := h.show()
	var items, subs []string
	for _, i := range d.Items {
		items = append(items, fmt.Sprint(i.Title, ":", i.Subgoal))
	}
	for _, g := range d.Subgoals {
		subs = append(subs, fmt.Sprint(g.Key, ":", g.Status, ":", g.Done, "/", g.InScope))
	}
	eq(t, strings.Join(items, ","), "sprint-wide chore:<nil>,port the runner:parity,snapshot API:hot-snap")
	eq(t, strings.Join(subs, ","), "parity:active:1/1,hot-snap:planned:0/1")
	if !strings.HasSuffix(d.Subgoals[0].Page, "/s/k8s/parity") {
		t.Fatal(d.Subgoals[0].Page)
	}
	h.ok("sub", "set", "hot-snap", "active")
	contains_(t, h.fails("item", "add", "which one?"), "several active subgoals (parity, hot-snap)")
	h.ok("item", "add", "whole sprint", "--subgoal", "-")
	h.ok("item", "set", "1", "--subgoal", "parity")
	eq(t, h.show().Subgoals[0].InScope, 2)
	contains_(t, h.fails("item", "add", "x", "--subgoal", "nope"), `no subgoal "nope"`)
}

func TestSubgoalGoalChangeNeedsAReasonAndIsKept(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "k8s", "K8s", "--goal", "g")
	h.ok("sub", "add", "parity", "Parity", "--goal", "match Firecracker")
	contains_(t, h.fails("sub", "set", "parity", "--goal", "match Firecracker and Grepbox"), "needs --reason")
	h.clock(2000)
	h.ok("sub", "set", "parity", "active", "--goal", "match Grepbox", "--reason", "Grepbox is the bar")
	eq(t, h.query("SELECT goal, status, reason FROM subgoal_events ORDER BY id"),
		"(match Firecracker, planned, added) (match Grepbox, active, Grepbox is the bar)")
	eq(t, h.query("SELECT kind, subgoal FROM log"), "(steer, parity)")
	contains_(t, h.fails("sub", "add", "parity", "Again", "--goal", "g"), "already exists")
}

func TestRecordsDefaultToTheActiveSubgoal(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "k8s", "K8s", "--goal", "g")
	h.ok("bench", "boot", "p50", "900", "ms", "--baseline")
	h.ok("sub", "add", "parity", "Parity", "--goal", "g", "--status", "active")
	h.ok("bench", "boot", "p50", "800", "ms")
	h.ok("log", "decision", "use containerd")
	fakeGH(t, "OPEN", "", "", pr3)
	h.ok("pr", "add", pr3)
	h.ok("pr", "ready", pr3)
	fakeGH(t, "MERGED", "2026-11-03T01:00:00Z", "", pr3)
	h.ok("sub", "set", "parity", "done")
	h.ok("pr", "sync")
	eq(t, h.query("SELECT subgoal FROM bench_results ORDER BY id"), "(<nil>) (parity)")
	eq(t, h.query("SELECT subgoal FROM log"), "(parity)")
	eq(t, h.query("SELECT state, subgoal FROM pr_events ORDER BY id"), "(opened, parity) (ready, parity) (merged, parity)")
	h.ok("sub", "set", "parity", "active")
	t.Setenv("SPRINT_SUBGOAL", "-")
	h.ok("log", "note", "sprint-wide")
	eq(t, h.query("SELECT subgoal FROM log ORDER BY id DESC LIMIT 1"), "(<nil>)")
}

func TestContextSectionsAreVersioned(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "k8s", "K8s", "--goal", "g")
	h.ok("sub", "add", "parity", "Parity", "--goal", "g")
	contains_(t, h.fails("context", "set", "arch", "--file", h.file("a.md", "x")), "needs --title")
	h.ok("context", "set", "arch", "--title", "Architecture", "--file", h.file("a.md", "v1"))
	h.ok("context", "set", "arch", "--file", h.file("a.md", "v2"))
	h.ok("context", "set", "arch", "--title", "Parity matrix", "--subgoal", "parity", "--file", h.file("b.md", "| a | b |"))
	contains_(t, h.fails("context", "set", "arch", "--file", h.file("e.md", "  \n")), "empty section")
	eq(t, h.query("SELECT subgoal, title, body FROM context_state ORDER BY id"),
		"(<nil>, Architecture, v2\n) (parity, Parity matrix, | a | b |\n)")
	h.ok("context", "set", "findings", "--title", "Findings so far", "--first", "--file", h.file("f.md", "f"))
	eq(t, h.query("SELECT key FROM context_state WHERE subgoal IS NULL ORDER BY position"), "(findings) (arch)")
	h.ok("context", "rm", "findings")
	h.ok("context", "rm", "arch")
	eq(t, h.query("SELECT subgoal FROM context_state"), "(parity)")
	eq(t, h.query("SELECT COUNT(*) FROM context_versions"), "(6)")
	contains_(t, h.fails("context", "rm", "arch"), `no section "arch"`)
}

// ---------------------------------------------------------------------------
// Pages

func pageHarness(t *testing.T) *harness {
	h := newHarness(t)
	h.ok("start", "k8s", "K8s <backend>", "--goal", "Kubernetes backend for Grepbox")
	h.ok("sub", "add", "parity", "Parity", "--goal", "match <Firecracker>", "--done-when", "bench within 5%", "--status", "active")
	h.ok("sub", "add", "hot-snap", "Hot snapshotting", "--goal", "warm resume")
	h.ok("item", "add", "port the runner")
	h.ok("item", "add", "merge the runner", "--owner", "user")
	h.clock(2000)
	h.ok("item", "set", "1", "done")
	h.ok("item", "set", "2", "--subgoal", "hot-snap")
	h.ok("sub", "set", "parity", "--goal", "match <Firecracker> on results", "--reason", "boot can trail")
	h.ok("bench", "boot", "p50", "900", "ms", "--baseline")
	h.ok("bench", "boot", "p50", "800", "ms", "--commit", "abcdef123456")
	h.ok("context", "set", "arch", "--title", "Architecture",
		"--file", h.file("a.md", "## Layers\n\n| a | b |\n|---|---|\n| 1 | 2 |\n"))
	return h
}

func (h *harness) sprintData(now int64) (Store, *sprintData) {
	db := openRead(h.db)
	h.t.Cleanup(func() { db.Close() })
	tx, err := db.Begin()
	if err != nil {
		h.t.Fatal(err)
	}
	h.t.Cleanup(func() { tx.Rollback() })
	s := Store{tx}
	return s, loadSprint(s, "k8s", now)
}

func TestBurnupFollowsAnItemIntoAnotherSubgoal(t *testing.T) {
	h := pageHarness(t)
	_, d := h.sprintData(3000)
	eq(t, fmt.Sprint(d.burnup("", true)), "[[1000 2 0] [2000 2 1] [3000 2 1]]")
	eq(t, fmt.Sprint(d.burnup("parity", false)), "[[1000 2 0] [2000 1 1] [3000 1 1]]")
	eq(t, fmt.Sprint(d.burnup("hot-snap", false)), "[[1000 0 0] [2000 1 0] [3000 1 0]]")
}

func TestPagesRenderAndEscape(t *testing.T) {
	h := pageHarness(t)
	s, d := h.sprintData(3000)
	goal := goalPage(s, d, false)
	for _, want := range []string{"K8s &lt;backend&gt;", "match &lt;Firecracker&gt;", `href="/s/k8s/parity"`,
		"<h2>Architecture</h2>", "<table>", "50%"} {
		contains_(t, goal, want)
	}
	if strings.Contains(goal, "<Firecracker>") {
		t.Fatal("unescaped subgoal goal")
	}
	sub := subgoalPage(s, d, "parity", false)
	for _, want := range []string{"bench within 5%", "-11.1%", "Subgoal history", "boot can trail"} {
		contains_(t, sub, want)
	}
	if strings.Contains(sub, "<h2>Architecture</h2>") {
		t.Fatal("sprint context on a subgoal page")
	}
	hot := subgoalPage(s, d, "hot-snap", false)
	contains_(t, hot, "Do now (you)")
	contains_(t, hot, "merge the runner")
}

func TestServerRoutesAndRefusesOtherHosts(t *testing.T) {
	h := pageHarness(t)
	ln, handler := listen(h.db, "127.0.0.1", "0")
	srv := &http.Server{Handler: handler}
	go srv.Serve(ln)
	t.Cleanup(func() { srv.Close() })
	get := func(path, host string) (int, string) {
		req, _ := http.NewRequest("GET", "http://"+ln.Addr().String()+path, nil)
		if host != "" {
			req.Host = host
		}
		c := &http.Client{Timeout: 5 * time.Second}
		r, err := c.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer r.Body.Close()
		b, _ := io.ReadAll(r.Body)
		return r.StatusCode, string(b)
	}
	for path, want := range map[string]int{"/": 200, "/s/k8s": 200, "/s/k8s/hot-snap": 200,
		"/s/k8s/nope": 404, "/s/nope": 404, "/s/k8s/parity/x": 404} {
		code, _ := get(path, "")
		eq(t, fmt.Sprint(path, " ", code), fmt.Sprint(path, " ", want))
	}
	code, body := get("/api/stamp", "")
	eq(t, code, 200)
	if strings.Trim(body, "0123456789.") != "" {
		t.Fatal(body)
	}
	code, _ = get("/s/k8s", "evil.example:80")
	eq(t, code, 403)
	// The page server's handle can't change the log.
	ro := openRead(h.db)
	defer ro.Close()
	if _, err := ro.Exec("INSERT INTO log (sprint_id, at, kind, text) VALUES (1, 1, 'note', 'x')"); err == nil {
		t.Fatal("read-only handle wrote to the log")
	}
}

func TestNewRecordsMustNameOneOfSeveralActiveSubgoals(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "k8s", "K8s", "--goal", "g")
	h.ok("sub", "add", "a", "A", "--goal", "g", "--status", "active")
	fakeGH(t, "OPEN", "", "", pr3)
	h.ok("pr", "add", pr3)
	h.ok("sub", "add", "b", "B", "--goal", "g", "--status", "active")
	for _, args := range [][]string{{"bench", "boot", "p50", "1", "ms"}, {"log", "note", "x"},
		{"pr", "add", "https://github.com/o/r/pull/4"}} {
		fakeGH(t, "OPEN", "", "", "https://github.com/o/r/pull/4")
		contains_(t, h.fails(args...), "several active subgoals (a, b)")
	}
	fakeGH(t, "OPEN", "", "", pr3)
	h.ok("pr", "add", pr3) // already tracked: keeps subgoal a
	h.ok("log", "note", "whole sprint", "--subgoal", "-")
	h.ok("bench", "boot", "p50", "1", "ms", "--subgoal", "b")
	eq(t, h.query("SELECT DISTINCT subgoal FROM pr_events"), "(a)")
	eq(t, h.query("SELECT subgoal FROM log"), "(<nil>)")
}

func TestHistoryShowsBenchStagesExitChecksAndContextVersions(t *testing.T) {
	h := pageHarness(t)
	h.clock(2500)
	h.ok("sub", "set", "parity", "--done-when", "bench within 2%", "--reason", "tighter bar")
	h.ok("sub", "set", "hot-snap", "active")
	h.ok("bench", "boot", "p50", "100", "ms", "--baseline", "--subgoal", "hot-snap")
	h.ok("context", "set", "arch", "--file", h.file("a2.md", "second *version*"))
	h.ok("context", "rm", "arch")
	s, d := h.sprintData(3000)
	goal := goalPage(s, d, false)
	// parity's run against parity's baseline; hot-snap's baseline alone.
	contains_(t, goal, "<td>Parity</td><td class=num>800</td><td class=num>900</td>")
	contains_(t, goal, "<td>Hot snapshotting</td><td class=num></td><td class=num>100</td>")
	contains_(t, goal, "done when changed: <s>bench within 5%</s> → bench within 2%")
	contains_(t, goal, "tighter bar")
	contains_(t, goal, "Section updated: <b>Architecture</b>")
	contains_(t, goal, "<em>version</em>")
	contains_(t, goal, "Section removed: <b>Architecture</b>")
	sub := subgoalPage(s, d, "parity", false)
	contains_(t, sub, "<th>Done when</th>")
	contains_(t, sub, "<td>bench within 2%</td>")
}
