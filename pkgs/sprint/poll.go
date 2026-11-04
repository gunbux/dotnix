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
// started it. Each poller has three files in the pollers folder, under
// <sprint>/<key>: .json (what to run), .pid, and .log (its own errors).
//
// The command prints Markdown (the item's body) or a JSON object with any of
// body, progress ("7/12"), ends_at (as in `live set --ends-at`), title and
// link. A field with the wrong type is skipped and shown as the card's
// error. Exit 100 marks the item done and stops the poller. Another non-zero
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
	// Slugs and keys have no "/", so one folder per sprint keeps every
	// poller's files apart.
	return filepath.Join(pollersDir(dbPath), sprint, key+ext)
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
	cmdline := string(out)
	if err != nil || !strings.Contains(cmdline, "--sprint "+sprint+" poll run "+key) {
		return 0, false
	}
	return pid, true
}

// stopPoller ends a poller and waits until it is gone. SIGTERM cancels its
// running command; a poller still there after 10 s gets SIGKILL.
func stopPoller(dbPath, sprint, key string) bool {
	pid, ok := pollerPID(dbPath, sprint, key)
	if ok {
		syscall.Kill(pid, syscall.SIGTERM)
		for i := 0; i < 100 && syscall.Kill(pid, 0) == nil; i++ {
			time.Sleep(100 * time.Millisecond)
		}
		if syscall.Kill(pid, 0) == nil {
			syscall.Kill(pid, syscall.SIGKILL)
			for i := 0; i < 20 && syscall.Kill(pid, 0) == nil; i++ {
				time.Sleep(100 * time.Millisecond)
			}
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
	// The CLI exits at once and init adopts the poller. A longer-lived
	// caller (the tests) must still reap it.
	exited := make(chan struct{})
	go func() { child.Wait(); close(exited) }()
	// The poller writes its own PID file first, so its cleanup always finds
	// it. Wait for that, or for a poller that already finished.
	for i := 0; i < 50; i++ {
		if pid, ok := pollerPID(db, sp.Slug, key); ok && pid == child.Process.Pid {
			break
		}
		select {
		case <-exited:
			c.printf("poll %s: the command finished on its first run\n", key)
			return
		case <-time.After(100 * time.Millisecond):
		}
	}
	verb := "started"
	if replaced {
		verb = "restarted"
	}
	c.printf("poll %s: %s, PID %d, every %s. `sprint poll stop %s` stops it.\n", key, verb, child.Process.Pid, every, key)
}

// pollResult turns one run of the command into a change to the item. A
// JSON object sets the fields it names. A field with the wrong type is
// skipped and reported in err, and the other fields still apply, so the card
// never shows the raw JSON.
func pollResult(stdout []byte) (ch liveChange, err error) {
	out := strings.TrimSpace(string(stdout))
	ch = liveChange{}
	var obj map[string]json.RawMessage
	if !strings.HasPrefix(out, "{") || json.Unmarshal([]byte(out), &obj) != nil {
		ch["body"] = out
		return ch, nil
	}
	var bad []string
	// field decodes one value and runs set on it; a type error or a
	// userError from set (such as parseProgress) marks the field bad.
	field := func(name, want string, dst any, set func()) {
		raw, ok := obj[name]
		if !ok || string(raw) == "null" {
			return
		}
		defer func() {
			if r := recover(); r != nil {
				if _, ok := r.(userError); !ok {
					panic(r)
				}
				bad = append(bad, fmt.Sprintf("%s must be %s, not %s", name, want, raw))
			}
		}()
		if json.Unmarshal(raw, dst) != nil {
			fail("")
		}
		set()
	}
	var body, progress, title, link string
	var endsAt any
	field("body", "a string", &body, func() { ch["body"] = strings.TrimSpace(body) })
	field("progress", `a string like "7/12"`, &progress, func() {
		p := parseProgress(progress).([2]float64)
		ch["done_n"], ch["total_n"] = p[0], p[1]
	})
	field("ends_at", "unix seconds or an RFC 3339 time", &endsAt, func() {
		switch t := endsAt.(type) {
		case float64:
			ch["ends_at"] = int64(t)
		case string:
			ch["ends_at"] = parseTime(t)
		default:
			fail("")
		}
	})
	field("title", "a string", &title, func() {
		if title != "" {
			ch["title"] = title
		}
	})
	field("link", "a string", &link, func() { ch["link"] = null(link) })
	if len(bad) > 0 {
		err = fmt.Errorf("bad output: %s", strings.Join(bad, "; "))
	}
	return ch, err
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

// pollOnce runs the command once and records the result. stopped ends the
// run early (poll stop), and its result is then dropped. Only a live item
// takes a result, so `live done` or `live rm` during a run wins. It reports
// whether the poller should stop.
func pollOnce(stopped context.Context, spec pollSpec, timeout time.Duration) (stop bool) {
	live, closeLive := openLive(livePath(spec.DB))
	defer closeLive()
	if cur, ok := live.liveItem(spec.Sprint, spec.Key); !ok || cur.State == "done" {
		fmt.Fprintf(os.Stderr, "%s: item %s is gone or done; stopping\n", time.Now().Format(time.RFC3339), spec.Key)
		return true
	}
	ctx, cancel := context.WithTimeout(stopped, timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, spec.Cmd[0], spec.Cmd[1:]...)
	cmd.Dir = spec.Dir
	// A timeout or a stop kills the whole process group, so a shell's
	// children can't keep the output pipes open.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	cmd.WaitDelay = 5 * time.Second
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	if stopped.Err() != nil {
		return true
	}
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
	var ch liveChange
	switch {
	case code != 0 && code != exitDone:
		msg := lastLine(stderr.String())
		if msg == "" {
			msg = fmt.Sprintf("exit %d", code)
			if code == -1 {
				msg = err.Error()
			}
		}
		ch = liveChange{"error": msg}
	default:
		// A bad field keeps its old value; the card shows why.
		var perr error
		ch, perr = pollResult(stdout.Bytes())
		ch["error"], ch["updated_at"] = nil, at
		if perr != nil {
			ch["error"] = perr.Error()
		}
		if ch["body"] == "" && code == exitDone {
			delete(ch, "body")
		}
	}
	ch["seen_at"] = at
	if code == exitDone {
		ch["state"], ch["done_at"] = "done", at
	}
	updated := liveUpdateWhere(live, spec.Sprint, spec.Key, ch, "state = 'live'")
	return code == exitDone || updated == 0
}

func cmdPollRun(c *call) {
	sp, key := c.flag("sprint"), c.pos["key"]
	// First, so cleanup below always finds this poller's own PID file.
	writeAtomic(pollFile(c.flag("db"), sp, key, ".pid"), []byte(strconv.Itoa(os.Getpid())+"\n"))
	data, err := os.ReadFile(pollFile(c.flag("db"), sp, key, ".json"))
	check(err)
	var spec pollSpec
	check(json.Unmarshal(data, &spec))
	every, timeout := parseEvery(spec.Every), parseEvery(spec.Timeout)
	stopped, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP)
	defer cancel()
	defer func() {
		// Only this poller's files: a restart may have written new ones.
		if pid, _ := os.ReadFile(pollFile(spec.DB, sp, key, ".pid")); strings.TrimSpace(string(pid)) == strconv.Itoa(os.Getpid()) {
			os.Remove(pollFile(spec.DB, sp, key, ".pid"))
			os.Remove(pollFile(spec.DB, sp, key, ".json"))
		}
	}()
	for {
		if pollOnce(stopped, spec, timeout) {
			return
		}
		select {
		case <-stopped.Done():
			return
		case <-time.After(every):
		}
	}
}

func cmdPollLs(c *call) {
	dir := pollersDir(c.dbPath)
	files, _ := filepath.Glob(filepath.Join(dir, "*", "*.json"))
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
