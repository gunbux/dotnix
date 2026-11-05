package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
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
	// No test reaches GitHub: a PR's review state defaults to a bare open PR.
	stubStatus(t, func(url string) (prStatus, error) {
		return prStatus{URL: url, Number: 3, Title: "T", State: "OPEN", BaseRefName: "main", HeadRefOid: "0000000000"}, nil
	})
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
	if !strings.HasSuffix(h.show().Dashboard, "/d/sprint/sprint?from=1000000&to=now&var-sprint=garmin.v2_x-1&var-subgoal=-") {
		t.Fatal(h.show().Dashboard)
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
	if !strings.HasSuffix(d.Subgoals[0].Dashboard, "&var-sprint=k8s&var-subgoal=parity") {
		t.Fatal(d.Subgoals[0].Dashboard)
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
// Dashboard views (scoped_burnup, bench_summary, activity)

func viewHarness(t *testing.T) *harness {
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
	h.ok("context", "set", "arch", "--title", "Architecture", "--file", h.file("a.md", "v1"))
	return h
}

func TestScopedBurnupFollowsAnItemIntoAnotherSubgoal(t *testing.T) {
	h := viewHarness(t)
	eq(t, h.query("SELECT scope, time, in_scope, done FROM scoped_burnup ORDER BY scope, time"),
		"(-, 1000, 2, 0) (-, 2000, 2, 1) "+
			"(hot-snap, 1000, 0, 0) (hot-snap, 2000, 1, 0) "+
			"(parity, 1000, 2, 0) (parity, 2000, 1, 1)")
}

func TestBenchSummaryKeepsEachSubgoalApart(t *testing.T) {
	h := viewHarness(t)
	h.clock(2500)
	h.ok("sub", "set", "hot-snap", "active")
	h.ok("bench", "boot", "p50", "100", "ms", "--baseline", "--subgoal", "hot-snap")
	h.ok("bench", "boot", "p50", "720", "ms", "--subgoal", "parity")
	// parity's latest run against parity's baseline; hot-snap's baseline alone.
	eq(t, h.query("SELECT subgoal, latest, baseline, change, runs, last_at FROM bench_summary ORDER BY subgoal"),
		"(hot-snap, <nil>, 100, <nil>, 0, 2500) (parity, 720, 900, -20, 2, 2500)")
}

func TestActivityDescribesEveryChange(t *testing.T) {
	h := viewHarness(t)
	h.clock(2500)
	h.ok("sub", "set", "parity", "--done-when", "bench within 2%", "--reason", "tighter bar")
	h.ok("sub", "set", "hot-snap", "active")
	h.ok("context", "set", "arch", "--file", h.file("a2.md", "v2"))
	h.ok("context", "rm", "arch")
	h.ok("log", "decision", "keep Kata", "--subgoal", "-")
	fakeGH(t, "OPEN", "", "", pr3)
	h.ok("pr", "add", pr3, "--subgoal", "parity")
	got := h.query("SELECT COALESCE(subgoal, '-'), kind, text FROM activity ORDER BY at, kind, id")
	for _, want := range []string{
		"(-, goal, Goal v1: Kubernetes backend for Grepbox)",
		"(parity, subgoal, Subgoal added: Parity — match <Firecracker>)",
		"(parity, item, Planned #1 port the runner)",
		"(parity, item, Planned #2 merge the runner (your step))",
		"(parity, item, #1 port the runner: done)",
		"(hot-snap, item, #2 merge the runner moved to Hot snapshotting)",
		"(parity, subgoal, Parity: goal changed: match <Firecracker> on results — boot can trail)",
		"(parity, bench, Benchmark boot p50 = 900 ms (baseline))",
		"(-, context, Section added: Architecture)",
		"(parity, subgoal, Parity: done when changed: bench within 5% → bench within 2% — tighter bar)",
		"(hot-snap, subgoal, Hot snapshotting: planned → active)",
		"(-, context, Section updated: Architecture)",
		"(-, context, Section removed: Architecture)",
		"(-, decision, keep Kata)",
		"(parity, pr, PR opened: Add T3 Ask)",
	} {
		contains_(t, got, want)
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

func TestBenchRmHidesEarlierResults(t *testing.T) {
	h := viewHarness(t)
	h.clock(2500)
	h.ok("bench", "rm", "boot", "p50", "--subgoal", "parity", "--reason", "split by backend")
	eq(t, h.query("SELECT COUNT(*) FROM bench_summary WHERE suite = 'boot'"), "(0)")
	eq(t, h.query("SELECT COUNT(*) FROM bench_results WHERE suite = 'boot'"), "(2)")
	h.fails("bench", "rm", "boot", "p50", "--subgoal", "parity")
	// A result in the same second as the removal still shows.
	h.ok("bench", "boot", "p50", "700", "ms", "--subgoal", "parity")
	eq(t, h.query("SELECT latest, baseline, runs FROM bench_summary WHERE suite = 'boot'"), "(700, <nil>, 1)")
	eq(t, h.query("SELECT text FROM activity WHERE kind = 'bench' AND text LIKE 'Benchmark removed%'"),
		"(Benchmark removed: boot p50 (split by backend))")
}

func TestItemSetMovesAnItem(t *testing.T) {
	h := viewHarness(t)
	h.ok("item", "add", "later")
	h.ok("item", "add", "latest")
	// The harness has items 1 and 2; "later" is 3 and "latest" is 4.
	h.ok("item", "set", "4", "--first")
	h.ok("item", "set", "3", "--after", "4")
	eq(t, h.query("SELECT item FROM item_state ORDER BY position"), "(4) (3) (1) (2)")
	h.fails("item", "set", "1", "--first", "--after", "2")
}

func TestDoNowOrdersByStageThenStep(t *testing.T) {
	h := viewHarness(t)
	// Item 2 is the user's step in hot-snap (planned). Add one in parity
	// (active) and one for the whole sprint, then put the hot-snap step first
	// by position: the stage still decides the order.
	h.ok("item", "add", "approve the bench", "--owner", "user", "--subgoal", "parity")
	h.ok("item", "add", "switch dotnix", "--owner", "user", "--subgoal", "-")
	h.ok("item", "set", "2", "--first")
	eq(t, h.query("SELECT rank, item, COALESCE(subgoal, '-'), total FROM do_now ORDER BY rank"),
		"(1, 4, -, 3) (2, 3, parity, 3) (3, 2, hot-snap, 3)")
	h.ok("item", "set", "3", "done")
	eq(t, h.query("SELECT rank, item FROM do_now ORDER BY rank"), "(1, 4) (2, 2)")
	var d summary
	check(json.Unmarshal([]byte(h.ok("show", "--json")), &d))
	eq(t, fmt.Sprint(d.DoNow[0].Item, d.DoNow[1].Item), "4 2")
}

func TestSubSetMovesASubgoal(t *testing.T) {
	h := viewHarness(t)
	// The harness has parity, then hot-snap.
	h.ok("sub", "set", "hot-snap", "--first")
	eq(t, h.query("SELECT key FROM subgoal_state ORDER BY position"), "(hot-snap) (parity)")
	h.ok("sub", "set", "hot-snap", "--after", "parity")
	eq(t, h.query("SELECT key FROM subgoal_state ORDER BY position"), "(parity) (hot-snap)")
	h.fails("sub", "set", "parity", "--first", "--after", "hot-snap")
}
