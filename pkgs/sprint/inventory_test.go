package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
)

func stubSearch(t *testing.T, fn func(string) ([]searchPR, error)) {
	real := ghSearchPRs
	ghSearchPRs = fn
	t.Cleanup(func() { ghSearchPRs = real })
}

func spr(repo string, n int, title, updated, author string) searchPR {
	var p searchPR
	p.Repository.NameWithOwner = repo
	p.Number, p.Title, p.UpdatedAt = n, title, updated
	p.URL = fmt.Sprintf("https://github.com/%s/pull/%d", repo, n)
	p.Author.Login = author
	return p
}

// The catch-up of 20 Nov 2026 missed #20103 in the sprint's own repo, the
// test-repo PRs, and a PR that waited for review. The inventory must name
// each of them.
func pastMiss(t *testing.T) {
	stubSearch(t, func(filter string) ([]searchPR, error) {
		switch filter {
		case "--author":
			return []searchPR{
				spr("gunbux/greptile-k8s-sandbox-test", 35, "Add free shipping above a subtotal", "2026-11-18T18:49:54Z", "gunbux"),
				spr("greptile-bench/bench-trex-steer-k", 4, "Add a bill-splitting page", "2026-11-19T10:56:08Z", "gunbux"),
				spr("greptileai/greptilia", 20103, "sandbox-orchestrator: retry a Pod create that loses a quota race", "2026-11-20T09:00:00Z", "gunbux"),
				spr("greptileai/greptilia", 19792, "Production Kubernetes sandboxes 6/7", "2026-11-20T09:50:00Z", "gunbux"),
				spr("gunbux/xs-oooc", 1, "Compare", "2023-02-16T00:00:00Z", "gunbux"),
			}, nil
		case "--review-requested":
			return []searchPR{spr("greptileai/greptilia", 18975, "grepbox-k8s-staging: pin the orchestrator", "2026-11-17T00:00:00Z", "devin-ai-integration[bot]")}, nil
		}
		return nil, fmt.Errorf("unexpected filter %s", filter)
	})
}

func TestInventoryNamesEveryOpenPR(t *testing.T) {
	h := newHarness(t)
	h.clock(1795190400) // 2026-11-20
	pastMiss(t)
	w := newWorld(t)
	tracked := waiting(19792, "Production Kubernetes sandboxes 6/7")
	tracked.URL = "https://github.com/greptileai/greptilia/pull/19792"
	w.set(tracked)
	h.ok("start", "s1", "One", "--goal", "g")
	h.ok("pr", "add", "https://github.com/greptileai/greptilia/pull/19792")

	out := h.ok("inventory")
	contains_(t, out, "  greptileai/greptilia\n")
	contains_(t, out, "#20103 sandbox-orchestrator: retry a Pod create that loses a quota race (in no sprint;")
	contains_(t, out, "#19792 Production Kubernetes sandboxes 6/7 (sprint s1;")
	contains_(t, out, "gunbux/greptile-k8s-sandbox-test: 1 test PRs (count only)")
	contains_(t, out, "greptile-bench/*: 1 test PRs (count only)")
	contains_(t, out, "1 stale PRs, not updated in 30 days")
	contains_(t, out, "greptileai/greptilia#18975 grepbox-k8s-staging: pin the orchestrator (by devin-ai-integration[bot];")
	contains_(t, out, "Sprint s1: 0 do-now steps, 1 open PRs tracked")
	contains_(t, out, "t3_thread_list {allProjects: true, settled: false}")
	contains_(t, out, "t3_environment_links")
	if strings.Contains(out, "xs-oooc") {
		t.Fatalf("listed a stale PR:\n%s", out)
	}

	var inv inventory
	check(json.Unmarshal([]byte(h.ok("inventory", "--json")), &inv))
	eq(t, len(inv.Mine), 2)
	eq(t, len(inv.Stale), 1)
	eq(t, len(inv.Review), 1)
	eq(t, strings.Join(inv.Untracked, " "), "https://github.com/greptileai/greptilia/pull/20103")
}

func TestInventoryReportsAFailedSearch(t *testing.T) {
	h := newHarness(t)
	stubSearch(t, func(string) ([]searchPR, error) { return nil, fmt.Errorf("rate limited") })
	out := h.ok("inventory")
	contains_(t, out, "ERROR: could not list your open PRs: rate limited")
	contains_(t, out, "ERROR: could not list PRs that wait for your review: rate limited")
}
