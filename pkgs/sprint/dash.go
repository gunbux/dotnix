package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// Grafana (modules/home/sprint.nix) reads its dashboard from a writable
// folder and rescans it every 10 s. Each Home Manager switch copies the
// built dashboard there and to builtDashboard. `sprint dash dev` writes a
// checkout's dashboard over it, so a panel edit needs no switch.

const dashboardSource = "modules/home/sprint/dashboard.nix"

func xdgDir(env, fallback string) string {
	if v := os.Getenv(env); v != "" {
		return v
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, fallback)
}

func dashboardsDir() string {
	if v := os.Getenv("SPRINT_DASHBOARDS"); v != "" {
		return v
	}
	return filepath.Join(xdgDir("XDG_STATE_HOME", ".local/state"), "sprint", "dashboards")
}

func builtDashboard() string {
	if v := os.Getenv("SPRINT_BUILT_DASHBOARD"); v != "" {
		return v
	}
	return filepath.Join(xdgDir("XDG_DATA_HOME", ".local/share"), "sprint", "sprint.json")
}

// writeAtomic replaces path in one rename. The temp name doesn't end in
// .json, so Grafana never reads a half-written file.
func writeAtomic(path string, data []byte) {
	check(os.MkdirAll(filepath.Dir(path), 0o755))
	tmp := filepath.Join(filepath.Dir(path), fmt.Sprintf(".%s.tmp-%d", filepath.Base(path), os.Getpid()))
	check(os.WriteFile(tmp, data, 0o644))
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		panic(err)
	}
}

func gitOut(dir string, args ...string) (string, error) {
	out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).Output()
	return strings.TrimSpace(string(out)), err
}

// devLabel names the checkout's state: branch@sha, with + for uncommitted changes.
func devLabel(checkout string) string {
	branch, err := gitOut(checkout, "rev-parse", "--abbrev-ref", "HEAD")
	if err != nil {
		return filepath.Base(checkout)
	}
	sha, _ := gitOut(checkout, "rev-parse", "--short", "HEAD")
	label := branch + "@" + sha
	if dirty, _ := gitOut(checkout, "status", "--porcelain", "--", "modules/home/sprint"); dirty != "" {
		label += "+"
	}
	return label
}

// markDev sets the dashboard's hidden `dev` variable, which the header
// shows, and adds the label to the title.
func markDev(dashboard []byte, label string) ([]byte, error) {
	var d map[string]any
	if err := json.Unmarshal(dashboard, &d); err != nil {
		return nil, fmt.Errorf("nix eval did not print a dashboard: %w", err)
	}
	d["title"] = fmt.Sprintf("%v (dev: %s)", d["title"], label)
	templating, _ := d["templating"].(map[string]any)
	vars, _ := templating["list"].([]any)
	found := false
	for _, v := range vars {
		if m, ok := v.(map[string]any); ok && m["name"] == "dev" {
			m["query"] = label
			m["current"] = map[string]any{"text": label, "value": label}
			m["options"] = []any{map[string]any{"text": label, "value": label, "selected": true}}
			found = true
		}
	}
	if !found {
		return nil, errors.New("the dashboard has no `dev` variable")
	}
	return json.MarshalIndent(d, "", " ")
}

func evalDashboard(checkout string) ([]byte, error) {
	cmd := exec.Command("nix", "eval", "--json", "--file", filepath.Join(checkout, dashboardSource))
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("nix eval failed: %v\n%s", err, strings.TrimSpace(stderr.String()))
	}
	return markDev(out, devLabel(checkout))
}

func findCheckout(c *call) string {
	dir := c.flag("checkout")
	if dir == "" {
		top, err := gitOut(".", "rev-parse", "--show-toplevel")
		if err != nil {
			fail("not in a git checkout; pass --checkout <dotnix checkout>")
		}
		dir = top
	}
	abs, err := filepath.Abs(dir)
	check(err)
	if _, err := os.Stat(filepath.Join(abs, dashboardSource)); err != nil {
		fail("%s has no %s", abs, dashboardSource)
	}
	return abs
}

// sourceStamp changes when any file of the dashboard's source changes.
func sourceStamp(checkout string) string {
	var b strings.Builder
	filepath.WalkDir(filepath.Join(checkout, filepath.Dir(dashboardSource)), func(p string, e fs.DirEntry, err error) error {
		if err == nil && !e.IsDir() {
			if info, err := e.Info(); err == nil {
				fmt.Fprintf(&b, "%s %d %d\n", p, info.Size(), info.ModTime().UnixNano())
			}
		}
		return nil
	})
	return b.String()
}

func cmdDashDev(c *call) {
	checkout := findCheckout(c)
	target := filepath.Join(dashboardsDir(), "sprint.json")
	write := func() error {
		start := time.Now()
		data, err := evalDashboard(checkout)
		if err != nil {
			return err
		}
		writeAtomic(target, data)
		c.printf("dev: %s -> %s (%.1f s). Grafana reloads it within 10 s.\n",
			devLabel(checkout), target, time.Since(start).Seconds())
		return nil
	}
	if !c.has("watch") {
		if err := write(); err != nil {
			fail("%v", err)
		}
		return
	}
	c.printf("watching %s; Ctrl-C stops. `sprint dash reset` restores the built dashboard.\n",
		filepath.Join(checkout, filepath.Dir(dashboardSource)))
	last := ""
	for {
		if stamp := sourceStamp(checkout); stamp != last {
			last = stamp
			if err := write(); err != nil {
				fmt.Fprintf(c.errOut, "sprint: %v\n", err)
			}
		}
		time.Sleep(500 * time.Millisecond)
	}
}

func cmdDashReset(c *call) {
	built := builtDashboard()
	data, err := os.ReadFile(built)
	if err != nil {
		fail("no built dashboard at %s; switch once to create it", built)
	}
	target := filepath.Join(dashboardsDir(), "sprint.json")
	writeAtomic(target, data)
	c.printf("reset: %s -> %s\n", built, target)
}
