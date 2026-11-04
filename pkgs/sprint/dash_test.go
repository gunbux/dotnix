package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
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
