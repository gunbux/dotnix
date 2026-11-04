package main

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func (h *harness) live(q string, args ...any) string {
	h.t.Helper()
	db, err := sql.Open("sqlite", "file:"+filepath.Join(filepath.Dir(h.db), "live.db"))
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
		rows.Scan(ptrs...)
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

func liveSprint(t *testing.T) *harness {
	h := newHarness(t)
	h.ok("start", "s1", "One", "--goal", "g")
	h.ok("sub", "add", "bench", "Benchmarks", "--goal", "g", "--status", "active")
	return h
}

func TestLiveSetAddsThenUpdatesInPlace(t *testing.T) {
	h := liveSprint(t)
	body := h.file("body.md", "In flight: run 8.\n")
	eq(t, h.ok("live", "set", "warm", "--title", "Benchmark: warm reviews", "--subgoal", "bench",
		"--progress", "7/12", "--ends-at", "2026-11-04T18:30+08:00", "--stale-after", "3m",
		"--link", "https://example.com/run", "--file", body), "live warm: added\n")
	eq(t, h.live("SELECT sprint, subgoal, title, body, done_n, total_n, ends_at, stale_after, link, state FROM live_items"),
		"(s1, bench, Benchmark: warm reviews, In flight: run 8., 7, 12, 1793788200, 180, https://example.com/run, live)")
	h.clock(1060)
	eq(t, h.ok("live", "set", "warm", "--progress", "8/12"), "live warm: updated\n")
	// Fields not given keep their values; one row per key.
	eq(t, h.live("SELECT title, body, done_n, subgoal, created_at, updated_at FROM live_items"),
		"(Benchmark: warm reviews, In flight: run 8., 8, bench, 1000, 1060)")
}

func TestLiveSetClearsFieldsWithADash(t *testing.T) {
	h := liveSprint(t)
	h.ok("live", "set", "ci", "--title", "CI", "--subgoal", "bench", "--progress", "1/3", "--link", "https://x", "--ends-at", "+30m")
	eq(t, h.live("SELECT ends_at FROM live_items"), "(2800)")
	h.ok("live", "set", "ci", "--progress", "-", "--link", "-", "--ends-at", "-", "--subgoal", "-")
	eq(t, h.live("SELECT done_n, total_n, link, ends_at, subgoal FROM live_items"), "(<nil>, <nil>, <nil>, <nil>, <nil>)")
}

func TestLiveSetChecksItsInput(t *testing.T) {
	h := liveSprint(t)
	contains_(t, h.fails("live", "set", "x"), "needs --title")
	contains_(t, h.fails("live", "set", "x", "--title", "X", "--progress", "7"), "must look like 7/12")
	contains_(t, h.fails("live", "set", "x", "--title", "X", "--progress", "1/0"), "must look like 7/12")
	contains_(t, h.fails("live", "set", "x", "--title", "X", "--progress", "NaN/12"), "must look like 7/12")
	contains_(t, h.fails("live", "set", "x", "--title", "X", "--progress", "1/Inf"), "must look like 7/12")
	contains_(t, h.fails("live", "set", "x", "--title", "X", "--ends-at", "tomorrow"), "bad time")
	contains_(t, h.fails("live", "set", "x", "--title", "X", "--stale-after", "soon"), "bad duration")
	contains_(t, h.fails("live", "set", "x", "--title", "X", "--subgoal", "nope"), `no subgoal "nope"`)
	contains_(t, h.fails("live", "set", "Bad Key", "--title", "X"), "bad live item")
	eq(t, h.live("SELECT COUNT(*) FROM live_items"), "(0)")
}

func TestLiveSetReadsTheBodyFromStdin(t *testing.T) {
	h := liveSprint(t)
	r, w, _ := os.Pipe()
	w.WriteString("| a | b |\n|---|---|\n| 1 | 2 |\n")
	w.Close()
	stdin := os.Stdin
	os.Stdin = r
	t.Cleanup(func() { os.Stdin = stdin })
	h.ok("live", "set", "t", "--title", "T", "--file", "-")
	eq(t, h.live("SELECT body FROM live_items"), "(| a | b |\n|---|---|\n| 1 | 2 |)")
}

func TestLiveDoneThenSetMakesItLiveAgain(t *testing.T) {
	h := liveSprint(t)
	h.ok("live", "set", "b", "--title", "B", "--progress", "11/12")
	h.clock(2000)
	contains_(t, h.ok("live", "done", "b", "--file", h.file("f.md", "All 12 runs ok.")), "done")
	eq(t, h.live("SELECT state, done_at, body, done_n FROM live_items"), "(done, 2000, All 12 runs ok., 11)")
	h.ok("live", "set", "b", "--progress", "1/12")
	eq(t, h.live("SELECT state, done_at FROM live_items"), "(live, <nil>)")
	contains_(t, h.fails("live", "done", "nope"), `no live item "nope"`)
}

func TestLiveRmAndLs(t *testing.T) {
	h := liveSprint(t)
	h.ok("live", "set", "a", "--title", "Alpha", "--stale-after", "1m", "--progress", "2/4")
	h.ok("live", "set", "b", "--title", "Beta", "--subgoal", "bench")
	h.clock(1100)
	out := h.ok("live", "ls")
	contains_(t, out, "a\tstale\t-\t100 s ago 2/4\tAlpha\n")
	contains_(t, out, "b\tlive\tbench\t100 s ago\tBeta\n")
	h.ok("live", "rm", "a")
	contains_(t, h.fails("live", "rm", "a"), `no live item "a"`)
	eq(t, h.live("SELECT key FROM live_items"), "(b)")
}

func TestLiveItemsBelongToTheirSprint(t *testing.T) {
	h := liveSprint(t)
	h.ok("start", "s2", "Two", "--goal", "g")
	h.ok("--sprint", "s1", "live", "set", "k", "--title", "One's")
	h.ok("--sprint", "s2", "live", "set", "k", "--title", "Two's")
	eq(t, h.live("SELECT sprint, title FROM live_items ORDER BY sprint"), "(s1, One's) (s2, Two's)")
	h.ok("--sprint", "s2", "live", "rm", "k")
	eq(t, h.live("SELECT sprint FROM live_items"), "(s1)")
}

func TestInitCreatesTheLiveFile(t *testing.T) {
	h := newHarness(t)
	h.ok("init")
	eq(t, h.live("SELECT COUNT(*) FROM live_items"), "(0)")
}

func TestContextSetIfMissingLeavesAnExistingSection(t *testing.T) {
	h := liveSprint(t)
	h.ok("context", "set", "findings", "--title", "Findings", "--file", h.file("a.md", "first"))
	eq(t, h.ok("context", "set", "findings", "--title", "Findings", "--if-missing", "--file", h.file("b.md", "template")),
		"section findings: exists, left alone\n")
	// Another scope is another section.
	eq(t, h.ok("context", "set", "findings", "--title", "Findings", "--subgoal", "bench", "--if-missing",
		"--file", h.file("c.md", "template")), "section findings: added\n")
	eq(t, h.query("SELECT COALESCE(subgoal, '-'), body FROM context_state ORDER BY id"), "(-, first\n) (bench, template\n)")
	// A removed section counts as missing.
	h.ok("context", "rm", "findings")
	eq(t, h.ok("context", "set", "findings", "--title", "Findings", "--if-missing", "--file", h.file("d.md", "again")),
		"section findings: added\n")
}

func TestContextLsListsSectionsByScope(t *testing.T) {
	h := liveSprint(t)
	h.ok("context", "set", "arch", "--title", "Architecture", "--file", h.file("a.md", "x"))
	h.ok("context", "set", "env", "--title", "Environment", "--subgoal", "bench", "--file", h.file("b.md", "y"))
	h.ok("context", "set", "gone", "--title", "Gone", "--file", h.file("c.md", "z"))
	h.ok("context", "rm", "gone")
	eq(t, h.ok("context", "ls"), "-\tarch\tArchitecture\t1970-01-01 08:16\nbench\tenv\tEnvironment\t1970-01-01 08:16\n")
	eq(t, h.ok("context", "ls", "--subgoal", "bench"), "bench\tenv\tEnvironment\t1970-01-01 08:16\n")
	eq(t, h.ok("context", "ls", "--subgoal", "-"), "-\tarch\tArchitecture\t1970-01-01 08:16\n")
	contains_(t, h.fails("context", "ls", "--subgoal", "nope"), `no subgoal "nope"`)
}
