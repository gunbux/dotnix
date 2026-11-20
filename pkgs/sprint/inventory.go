package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"sort"
	"strings"
	"time"
)

// Inventory: `sprint inventory` lists every source a catch-up must cover, so
// a status report starts from the whole set and not from what the agent
// remembers. It covers what the CLI can reach: the user's open PRs in every
// repository, the PRs that wait for the user's review, and each open
// sprint's do-now list and tracked PRs. The T3 threads it cannot reach come
// last, as the exact tool calls to make.

// searchPR is one PR from `gh search prs`.
type searchPR struct {
	Repository struct {
		NameWithOwner string `json:"nameWithOwner"`
	} `json:"repository"`
	Number    int    `json:"number"`
	Title     string `json:"title"`
	IsDraft   bool   `json:"isDraft"`
	UpdatedAt string `json:"updatedAt"`
	URL       string `json:"url"`
	Author    struct {
		Login string `json:"login"`
	} `json:"author"`
}

// ghSearchPRs runs `gh search prs` with one filter (--author @me or
// --review-requested @me). Tests replace it. gh reads no stdin: exec gives
// it /dev/null.
var ghSearchPRs = func(filter string) ([]searchPR, error) {
	out, err := exec.Command("gh", "search", "prs", filter, "@me", "--state", "open", "--limit", "200",
		"--json", "repository,number,title,isDraft,updatedAt,url,author").Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return nil, fmt.Errorf("%s", strings.TrimSpace(string(ee.Stderr)))
		}
		return nil, err
	}
	var prs []searchPR
	return prs, json.Unmarshal(out, &prs)
}

// testGroup names the group of a repository that holds only benchmark or
// test PRs, or returns "": a catch-up counts these PRs and does not list
// them. All greptile-bench repositories count as one group.
func testGroup(repo string) string {
	switch {
	case strings.HasPrefix(repo, "greptile-bench/"):
		return "greptile-bench/*"
	case repo == "gunbux/greptile-k8s-sandbox-test":
		return repo
	}
	return ""
}

// staleAfter is how long a PR can go without an update before the
// inventory counts it as stale.
const staleAfter = 30 * 24 * time.Hour

type invPR struct {
	Repo    string `json:"repo"`
	Number  int    `json:"number"`
	Title   string `json:"title"`
	Draft   bool   `json:"draft"`
	Updated string `json:"updated"`
	URL     string `json:"url"`
	Author  string `json:"author,omitempty"`
	Sprint  string `json:"sprint,omitempty"`
}

type invCount struct {
	Repo  string `json:"repo"`
	Count int    `json:"count"`
}

type invSprint struct {
	Sprint string   `json:"sprint"`
	DoNow  int      `json:"do_now"`
	Open   []string `json:"open_prs"`
}

type inventory struct {
	Mine       []invPR     `json:"mine"`
	TestRepos  []invCount  `json:"test_repos"`
	Stale      []invPR     `json:"stale"`
	Review     []invPR     `json:"review_requested"`
	Sprints    []invSprint `json:"sprints"`
	Untracked  []string    `json:"untracked"`
	Errors     []string    `json:"errors"`
	T3Calls    []string    `json:"t3_calls"`
	StaleAfter string      `json:"stale_after"`
}

// t3Calls are the steps only an agent with the T3 tools can do.
var t3Calls = []string{
	"t3_thread_list {allProjects: true, settled: false}: page with cursor until nextCursor is null; keep the top-level threads (relationshipToParent is not subagent)",
	"t3_environment_links: for each link with status reachable, run the same t3_thread_list with its environmentId",
	"t3_thread_read {limit: 1} for each thread updated in the last 3 days: collect every PR it names, also PRs by other people (a review), and each step it waits on",
	"Reconcile: put every PR above and every thread in one report section, or under \"Threads you can close\"",
}

type invFetch struct {
	mine, review       []searchPR
	mineErr, reviewErr error
}

func prefetchInventory(c *call) {
	var f invFetch
	f.mine, f.mineErr = ghSearchPRs("--author")
	f.review, f.reviewErr = ghSearchPRs("--review-requested")
	c.fetched = f
}

func toInvPR(p searchPR) invPR {
	return invPR{Repo: p.Repository.NameWithOwner, Number: p.Number, Title: p.Title, Draft: p.IsDraft,
		Updated: p.UpdatedAt, URL: p.URL, Author: p.Author.Login}
}

func buildInventory(c *call) inventory {
	f, _ := c.fetched.(invFetch)
	inv := inventory{Mine: []invPR{}, TestRepos: []invCount{}, Stale: []invPR{}, Review: []invPR{},
		Sprints: []invSprint{}, Untracked: []string{}, Errors: []string{}, T3Calls: t3Calls,
		StaleAfter: fmt.Sprintf("%d days", int(staleAfter.Hours()/24))}
	if f.mineErr != nil {
		inv.Errors = append(inv.Errors, "could not list your open PRs: "+f.mineErr.Error())
	}
	if f.reviewErr != nil {
		inv.Errors = append(inv.Errors, "could not list PRs that wait for your review: "+f.reviewErr.Error())
	}

	// Each open sprint's do-now count and tracked open PRs.
	tracked := map[string]string{}
	sprints := c.store.openSprints()
	if c.flag("sprint") != "" {
		sprints = []Sprint{c.store.resolve(c.flag("sprint"))}
	}
	for _, sp := range sprints {
		is := invSprint{Sprint: sp.Slug, Open: []string{}}
		c.store.one("SELECT COUNT(*) FROM do_now WHERE sprint_id = ?", []any{sp.ID}, &is.DoNow)
		c.store.each("SELECT url FROM pr_state WHERE sprint_id = ? AND state NOT IN ('merged', 'closed') ORDER BY url",
			[]any{sp.ID}, func(r *sql.Rows) {
				var u string
				check(r.Scan(&u))
				is.Open = append(is.Open, u)
				tracked[u] = sp.Slug
			})
		inv.Sprints = append(inv.Sprints, is)
	}

	cutoff := time.Unix(now(), 0).Add(-staleAfter)
	counts := map[string]int{}
	for _, p := range f.mine {
		ip := toInvPR(p)
		ip.Author = ""
		ip.Sprint = tracked[ip.URL]
		if t, err := time.Parse(time.RFC3339, ip.Updated); err == nil && t.Before(cutoff) {
			inv.Stale = append(inv.Stale, ip)
			continue
		}
		if g := testGroup(ip.Repo); g != "" {
			counts[g]++
			continue
		}
		inv.Mine = append(inv.Mine, ip)
		if ip.Sprint == "" {
			inv.Untracked = append(inv.Untracked, ip.URL)
		}
	}
	for repo, n := range counts {
		inv.TestRepos = append(inv.TestRepos, invCount{repo, n})
	}
	sort.Slice(inv.TestRepos, func(i, j int) bool { return inv.TestRepos[i].Repo < inv.TestRepos[j].Repo })
	sort.SliceStable(inv.Mine, func(i, j int) bool {
		if inv.Mine[i].Repo != inv.Mine[j].Repo {
			return inv.Mine[i].Repo < inv.Mine[j].Repo
		}
		return inv.Mine[i].Number < inv.Mine[j].Number
	})
	for _, p := range f.review {
		inv.Review = append(inv.Review, toInvPR(p))
	}
	return inv
}

func cmdInventory(c *call) {
	inv := buildInventory(c)
	if c.has("json") {
		b, err := json.MarshalIndent(inv, "", "  ")
		check(err)
		c.printf("%s\n", b)
		return
	}
	for _, e := range inv.Errors {
		c.printf("ERROR: %s\n", e)
	}
	c.printf("Your open PRs (%d):\n", len(inv.Mine))
	repo := ""
	for _, p := range inv.Mine {
		if p.Repo != repo {
			repo = p.Repo
			c.printf("  %s\n", repo)
		}
		tags := []string{}
		if p.Draft {
			tags = append(tags, "draft")
		}
		if p.Sprint != "" {
			tags = append(tags, "sprint "+p.Sprint)
		} else {
			tags = append(tags, "in no sprint")
		}
		c.printf("    [ ] #%d %s (%s; updated %s)\n", p.Number, p.Title, strings.Join(tags, ", "), dateOf(p.Updated))
	}
	for _, t := range inv.TestRepos {
		c.printf("  [ ] %s: %d test PRs (count only)\n", t.Repo, t.Count)
	}
	if len(inv.Stale) > 0 {
		c.printf("  [ ] %d stale PRs, not updated in %s (list with --json)\n", len(inv.Stale), inv.StaleAfter)
	}
	c.printf("PRs that wait for your review (%d):\n", len(inv.Review))
	for _, p := range inv.Review {
		c.printf("  [ ] %s#%d %s (by %s; updated %s)\n", p.Repo, p.Number, p.Title, p.Author, dateOf(p.Updated))
	}
	for _, s := range inv.Sprints {
		c.printf("Sprint %s: %d do-now steps, %d open PRs tracked\n", s.Sprint, s.DoNow, len(s.Open))
		for _, u := range s.Open {
			c.printf("  [ ] %s\n", u)
		}
	}
	if len(inv.Untracked) > 0 {
		c.printf("Open PRs in no sprint (%d): put each in the report\n", len(inv.Untracked))
	}
	c.printf("T3, gather with tools (this CLI cannot reach T3):\n")
	for i, s := range inv.T3Calls {
		c.printf("  %d. %s\n", i+1, s)
	}
}

func dateOf(stamp string) string {
	if len(stamp) >= 10 {
		return stamp[:10]
	}
	return stamp
}
