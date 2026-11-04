package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"sync"
)

// The PR board sorts a sprint's open PRs by what the user must do next:
// Merge now, Fix first, or Waiting, in review order. `sprint pr sync` reads
// each open PR's review state from GitHub, builds the board, and logs a row
// per PR when its row changes (pr_reviews). The dashboard renders the latest
// rows, so the board needs no generator.

// prReview is one PR's row on the board.
type prReview struct {
	URL      string      `json:"url"`
	Number   int         `json:"number"`
	Head     string      `json:"head"`
	HeadRef  string      `json:"-"`
	Base     string      `json:"base"`
	Draft    bool        `json:"draft"`
	Failing  []string    `json:"failing"`
	Running  int         `json:"running"`
	Threads  int         `json:"threads"`
	Bots     []botScore  `json:"bots"`
	Group    string      `json:"group"`
	Steps    []string    `json:"steps"`
	Rank     int         `json:"rank"`
	Why      string      `json:"why"`
	Stack    string      `json:"stack"`
	parent   *prReview   // the PR this one is stacked on
	status   prStatus    // what GitHub said
	fix      []string    // what blocks the merge
	wait     []string    // what it waits on
	prio     [2]int      // review order: reason, then tooling last
	children []*prReview // PRs stacked on this one
}

var groupOrder = map[string]int{"merge": 0, "fix": 1, "wait": 2}

// toolingRE marks PRs reviewed last: docs, tests, chores, CI.
var toolingRE = regexp.MustCompile(`^(docs|tests?|chore|ci)(\(|:)`)

// priority is the review order for a PR: one that an open blocker item names,
// then one any open item names, then code, then tooling. why says which.
func priority(p *prReview, title string, items []Item) ([2]int, string) {
	mention := regexp.MustCompile(fmt.Sprintf(`(#|/pull/)%d(\D|$)`, p.Number))
	tooling := 0
	if toolingRE.MatchString(title) {
		tooling = 1
	}
	var named []Item
	for _, i := range items {
		if mention.MatchString(i.Title + " " + i.Note) {
			named = append(named, i)
		}
	}
	for _, i := range named {
		if strings.Contains(strings.ToLower(i.Title), "blocker") {
			short := strings.TrimSpace(regexp.MustCompile(`[:(]`).Split(i.Title, 2)[0])
			return [2]int{0, tooling}, fmt.Sprintf("%s (sprint item %d)", short, i.Item)
		}
	}
	if len(named) > 0 {
		return [2]int{1, tooling}, fmt.Sprintf("On your sprint list (item %d)", named[0].Item)
	}
	if tooling == 1 {
		return [2]int{3, 1}, "Docs, tests or tooling"
	}
	return [2]int{2, 0}, "Code or infra change"
}

func plural(n int, one string) string {
	if n == 1 {
		return fmt.Sprintf("%d %s", n, one)
	}
	return fmt.Sprintf("%d %ss", n, one)
}

// buildBoard groups and orders the open PRs. items are the sprint's open
// plan items, which can move a PR up the review order.
func buildBoard(statuses []prStatus, items []Item) []*prReview {
	byHead := map[string]*prReview{}
	var prs []*prReview
	for _, s := range statuses {
		failing, running := s.checks()
		p := &prReview{URL: s.URL, Number: s.Number, Head: s.HeadRefOid, HeadRef: s.HeadRefName, Base: s.BaseRefName,
			Draft: s.IsDraft, Failing: failing, Running: running, Threads: s.openThreads(), Bots: s.scores(), status: s}
		if len(p.Head) > 10 {
			p.Head = p.Head[:10]
		}
		if p.Failing == nil {
			p.Failing = []string{}
		}
		if p.Bots == nil {
			p.Bots = []botScore{}
		}
		p.prio, p.Why = priority(p, s.Title, items)
		byHead[repoOf(s.URL)+" "+s.HeadRefName] = p
		prs = append(prs, p)
	}
	for _, p := range prs {
		if parent := byHead[repoOf(p.URL)+" "+p.Base]; parent != nil && parent != p {
			p.parent = parent
			parent.children = append(parent.children, p)
		}
	}
	for _, p := range prs {
		s := p.status
		var fix, wait []string
		if len(p.Failing) > 0 {
			shown := p.Failing[:min(3, len(p.Failing))]
			msg := "Fails `" + strings.Join(shown, "`, `") + "`"
			if len(p.Failing) > 3 {
				msg += fmt.Sprintf(" and %d more", len(p.Failing)-3)
			}
			fix = append(fix, msg)
		}
		if s.Mergeable == "CONFLICTING" {
			fix = append(fix, "Has merge conflicts with its base")
		}
		if p.Threads > 0 {
			fix = append(fix, plural(p.Threads, "open review thread"))
		}
		for _, b := range p.Bots {
			if b.OnHead && b.Score < 5 {
				fix = append(fix, fmt.Sprintf("%s scores %d/5", b.Name, b.Score))
			}
		}
		if s.ReviewDecision == "CHANGES_REQUESTED" {
			fix = append(fix, "A reviewer asks for changes")
		}
		if p.parent == nil && p.Base != "main" && p.Base != "master" {
			wait = append(wait, fmt.Sprintf("Based on `%s`, not main", p.Base))
		}
		if p.Draft {
			wait = append(wait, "Draft")
		}
		if len(p.Bots) == 0 {
			wait = append(wait, "No review bot has scored it yet")
		}
		for _, b := range p.Bots {
			if !b.OnHead {
				wait = append(wait, b.Name+" has not reviewed the newest commit")
			}
		}
		if p.Running > 0 && len(p.Failing) == 0 {
			wait = append(wait, plural(p.Running, "check")+" still running")
		}
		if s.ReviewDecision == "REVIEW_REQUIRED" {
			wait = append(wait, "Needs an approval")
		}
		p.fix, p.wait = fix, wait
	}
	// A stacked PR merges only after every PR below it; until then it waits.
	ownReady := func(p *prReview) bool { return len(p.fix) == 0 && len(p.wait) == 0 }
	for _, p := range prs {
		after := ""
		if p.parent != nil {
			ready := ownReady(p)
			for q := p.parent; q != nil; q = q.parent {
				ready = ready && ownReady(q)
			}
			if ready {
				after = fmt.Sprintf("Merge right after #%d.", p.parent.Number)
			} else {
				p.wait = append([]string{fmt.Sprintf("Stacked: merge #%d first", p.parent.Number)}, p.wait...)
			}
		}
		switch {
		case len(p.fix) > 0:
			p.Group = "fix"
		case len(p.wait) > 0:
			p.Group = "wait"
		default:
			p.Group = "merge"
		}
		p.Steps = append(append([]string{}, p.fix...), p.wait...)
		if after != "" {
			p.Steps = []string{after}
		}
	}
	// Review order: group, then the stack root's priority and number, then
	// the place in the stack.
	root := func(p *prReview) (*prReview, int) {
		depth := 0
		for p.parent != nil {
			p, depth = p.parent, depth+1
		}
		return p, depth
	}
	sort.SliceStable(prs, func(i, j int) bool {
		a, b := prs[i], prs[j]
		if groupOrder[a.Group] != groupOrder[b.Group] {
			return groupOrder[a.Group] < groupOrder[b.Group]
		}
		ra, da := root(a)
		rb, db := root(b)
		if ra.prio != rb.prio {
			return ra.prio[0] < rb.prio[0] || ra.prio[0] == rb.prio[0] && ra.prio[1] < rb.prio[1]
		}
		if ra.Number != rb.Number {
			return ra.Number < rb.Number
		}
		return da < db
	})
	for i, p := range prs {
		p.Rank = i + 1
		r, depth := root(p)
		if size := stackSize(r); size > 1 {
			p.Stack = fmt.Sprintf("stack %d of %d", depth+1, size)
		}
	}
	return prs
}

func stackSize(p *prReview) int {
	n := 1
	for _, c := range p.children {
		n += stackSize(c)
	}
	return n
}

var repoRE = regexp.MustCompile(`github\.com/([^/]+/[^/]+)/pull/`)

func repoOf(url string) string {
	if m := repoRE.FindStringSubmatch(url); m != nil {
		return strings.ToLower(m[1])
	}
	return ""
}

func jsonText(v any) string {
	b, err := json.Marshal(v)
	check(err)
	return string(b)
}

// recordReviews logs each board row that differs from that PR's last row.
// key maps GitHub's URL back to the URL the log uses for the PR.
func (s Store) recordReviews(sprintID int64, board []*prReview, key map[string]string) {
	at := now()
	for _, p := range board {
		url := key[p.URL]
		if url == "" {
			url = p.URL
		}
		row := []any{p.Number, p.Head, p.Base, p.Draft, jsonText(p.Failing), p.Running, p.Threads, jsonText(p.Bots),
			p.Group, jsonText(p.Steps), p.Rank, p.Why, p.Stack}
		var last string
		s.one("SELECT number || '|' || head || '|' || base || '|' || draft || '|' || failing || '|' || running || '|' || "+
			"threads || '|' || bots || '|' || grp || '|' || steps || '|' || rank || '|' || why || '|' || stack "+
			"FROM pr_review_state WHERE sprint_id = ? AND url = ?", []any{sprintID, url}, &last)
		parts := make([]string, len(row))
		for i, v := range row {
			if b, ok := v.(bool); ok {
				v = map[bool]int{false: 0, true: 1}[b]
			}
			parts[i] = fmt.Sprint(v)
		}
		if strings.Join(parts, "|") == last {
			continue
		}
		s.exec("INSERT INTO pr_reviews (sprint_id, at, url, number, head, base, draft, failing, running, threads, bots, "+
			"grp, steps, rank, why, stack) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
			append([]any{sprintID, at, url}, row...)...)
	}
}

// fetchStatuses reads the review state of PRs GitHub says are open, a few
// at a time. A PR it cannot read is reported and left off the board.
func fetchStatuses(c *call, urls []string) map[string]prStatus {
	out := map[string]prStatus{}
	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, 6)
	for _, u := range urls {
		wg.Add(1)
		go func(u string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			st, err := ghPRStatus(u)
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				fmt.Fprintf(c.errOut, "sprint: could not read the review state of %s: %v\n", u, err)
				return
			}
			out[u] = st
		}(u)
	}
	wg.Wait()
	return out
}

func (s Store) openItems(sprintID int64) []Item {
	var items []Item
	s.each("SELECT "+itemCols+" FROM item_state WHERE sprint_id = ? AND status NOT IN ('done', 'dropped') ORDER BY position",
		[]any{sprintID}, func(r *sql.Rows) { items = append(items, scanItem(r)) })
	return items
}

// syncBoard builds the board from the statuses fetched for PRs that are
// still open after this sync, and logs what changed.
func syncBoard(c *call, f fetchedPRs) {
	s := c.store
	var statuses []prStatus
	key := map[string]string{}
	for _, p := range f.prs {
		st, ok := f.statuses[p.key]
		cur, tracked := s.prLatest(f.sprintID, p.key)
		if !ok || !tracked || cur.State == "merged" || cur.State == "closed" {
			continue
		}
		statuses = append(statuses, st)
		key[st.URL] = p.key
	}
	board := buildBoard(statuses, s.openItems(f.sprintID))
	s.recordReviews(f.sprintID, board, key)
	counts := map[string]int{}
	for _, p := range board {
		counts[p.Group]++
	}
	c.printf("PR board: %d merge now, %d fix first, %d waiting\n", counts["merge"], counts["fix"], counts["wait"])
}

func cmdPRNote(c *call) {
	s := c.store
	sp := s.resolve(c.flag("sprint"))
	url := c.pos["url"]
	if _, ok := s.prLatest(sp.ID, url); !ok {
		fail("%s is not in this sprint; run `sprint pr add` first", url)
	}
	text := strings.TrimSpace(c.pos["text"])
	if text == "-" {
		text = ""
	}
	s.exec("INSERT INTO pr_notes (sprint_id, at, url, text) VALUES (?, ?, ?, ?)", sp.ID, now(), url, text)
	if text == "" {
		c.printf("%s: note removed\n", url)
		return
	}
	c.printf("%s: note set\n", url)
}
