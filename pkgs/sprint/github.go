package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

type prInfo struct {
	Title     string `json:"title"`
	URL       string `json:"url"`
	State     string `json:"state"`
	CreatedAt string `json:"createdAt"`
	MergedAt  string `json:"mergedAt"`
	ClosedAt  string `json:"closedAt"`
}

// ghPR asks GitHub about a PR. Tests replace it.
var ghPR = func(url string) (prInfo, error) {
	cmd := exec.Command("gh", "pr", "view", url, "--json", "title,url,state,createdAt,mergedAt,closedAt")
	out, err := cmd.Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return prInfo{}, fmt.Errorf("%s", strings.TrimSpace(string(ee.Stderr)))
		}
		return prInfo{}, err
	}
	var info prInfo
	return info, json.Unmarshal(out, &info)
}

func epoch(stamp string) int64 {
	if stamp == "" {
		return 0
	}
	t, err := time.Parse(time.RFC3339, stamp)
	if err != nil {
		return 0
	}
	return t.Unix()
}

func orNow(t int64) int64 {
	if t == 0 {
		return now()
	}
	return t
}

func (s Store) prLatest(sprintID int64, url string) (PR, bool) {
	var p PR
	ok := s.one("SELECT "+prCols+" FROM pr_state WHERE sprint_id = ? AND url = ?", []any{sprintID, url},
		&p.ID, &p.At, &p.URL, &p.Title, &p.State, &p.Subgoal)
	return p, ok
}

func (s Store) lastPREvent(sprintID int64, url string) int64 {
	return s.int("SELECT MAX(id) FROM pr_events WHERE sprint_id = ? AND url = ?", sprintID, url)
}

type fetchedPR struct {
	key  string // the PR's key in the log
	info prInfo
	seen int64 // the key's newest event id before the GitHub call
}

type fetchedPRs struct {
	sprintID int64
	prs      []fetchedPR
}

// recordPR writes the events that GitHub shows and the log doesn't have yet.
// GitHub may return a different URL after a repo rename, so the key never
// comes from info. If another writer added an event since `seen`, this
// result may be older than theirs, so it is dropped (ok=false); the next
// sync fetches again. subgoal applies to a PR new to the log; a known PR
// keeps its own.
func (s Store) recordPR(sprintID int64, f fetchedPR, subgoal string) (wrote []string, ok bool) {
	if s.lastPREvent(sprintID, f.key) != f.seen {
		return nil, false
	}
	latest := ""
	if row, found := s.prLatest(sprintID, f.key); found {
		latest, subgoal = row.State, row.Subgoal
	}
	add := func(state string, at int64) {
		s.exec("INSERT INTO pr_events (sprint_id, at, url, title, state, subgoal) VALUES (?, ?, ?, ?, ?, ?)",
			sprintID, at, f.key, f.info.Title, state, null(subgoal))
		wrote = append(wrote, state)
		latest = state
	}
	if latest == "" {
		add("opened", orNow(epoch(f.info.CreatedAt)))
	}
	switch {
	case f.info.State == "OPEN" && latest == "closed":
		add("opened", now())
	case f.info.State == "MERGED" && latest != "merged":
		add("merged", orNow(epoch(f.info.MergedAt)))
	case f.info.State == "CLOSED" && latest != "closed" && latest != "merged":
		add("closed", orNow(epoch(f.info.ClosedAt)))
	}
	return wrote, true
}

// fetchPRAdd picks the sprint once, then asks GitHub, before the write lock
// because gh can take seconds. New PRs are keyed by GitHub's own URL, so
// `sprint pr add 12` and the full URL name the same PR. A URL already in the
// log keeps its key, even if the repo was renamed since.
func fetchPRAdd(c *call) {
	s := c.store
	sp := s.resolve(c.flag("sprint"))
	out := fetchedPRs{sprintID: sp.ID}
	for _, arg := range c.many {
		known := s.lastPREvent(sp.ID, arg)
		info, err := ghPR(arg)
		if err != nil {
			fail("%v", err)
		}
		if known != 0 {
			out.prs = append(out.prs, fetchedPR{arg, info, known})
		} else {
			out.prs = append(out.prs, fetchedPR{info.URL, info, s.lastPREvent(sp.ID, info.URL)})
		}
	}
	c.fetched = out
}

// fetchPRSync asks GitHub about every PR that isn't merged, closed ones
// included, so a reopen shows.
func fetchPRSync(c *call) {
	s := c.store
	sp := s.resolve(c.flag("sprint"))
	out := fetchedPRs{sprintID: sp.ID}
	var urls []string
	s.each("SELECT url FROM pr_state WHERE sprint_id = ? AND state != 'merged'", []any{sp.ID}, func(r *sql.Rows) {
		var u string
		check(r.Scan(&u))
		urls = append(urls, u)
	})
	seen := map[string]int64{}
	for _, u := range urls {
		seen[u] = s.lastPREvent(sp.ID, u)
	}
	for _, u := range urls {
		// One deleted or private repo must not stop the other PRs updating.
		info, err := ghPR(u)
		if err != nil {
			fmt.Fprintf(c.errOut, "sprint: could not read %s: %v\n", u, err)
			continue
		}
		out.prs = append(out.prs, fetchedPR{u, info, seen[u]})
	}
	c.fetched = out
}

func savePRs(c *call, quietUnchanged bool, subgoal string) {
	f := c.fetched.(fetchedPRs)
	for _, p := range f.prs {
		wrote, ok := c.store.recordPR(f.sprintID, p, subgoal)
		switch {
		case !ok:
			c.printf("%s: changed during the GitHub call; run `sprint pr sync` again\n", p.key)
		case len(wrote) > 0:
			c.printf("%s: %s\n", p.key, strings.Join(wrote, ", "))
		case !quietUnchanged:
			c.printf("%s: already tracked\n", p.key)
		}
	}
}

func cmdPRAdd(c *call) {
	f := c.fetched.(fetchedPRs)
	savePRs(c, false, c.store.pickSubgoal(f.sprintID, c.flag("subgoal"), c.has("subgoal"), false))
}

func cmdPRSync(c *call) { savePRs(c, true, "") }

func cmdPRReady(c *call) {
	s := c.store
	sp := s.resolve(c.flag("sprint"))
	url := c.pos["url"]
	cur, ok := s.prLatest(sp.ID, url)
	if !ok {
		fail("%s is not in this sprint; run `sprint pr add` first", url)
	}
	if cur.State == "merged" || cur.State == "closed" {
		fail("%s is already %s", url, cur.State)
	}
	s.exec("INSERT INTO pr_events (sprint_id, at, url, title, state, subgoal) VALUES (?, ?, ?, ?, 'ready', ?)",
		sp.ID, now(), url, cur.Title, null(cur.Subgoal))
	c.printf("%s: ready\n", url)
}
