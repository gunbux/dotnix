package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// dashSetup makes a git checkout with a dashboard source, a fake `nix` that
// prints the dashboard JSON stored beside the source, and Grafana's folder.
func dashSetup(t *testing.T) (h *harness, checkout, target string) {
	h = newHarness(t)
	checkout = filepath.Join(h.dir, "dotnix")
	src := filepath.Join(checkout, dashboardSource)
	if err := os.MkdirAll(filepath.Dir(src), 0o755); err != nil {
		t.Fatal(err)
	}
	h.file("dotnix/"+dashboardSource, "{ }\n")
	h.file("dotnix/modules/home/sprint/out.json",
		`{"title":"Sprint","templating":{"list":[{"name":"sprint"},{"name":"dev","type":"constant","query":""}]}}`)
	for _, args := range [][]string{{"init", "-q", "-b", "chun/demo"}, {"add", "."},
		{"-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "x"}} {
		if out, err := exec.Command("git", append([]string{"-C", checkout}, args...)...).CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	bin := filepath.Join(h.dir, "bin")
	os.MkdirAll(bin, 0o755)
	// The real call is `nix eval --json --file <checkout>/modules/home/sprint/dashboard.nix`.
	h.file("bin/nix", "#!/bin/sh\n[ \"$1 $2 $3\" = 'eval --json --file' ] || exit 9\ncat \"$(dirname \"$4\")/out.json\"\n")
	os.Chmod(filepath.Join(bin, "nix"), 0o755)
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("SPRINT_DASHBOARDS", filepath.Join(h.dir, "dashboards"))
	t.Setenv("SPRINT_BUILT_DASHBOARD", h.file("built.json", `{"title":"Sprint","built":true}`))
	return h, checkout, filepath.Join(h.dir, "dashboards", "sprint.json")
}

func readDashboard(t *testing.T, path string) map[string]any {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var d map[string]any
	if err := json.Unmarshal(data, &d); err != nil {
		t.Fatal(err)
	}
	return d
}

func devVar(d map[string]any) string {
	for _, v := range d["templating"].(map[string]any)["list"].([]any) {
		if m := v.(map[string]any); m["name"] == "dev" {
			return m["query"].(string)
		}
	}
	return ""
}

func TestDashDevWritesTheCheckoutsDashboardWithItsBranch(t *testing.T) {
	h, checkout, target := dashSetup(t)
	sha, _ := gitOut(checkout, "rev-parse", "--short", "HEAD")
	out := h.ok("dash", "dev", "--checkout", checkout)
	contains_(t, out, "dev: chun/demo@"+sha)
	d := readDashboard(t, target)
	eq(t, devVar(d), "chun/demo@"+sha)
	eq(t, d["title"].(string), "Sprint (dev: chun/demo@"+sha+")")
	entries, _ := os.ReadDir(filepath.Dir(target))
	eq(t, len(entries), 1) // no temp file left behind
}

func TestDashDevMarksUncommittedChanges(t *testing.T) {
	h, checkout, target := dashSetup(t)
	h.file("dotnix/modules/home/sprint/page.css", "x")
	h.ok("dash", "dev", "--checkout", checkout)
	label := devVar(readDashboard(t, target))
	eq(t, label[len(label)-1:], "+")
}

func TestDashDevFindsTheCheckoutAroundTheWorkingFolder(t *testing.T) {
	h, checkout, target := dashSetup(t)
	wd, _ := os.Getwd()
	os.Chdir(filepath.Join(checkout, "modules"))
	t.Cleanup(func() { os.Chdir(wd) })
	h.ok("dash", "dev")
	contains_(t, devVar(readDashboard(t, target)), "chun/demo@")
}

func TestDashDevKeepsTheOldFileWhenEvalFails(t *testing.T) {
	h, checkout, target := dashSetup(t)
	h.ok("dash", "reset")
	h.file("dotnix/modules/home/sprint/out.json", "error: syntax error")
	contains_(t, h.fails("dash", "dev", "--checkout", checkout), "did not print a dashboard")
	eq(t, readDashboard(t, target)["built"], any(true))
	contains_(t, h.fails("dash", "dev", "--checkout", h.dir), "has no "+dashboardSource)
}

func TestDashResetRestoresTheBuiltCopy(t *testing.T) {
	h, checkout, target := dashSetup(t)
	h.ok("dash", "dev", "--checkout", checkout)
	contains_(t, h.ok("dash", "reset"), "reset:")
	eq(t, readDashboard(t, target)["built"], any(true))
	t.Setenv("SPRINT_BUILT_DASHBOARD", filepath.Join(h.dir, "missing.json"))
	contains_(t, h.fails("dash", "reset"), "switch once")
}

func TestDashCommandsLeaveTheLogAlone(t *testing.T) {
	h, checkout, _ := dashSetup(t)
	h.ok("dash", "dev", "--checkout", checkout)
	if _, err := os.Stat(h.db); !os.IsNotExist(err) {
		t.Fatalf("dash dev created the log: %v", err)
	}
}

// A DOM as Chrome dumps it after page/fit.js ran on each page panel.
func fitDOM(live string) string {
	var b strings.Builder
	for _, p := range pagePanels {
		attrs := `data-sp-fit="ok" data-sp-hidden="0" data-sp-gap="10" data-sp-wide="0" data-sp-raw="0" data-sp-wide-at=""`
		if p == "live" {
			attrs = live
		}
		fmt.Fprintf(&b, `<div class="dt-row" data-sp-panel="%s" %s><div class="sp"></div></div>`, p, attrs)
	}
	return b.String()
}

func TestParseFitsReadsEachPanel(t *testing.T) {
	f := parseFits(fitDOM(`data-sp-fit="folded" data-sp-hidden="4" data-sp-gap="200" data-sp-wide="14" data-sp-raw="1" data-sp-wide-at="td &quot;completed&quot;"`))
	eq(t, len(f), len(pagePanels))
	eq(t, f["live"], panelFit{fit: "folded", wideAt: `td "completed"`, hidden: 4, gap: 200, wide: 14, raw: 1})
	eq(t, f["donow"].fit, "ok")
}

// dashCheckSetup has one open sprint with two subgoals (one dropped), and a
// fake Chrome that prints the DOM in dom.html.
func dashCheckSetup(t *testing.T, dom string) *harness {
	h := newHarness(t)
	h.ok("start", "s1", "Sprint one", "--goal", "g")
	h.ok("sub", "add", "a", "Stage A", "--goal", "ga", "--done-when", "x", "--status", "active")
	h.ok("sub", "add", "b", "Stage B", "--goal", "gb", "--done-when", "y")
	h.ok("sub", "set", "b", "dropped", "--reason", "r")
	h.file("dom.html", dom)
	chrome := h.file("chrome", "#!/bin/sh\necho \"$@\" >> \""+h.dir+"/chrome.args\"\ncat \""+h.dir+"/dom.html\"\n")
	os.Chmod(chrome, 0o755)
	t.Setenv("SPRINT_CHROME", chrome)
	return h
}

func TestDashCheckPassesACleanDashboard(t *testing.T) {
	h := dashCheckSetup(t, fitDOM(`data-sp-fit="folded" data-sp-hidden="3" data-sp-gap="0" data-sp-wide="0" data-sp-raw="0" data-sp-wide-at=""`))
	out := h.ok("dash", "check")
	contains_(t, out, "s1 (1512 px wide)")
	contains_(t, out, "s1 / a (1512 px wide)")
	contains_(t, out, "note:    live: 3 item(s) folded to fit")
	if strings.Contains(out, "s1 / b") {
		t.Fatalf("checked a dropped subgoal:\n%s", out)
	}
	args, _ := os.ReadFile(filepath.Join(h.dir, "chrome.args"))
	contains_(t, string(args), "--window-size=1512,5000")
	contains_(t, string(args), "var-subgoal=a")
	contains_(t, string(args), "&kiosk")
}

func TestDashCheckFailsOnLayoutProblems(t *testing.T) {
	h := dashCheckSetup(t, fitDOM(`data-sp-fit="clipped" data-sp-hidden="0" data-sp-gap="300" data-sp-wide="14" data-sp-raw="1" data-sp-wide-at="td &quot;completed&quot;"`))
	out := h.fails("dash", "check", "--width", "1280")
	contains_(t, out, "layout problem(s)")
	_, stdout, _ := h.run("dash", "check", "--width", "1280")
	contains_(t, stdout, `problem: live: content is 14 px wider than its box (td "completed")`)
	contains_(t, stdout, "problem: live: 1 card(s) show raw JSON")
	contains_(t, stdout, "note:    live: one item is taller than the panel")
	contains_(t, stdout, "note:    live: 300 px empty at the bottom")
}

// An opened list that the panel cuts without a scroll is a problem; one
// the panel shows in full and scrolls is a note. --open asks the page to
// open every list.
func TestDashCheckFailsOnCutContentAndOpensLists(t *testing.T) {
	h := dashCheckSetup(t, fitDOM(`data-sp-fit="ok" data-sp-hidden="0" data-sp-gap="0" data-sp-wide="0" data-sp-raw="0" data-sp-wide-at="" data-sp-cut="240" data-sp-open="0"`))
	_, stdout, _ := h.run("dash", "check", "--open")
	contains_(t, stdout, "problem: live: content is cut by 240 px and the panel doesn't scroll")
	args, _ := os.ReadFile(filepath.Join(h.dir, "chrome.args"))
	contains_(t, string(args), "&kiosk&sp-open=1")

	h.file("dom.html", fitDOM(`data-sp-fit="all" data-sp-hidden="0" data-sp-gap="400" data-sp-wide="0" data-sp-raw="0" data-sp-wide-at="" data-sp-cut="0" data-sp-open="2"`))
	out := h.ok("dash", "check")
	contains_(t, out, "note:    live: shown in full (2 list(s) opened); the panel scrolls")
	if strings.Contains(out, "px empty") {
		t.Fatalf("a panel shown in full has no gap to report:\n%s", out)
	}
}

func TestDashCheckFailsWhenAPanelDidNotRender(t *testing.T) {
	h := dashCheckSetup(t, `<div data-sp-panel="header" data-sp-fit="ok"></div>`)
	_, stdout, _ := h.run("dash", "check", "--sprint", "s1")
	contains_(t, stdout, "problem: live: did not render")
	contains_(t, h.fails("dash", "check", "--width", "100"), "at least 320")
}
