package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// A poller runs a command every --every and writes what it prints to a live
// item. It runs detached, so it outlives the shell or agent turn that
// started it. Each poller has three files in the pollers folder, named
// <sprint>.<key>: .json (what to run), .pid, and .log (its own errors).
//
// The command prints Markdown (the item's body) or a JSON object with any of
// body, progress ("7/12"), ends_at (as in `live set --ends-at`), title and
// link. Exit 100 marks the item done and stops the poller. Another non-zero
// exit keeps the last body and shows the error on the card.

const exitDone = 100

type pollSpec struct {
	Sprint  string   `json:"sprint"`
	Key     string   `json:"key"`
	DB      string   `json:"db"`
	Every   string   `json:"every"`
	Timeout string   `json:"timeout"`
	Cmd     []string `json:"cmd"`
	Dir     string   `json:"dir"`
	Started int64    `json:"started"`
}

func pollersDir(dbPath string) string {
	if v := os.Getenv("SPRINT_POLLERS"); v != "" {
		return v
	}
	return filepath.Join(filepath.Dir(dbPath), "pollers")
}

func pollFile(dbPath, sprint, key, ext string) string {
	return filepath.Join(pollersDir(dbPath), sprint+"."+key+ext)
}

func parseEvery(v string) time.Duration {
	d, err := time.ParseDuration(v)
	if err != nil || d < 5*time.Second {
		fail("bad --every %q: use 5s or more, such as 60s or 5m", v)
	}
	return d
}

// pollerPID is the poller's PID if it still runs. The process must be this
// poller, so a reused PID never counts.
func pollerPID(dbPath, sprint, key string) (int, bool) {
	data, err := os.ReadFile(pollFile(dbPath, sprint, key, ".pid"))
	if err != nil {
		return 0, false
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil || syscall.Kill(pid, 0) != nil {
		return 0, false
	}
	out, err := exec.Command("ps", "-p", strconv.Itoa(pid), "-o", "command=").Output()
	if err != nil || !strings.Contains(string(out), "poll run "+key) {
		return 0, false
	}
	return pid, true
}

func stopPoller(dbPath, sprint, key string) bool {
	pid, ok := pollerPID(dbPath, sprint, key)
	if ok {
		syscall.Kill(pid, syscall.SIGTERM)
		for i := 0; i < 50 && syscall.Kill(pid, 0) == nil; i++ {
			time.Sleep(100 * time.Millisecond)
		}
	}
	for _, ext := range []string{".pid", ".json"} {
		os.Remove(pollFile(dbPath, sprint, key, ext))
	}
	return ok
}

func cmdPoll(c *call) {
	sp := c.store.resolve(c.flag("sprint"))
	key := c.pos["key"]
	checkKey("live item", key)
	every := parseEvery(c.flag("every"))
	timeout := min(max(every, 30*time.Second), 10*time.Minute)
	if c.has("timeout") {
		timeout = parseEvery(c.flag("timeout"))
	}
	ch := liveChange{"stale_after": int64(3 * every.Seconds())}
	if c.has("title") {
		ch["title"] = c.flag("title")
	}
	if c.has("subgoal") {
		ch["subgoal"] = null(c.store.pickSubgoal(sp.ID, c.flag("subgoal"), true, false))
	}
	clearable(c, "stale-after", parseSeconds, ch, "stale_after")
	clearable(c, "link", parseText, ch, "link")
	live, closeLive := openLive(livePath(c.dbPath))
	liveSet(live, sp.Slug, key, ch)
	closeLive()

	db, err := filepath.Abs(c.dbPath)
	check(err)
	replaced := stopPoller(db, sp.Slug, key)
	wd, _ := os.Getwd()
	spec := pollSpec{Sprint: sp.Slug, Key: key, DB: db, Every: every.String(), Timeout: timeout.String(),
		Cmd: c.many, Dir: wd, Started: now()}
	data, err := json.MarshalIndent(spec, "", "  ")
	check(err)
	check(os.MkdirAll(pollersDir(db), 0o755))
	writeAtomic(pollFile(db, sp.Slug, key, ".json"), data)

	self, err := os.Executable()
	check(err)
	logf, err := os.OpenFile(pollFile(db, sp.Slug, key, ".log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	check(err)
	defer logf.Close()
	child := exec.Command(self, "--db", db, "--sprint", sp.Slug, "poll", "run", key)
	child.Stdout, child.Stderr = logf, logf
	child.Dir = wd
	// Its own session: closing the starting shell or agent turn doesn't stop it.
	child.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	check(child.Start())
	writeAtomic(pollFile(db, sp.Slug, key, ".pid"), []byte(strconv.Itoa(child.Process.Pid)+"\n"))
	// The CLI exits at once and init adopts the poller. A longer-lived
	// caller (the tests) must still reap it.
	go child.Wait()
	verb := "started"
	if replaced {
		verb = "restarted"
	}
	c.printf("poll %s: %s, PID %d, every %s. `sprint poll stop %s` stops it.\n", key, verb, child.Process.Pid, every, key)
}

// pollResult turns one run of the command into a change to the item.
func pollResult(stdout []byte) liveChange {
	out := strings.TrimSpace(string(stdout))
	ch := liveChange{}
	if strings.HasPrefix(out, "{") {
		var j struct {
			Body     *string         `json:"body"`
			Progress *string         `json:"progress"`
			EndsAt   json.RawMessage `json:"ends_at"`
			Title    *string         `json:"title"`
			Link     *string         `json:"link"`
		}
		if json.Unmarshal([]byte(out), &j) == nil {
			if j.Body != nil {
				ch["body"] = strings.TrimSpace(*j.Body)
			}
			if j.Progress != nil {
				p := parseProgress(*j.Progress).([2]float64)
				ch["done_n"], ch["total_n"] = p[0], p[1]
			}
			if len(j.EndsAt) > 0 && string(j.EndsAt) != "null" {
				var v any
				json.Unmarshal(j.EndsAt, &v)
				switch t := v.(type) {
				case float64:
					ch["ends_at"] = int64(t)
				case string:
					ch["ends_at"] = parseTime(t)
				}
			}
			if j.Title != nil && *j.Title != "" {
				ch["title"] = *j.Title
			}
			if j.Link != nil {
				ch["link"] = null(*j.Link)
			}
			return ch
		}
	}
	ch["body"] = out
	return ch
}

// tryPollResult is pollResult with bad output reported as an error.
func tryPollResult(stdout []byte) (ch liveChange, err error) {
	defer func() {
		if r := recover(); r != nil {
			if e, ok := r.(userError); ok {
				err = fmt.Errorf("bad output: %s", e.msg)
				return
			}
			panic(r)
		}
	}()
	return pollResult(stdout), nil
}

// lastLine keeps an error message short enough for a card.
func lastLine(s string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	l := strings.TrimSpace(lines[len(lines)-1])
	if len(l) > 300 {
		l = l[:300] + "…"
	}
	return l
}

// pollOnce runs the command once and records the result. It reports
// whether the poller should stop.
func pollOnce(spec pollSpec, timeout time.Duration) (stop bool) {
	live, closeLive := openLive(livePath(spec.DB))
	defer closeLive()
	cur, ok := live.liveItem(spec.Sprint, spec.Key)
	if !ok || cur.State == "done" {
		fmt.Fprintf(os.Stderr, "%s: item %s is gone or done; stopping\n", time.Now().Format(time.RFC3339), spec.Key)
		return true
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, spec.Cmd[0], spec.Cmd[1:]...)
	cmd.Dir = spec.Dir
	// A timeout kills the whole process group, so a shell's children can't
	// keep the output pipes open.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	cmd.WaitDelay = 5 * time.Second
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	code := 0
	var ee *exec.ExitError
	switch {
	case ctx.Err() != nil:
		err, code = fmt.Errorf("timed out after %s", timeout), -1
	case errors.As(err, &ee):
		code = ee.ExitCode()
	case err != nil:
		code = -1
	}
	at := now()
	if code != 0 && code != exitDone {
		msg := lastLine(stderr.String())
		if msg == "" {
			msg = fmt.Sprintf("exit %d", code)
			if code == -1 {
				msg = err.Error()
			}
		}
		liveUpdate(live, spec.Sprint, spec.Key, liveChange{"error": msg, "seen_at": at})
		return false
	}
	ch, perr := tryPollResult(stdout.Bytes())
	if perr != nil {
		liveUpdate(live, spec.Sprint, spec.Key, liveChange{"error": perr.Error(), "seen_at": at})
		return code == exitDone
	}
	if code == exitDone && ch["body"] == "" {
		delete(ch, "body")
	}
	liveSet(live, spec.Sprint, spec.Key, ch)
	if code == exitDone {
		liveUpdate(live, spec.Sprint, spec.Key, liveChange{"state": "done", "done_at": at})
		return true
	}
	return false
}

func cmdPollRun(c *call) {
	sp := c.flag("sprint")
	data, err := os.ReadFile(pollFile(c.flag("db"), sp, c.pos["key"], ".json"))
	check(err)
	var spec pollSpec
	check(json.Unmarshal(data, &spec))
	every, timeout := parseEvery(spec.Every), parseEvery(spec.Timeout)
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP)
	defer func() {
		// Only this poller's PID file: a restart may have written a new one.
		if pid, _ := os.ReadFile(pollFile(spec.DB, sp, spec.Key, ".pid")); strings.TrimSpace(string(pid)) == strconv.Itoa(os.Getpid()) {
			os.Remove(pollFile(spec.DB, sp, spec.Key, ".pid"))
			os.Remove(pollFile(spec.DB, sp, spec.Key, ".json"))
		}
	}()
	for {
		if pollOnce(spec, timeout) {
			return
		}
		select {
		case <-sigs:
			return
		case <-time.After(every):
		}
	}
}

func cmdPollLs(c *call) {
	dir := pollersDir(c.dbPath)
	files, _ := filepath.Glob(filepath.Join(dir, "*.json"))
	sort.Strings(files)
	live, closeLive := openLive(livePath(c.dbPath))
	defer closeLive()
	if len(files) == 0 {
		c.printf("no pollers\n")
	}
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		var spec pollSpec
		if json.Unmarshal(data, &spec) != nil {
			continue
		}
		pid, ok := pollerPID(c.dbPath, spec.Sprint, spec.Key)
		state := fmt.Sprintf("PID %d", pid)
		if !ok {
			state = "not running"
		}
		last, lastErr := "no update yet", ""
		if l, found := live.liveItem(spec.Sprint, spec.Key); found {
			last, lastErr = "updated "+ago(l.UpdatedAt), l.Error
		}
		c.printf("%s\t%s\t%s\tevery %s\t%s\t%s\n", spec.Key, spec.Sprint, state, spec.Every, last,
			strings.Join(spec.Cmd, " "))
		if lastErr != "" {
			c.printf("\terror: %s\n", lastErr)
		}
	}
}

func cmdPollStop(c *call) {
	sp := c.store.resolve(c.flag("sprint"))
	if !stopPoller(c.dbPath, sp.Slug, c.pos["key"]) {
		fail("no running poller %q in sprint %s", c.pos["key"], sp.Slug)
	}
	c.printf("poll %s: stopped. The card stays; `sprint live done %s` or `sprint live rm %s` ends it.\n",
		c.pos["key"], c.pos["key"], c.pos["key"])
}
