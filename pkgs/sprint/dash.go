package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
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
		// The label is part of the state: a commit changes it but no file.
		if stamp := sourceStamp(checkout) + devLabel(checkout); stamp != last {
			last = stamp
			if err := write(); err != nil {
				fmt.Fprintf(c.errOut, "sprint: %v\n", err)
			}
		}
		time.Sleep(time.Second)
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

// The page panels of modules/home/sprint/dashboard.nix. Each one runs
// page/fit.js, which writes data-sp-* attributes that dashCheck reads.
var pagePanels = []string{"header", "progress", "live", "donow", "stages", "timeline", "prs", "context", "left", "bench"}

// Thresholds for `dash check`, in CSS pixels.
const (
	maxWide = 2   // content wider than its box: a table out of a card
	maxGap  = 160 // empty space at the bottom of a panel: about 4 grid rows
)

func findChrome(c *call) string {
	if v := c.flag("chrome"); v != "" {
		return v
	}
	if v := os.Getenv("SPRINT_CHROME"); v != "" {
		return v
	}
	for _, name := range []string{"chromium", "google-chrome-stable", "google-chrome", "chrome"} {
		if p, err := exec.LookPath(name); err == nil {
			return p
		}
	}
	mac := "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
	if _, err := os.Stat(mac); err == nil {
		return mac
	}
	fail("no Chrome or Chromium found; pass --chrome <path> or set SPRINT_CHROME")
	return ""
}

var spAttrRE = regexp.MustCompile(`data-sp-(panel|fit|hidden|gap|wide|raw|wide-at|cut|open)="([^"]*)"`)

type panelFit struct {
	fit, wideAt                       string
	hidden, gap, wide, raw, cut, open int
}

// renderFits loads one view in headless Chrome and returns what fit.js
// wrote on each page panel. The window is tall, so Grafana renders every
// panel; the panels' heights don't depend on it.
func renderFits(chrome, url string, width int) (map[string]panelFit, error) {
	profile, err := os.MkdirTemp("", "sprint-dash-check-")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(profile)
	cmd := exec.Command(chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars",
		"--user-data-dir="+profile, fmt.Sprintf("--window-size=%d,5000", width),
		"--virtual-time-budget=20000", "--dump-dom", url)
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("chrome: %v", err)
	}
	return parseFits(string(out)), nil
}

// parseFits reads the data-sp-* attributes from a dumped DOM, by panel.
func parseFits(dom string) map[string]panelFit {
	fits := map[string]panelFit{}
	// fit.js writes the attributes in one order, so each panel's run of
	// matches starts at data-sp-panel.
	var cur string
	for _, m := range spAttrRE.FindAllStringSubmatch(dom, -1) {
		if m[1] == "panel" {
			cur = m[2]
			fits[cur] = panelFit{}
			continue
		}
		f := fits[cur]
		n, _ := strconv.Atoi(m[2])
		switch m[1] {
		case "fit":
			f.fit = m[2]
		case "hidden":
			f.hidden = n
		case "gap":
			f.gap = n
		case "wide":
			f.wide = n
		case "raw":
			f.raw = n
		case "cut":
			f.cut = n
		case "open":
			f.open = n
		case "wide-at":
			f.wideAt = html.UnescapeString(m[2])
		}
		fits[cur] = f
	}
	return fits
}

// cmdDashCheck renders every view of each open sprint and reports layout
// problems: a section that didn't render, content out of its box, content
// cut where the panel doesn't scroll, and raw JSON on a Live card. It notes
// folds, a section cut because one item is taller than its panel, and a
// large empty gap. --open opens every list first (Merged, Waiting, context
// sections), as a reader who clicks them would. It exits 1 on a problem, and 0 when there are only
// notes.
func cmdDashCheck(c *call) {
	chrome := findChrome(c)
	width := 1512
	if v := c.flag("width"); v != "" {
		w, err := strconv.Atoi(v)
		if err != nil || w < 320 {
			fail("--width must be a number of pixels, at least 320")
		}
		width = w
	}
	type view struct{ sprint, subgoal, url string }
	var views []view
	// The log is open only while the views are listed: a render takes
	// seconds, and pollers write meanwhile.
	db := c.flag("db")
	if db == "" {
		db = defaultDB()
	}
	s, closeDB := openWrite(db)
	for _, sp := range s.openSprints() {
		if slug := c.flag("sprint"); slug != "" && slug != sp.Slug {
			continue
		}
		views = append(views, view{sp.Slug, "", dashboardURL(sp.Slug, "", sp.StartedAt)})
		s.each("SELECT key FROM subgoal_state WHERE sprint_id = ? AND status != 'dropped' ORDER BY position",
			[]any{sp.ID}, func(r *sql.Rows) {
				var key string
				check(r.Scan(&key))
				views = append(views, view{sp.Slug, key, dashboardURL(sp.Slug, key, sp.StartedAt)})
			})
	}
	closeDB()
	if len(views) == 0 {
		fail("no open sprint to check")
	}
	problems := 0
	for _, v := range views {
		name := v.sprint
		if v.subgoal != "" {
			name += " / " + v.subgoal
		}
		url := v.url + "&kiosk"
		if c.has("open") {
			url += "&sp-open=1"
		}
		fits, err := renderFits(chrome, url, width)
		if err != nil {
			fail("%s: %v", name, err)
		}
		var lines []string
		bad := func(format string, a ...any) {
			problems++
			lines = append(lines, "  problem: "+fmt.Sprintf(format, a...))
		}
		note := func(format string, a ...any) { lines = append(lines, "  note:    "+fmt.Sprintf(format, a...)) }
		for _, p := range pagePanels {
			f, ok := fits[p]
			switch {
			case !ok:
				bad("%s: did not render (a script error, or fit.js didn't run)", p)
				continue
			}
			if f.cut > 0 {
				bad("%s: content is cut by %d px and the panel doesn't scroll", p, f.cut)
			}
			if f.wide > maxWide {
				bad("%s: content is %d px wider than its box (%s)", p, f.wide, f.wideAt)
			}
			if f.raw > 0 {
				bad("%s: %d card(s) show raw JSON: the poller's output did not parse", p, f.raw)
			}
			switch {
			case f.fit == "all":
				note("%s: shown in full (%d list(s) opened); the panel scrolls", p, f.open)
			case f.fit == "clipped":
				note("%s: one item is taller than the panel, so it is cut (Show all opens it)", p)
			case f.hidden > 0:
				note("%s: %d item(s) folded to fit", p, f.hidden)
			}
			if f.gap > maxGap && f.fit != "all" {
				note("%s: %d px empty at the bottom", p, f.gap)
			}
		}
		status := "ok"
		if len(lines) > 0 {
			status = ""
		}
		c.printf("%s (%d px wide) %s\n", name, width, status)
		for _, l := range lines {
			c.printf("%s\n", l)
		}
	}
	if problems > 0 {
		fail("%d layout problem(s)", problems)
	}
}
