package main

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// The detached poller re-runs this binary. Under `go test` that is the test
// binary, so it acts as the CLI when the tests ask.
func TestMain(m *testing.M) {
	if os.Getenv("SPRINT_TEST_AS_CLI") == "1" {
		os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
	}
	os.Exit(m.Run())
}

func TestPollResultReadsMarkdownOrJSON(t *testing.T) {
	eq(t, pollResult([]byte("  # Run 8\n\nok\n"))["body"], any("# Run 8\n\nok"))
	ch := pollResult([]byte(`{"body":"7 ok","progress":"7/12","ends_at":"2026-11-04T18:30+08:00","link":"https://x"}`))
	eq(t, ch["body"], any("7 ok"))
	eq(t, ch["done_n"], any(7.0))
	eq(t, ch["total_n"], any(12.0))
	eq(t, ch["ends_at"], any(int64(1793788200)))
	eq(t, ch["link"], any("https://x"))
	eq(t, pollResult([]byte(`{"ends_at": 1793788200}`))["ends_at"], any(int64(1793788200)))
	_, hasBody := pollResult([]byte(`{"progress":"1/2"}`))["body"]
	eq(t, hasBody, false)
	// Not JSON after all: the whole text is the body.
	eq(t, pollResult([]byte("{not json"))["body"], any("{not json"))
	_, err := tryPollResult([]byte(`{"progress":"seven"}`))
	contains_(t, err.Error(), "must look like 7/12")
}

func pollSpecFor(h *harness, key, script string) pollSpec {
	return pollSpec{Sprint: "s1", Key: key, DB: h.db, Cmd: []string{"sh", "-c", script}, Dir: h.dir}
}

func TestPollOnceRecordsEachOutcome(t *testing.T) {
	h := liveSprint(t)
	h.ok("live", "set", "b", "--title", "Bench", "--stale-after", "1m")
	eq(t, pollOnce(pollSpecFor(h, "b", `echo '{"body":"run 3","progress":"3/12"}'`), time.Minute), false)
	eq(t, h.live("SELECT body, done_n, state, error FROM live_items"), "(run 3, 3, live, <nil>)")

	h.clock(1100)
	eq(t, pollOnce(pollSpecFor(h, "b", "echo 'gh: rate limited' >&2; exit 2"), time.Minute), false)
	eq(t, h.live("SELECT body, error, updated_at, seen_at FROM live_items"), "(run 3, gh: rate limited, 1000, 1100)")
	eq(t, pollOnce(pollSpecFor(h, "b", "exit 3"), time.Minute), false)
	eq(t, h.live("SELECT error FROM live_items"), "(exit 3)")
	eq(t, pollOnce(pollSpecFor(h, "b", "sleep 5"), 200*time.Millisecond), false)
	eq(t, h.live("SELECT error FROM live_items"), "(timed out after 200ms)")

	h.clock(1200)
	eq(t, pollOnce(pollSpecFor(h, "b", "echo 'All 12 ok.'; exit 100"), time.Minute), true)
	eq(t, h.live("SELECT body, state, done_at, error FROM live_items"), "(All 12 ok., done, 1200, <nil>)")
	// A done or removed item stops the poller before it runs the command.
	eq(t, pollOnce(pollSpecFor(h, "b", "echo again"), time.Minute), true)
	h.ok("live", "rm", "b")
	eq(t, pollOnce(pollSpecFor(h, "b", "echo again"), time.Minute), true)
}

func TestPollExit100WithNoOutputKeepsTheBody(t *testing.T) {
	h := liveSprint(t)
	h.ok("live", "set", "b", "--title", "Bench", "--file", h.file("b.md", "last body"))
	eq(t, pollOnce(pollSpecFor(h, "b", "exit 100"), time.Minute), true)
	eq(t, h.live("SELECT body, state FROM live_items"), "(last body, done)")
}

// waitFor polls cond for up to 10 s.
func waitFor(t *testing.T, what string, cond func() bool) {
	t.Helper()
	for i := 0; i < 100; i++ {
		if cond() {
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("timed out waiting: %s", what)
}

func detachedSprint(t *testing.T) *harness {
	h := liveSprint(t)
	t.Setenv("SPRINT_NOW", "")
	t.Setenv("SPRINT_TEST_AS_CLI", "1")
	t.Cleanup(func() {
		files, _ := filepath.Glob(filepath.Join(filepath.Dir(h.db), "pollers", "*.pid"))
		for _, f := range files {
			data, _ := os.ReadFile(f)
			if pid, err := strconv.Atoi(strings.TrimSpace(string(data))); err == nil {
				syscall.Kill(pid, syscall.SIGKILL)
			}
		}
	})
	return h
}

func pidOf(t *testing.T, h *harness, key string) int {
	data, err := os.ReadFile(filepath.Join(filepath.Dir(h.db), "pollers", "s1."+key+".pid"))
	if err != nil {
		return 0
	}
	pid, _ := strconv.Atoi(strings.TrimSpace(string(data)))
	return pid
}

func TestPollRunsDetachedUntilStopped(t *testing.T) {
	h := detachedSprint(t)
	out := h.ok("poll", "tick", "--every", "5s", "--title", "Ticker", "--subgoal", "bench", "--",
		"sh", "-c", "echo tick $$")
	contains_(t, out, "poll tick: started, PID")
	waitFor(t, "first tick", func() bool { return strings.Contains(h.live("SELECT body FROM live_items"), "tick") })
	eq(t, h.live("SELECT title, subgoal, stale_after, state FROM live_items"), "(Ticker, bench, 15, live)")
	pid := pidOf(t, h, "tick")
	// Its own session, so the shell that started it can end.
	sid, _ := syscall.Getsid(pid)
	eq(t, sid, pid)
	contains_(t, h.ok("poll", "ls"), "tick\ts1\tPID "+strconv.Itoa(pid)+"\tevery 5s\tupdated ")

	// Starting it again replaces the running poller.
	contains_(t, h.ok("poll", "tick", "--every", "5s", "--", "sh", "-c", "echo tock"), "restarted")
	waitFor(t, "old poller gone", func() bool { return syscall.Kill(pid, 0) != nil })
	waitFor(t, "second command", func() bool { return h.live("SELECT body FROM live_items") == "(tock)" })

	newPID := pidOf(t, h, "tick")
	contains_(t, h.ok("poll", "stop", "tick"), "stopped")
	waitFor(t, "poller gone", func() bool { return syscall.Kill(newPID, 0) != nil })
	eq(t, pidOf(t, h, "tick"), 0)
	eq(t, h.ok("poll", "ls"), "no pollers\n")
	contains_(t, h.fails("poll", "stop", "tick"), `no running poller "tick"`)
	// The card stays.
	eq(t, h.live("SELECT state FROM live_items"), "(live)")
}

func TestPollEndsItselfOnExit100(t *testing.T) {
	h := detachedSprint(t)
	h.ok("poll", "job", "--every", "5s", "--title", "Job", "--", "sh", "-c", "echo 'finished'; exit 100")
	waitFor(t, "item done", func() bool { return h.live("SELECT state FROM live_items") == "(done)" })
	eq(t, h.live("SELECT body FROM live_items"), "(finished)")
	waitFor(t, "PID file removed", func() bool { return pidOf(t, h, "job") == 0 })
}

func TestKilledPollerShowsAsStale(t *testing.T) {
	h := detachedSprint(t)
	h.ok("poll", "w", "--every", "5s", "--stale-after", "1s", "--title", "Watch", "--", "sh", "-c", "echo up")
	waitFor(t, "first run", func() bool { return h.live("SELECT body FROM live_items") == "(up)" })
	pid := pidOf(t, h, "w")
	syscall.Kill(pid, syscall.SIGKILL)
	waitFor(t, "stale", func() bool { return strings.Contains(h.ok("live", "ls"), "w\tstale\t") })
	contains_(t, h.ok("poll", "ls"), "w\ts1\tnot running")
}

func TestPollChecksItsInput(t *testing.T) {
	h := liveSprint(t)
	contains_(t, h.fails("poll", "x", "--title", "X", "--", "true"), "--every is required")
	contains_(t, h.fails("poll", "x", "--every", "1s", "--title", "X", "--", "true"), "5s or more")
	contains_(t, h.fails("poll", "x", "--every", "1m", "--", "true"), "needs --title")
	contains_(t, h.fails("poll", "x", "--every", "1m", "--title", "X"), "missing cmd")
}

func TestProbeTailEndsWhenALineMatches(t *testing.T) {
	h := newHarness(t)
	log := h.file("bench.log", "start\nrun 1 ok\nrun 2 ok\n")
	out := h.ok("probe", "tail", log, "--lines", "2", "--until", "^DONE")
	eq(t, out, "```\nrun 1 ok\nrun 2 ok\n```\n")
	h.file("bench.log", "start\nDONE 12 runs\n")
	code, _, _ := h.run("probe", "tail", log, "--until", "^DONE")
	eq(t, code, exitDone)
}
