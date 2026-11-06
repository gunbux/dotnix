package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"regexp"
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
	key   string // the PR's key in the log
	info  prInfo
	seen  int64 // the key's newest event id before the GitHub call
	found bool  // found by the search for the user's open PRs, not added
}

type fetchedPRs struct {
	sprintID int64
	prs      []fetchedPR
	statuses map[string]prStatus // review state of the PRs still open, by log key
	lastSync int64               // the newest pr_syncs id before the GitHub calls
	failed   int                 // PRs GitHub could not tell about
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
			out.prs = append(out.prs, fetchedPR{key: arg, info: info, seen: known})
		} else {
			out.prs = append(out.prs, fetchedPR{key: info.URL, info: info, seen: s.lastPREvent(sp.ID, info.URL)})
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
	found, failed := discoverPRs(c, sp, map[string]bool{})
	out.failed += failed
	out.lastSync = s.int("SELECT MAX(id) FROM pr_syncs WHERE sprint_id = ?", sp.ID)
	for _, u := range urls {
		// One deleted or private repo must not stop the other PRs updating.
		info, err := ghPR(u)
		if err != nil {
			fmt.Fprintf(c.errOut, "sprint: could not read %s: %v\n", u, err)
			out.failed++
			continue
		}
		out.prs = append(out.prs, fetchedPR{key: u, info: info, seen: seen[u]})
	}
	out.prs = append(out.prs, found...)
	var open []string
	for _, p := range out.prs {
		if p.info.State == "OPEN" {
			open = append(open, p.key)
		}
	}
	out.statuses = fetchStatuses(c, open)
	out.failed += len(open) - len(out.statuses)
	c.fetched = out
}

func savePRs(c *call, quietUnchanged bool, subgoal string) {
	f := c.fetched.(fetchedPRs)
	for _, p := range f.prs {
		wrote, ok := c.store.recordPR(f.sprintID, p, subgoal)
		switch {
		case !ok:
			c.printf("%s: changed during the GitHub call; run `sprint pr sync` again\n", p.key)
		case p.found && len(wrote) > 0:
			c.printf("%s: found open, added with no stage: %s\n", p.key, p.info.Title)
		case len(wrote) > 0:
			c.printf("%s: %s\n", p.key, strings.Join(wrote, ", "))
		case !quietUnchanged:
			c.printf("%s: already tracked\n", p.key)
		}
	}
}

func cmdPRAdd(c *call) {
	f := c.fetched.(fetchedPRs)
	// Only a PR new to the log takes a subgoal, so only then must it be clear.
	isNew := false
	for _, p := range f.prs {
		isNew = isNew || p.seen == 0
	}
	subgoal := ""
	if isNew || c.has("subgoal") {
		subgoal = c.store.pickSubgoal(f.sprintID, c.flag("subgoal"), c.has("subgoal"), true)
	}
	savePRs(c, false, subgoal)
}

func cmdPRSync(c *call) {
	f := c.fetched.(fetchedPRs)
	savePRs(c, true, "")
	board, key := syncBoard(c, f)
	triageItems(c, f.sprintID, board, key)
}

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

// prStatus is what a review gate needs to know about a PR: its head, the
// review bots' scores, open threads, and checks.
type prStatus struct {
	Number      int    `json:"number"`
	URL         string `json:"url"`
	Title       string `json:"title"`
	State       string `json:"state"`
	IsDraft     bool   `json:"isDraft"`
	BaseRefName string `json:"baseRefName"`
	HeadRefName string `json:"headRefName"`
	// The repository that owns the head branch: a fork's for a fork PR.
	HeadRepository *struct {
		NameWithOwner string `json:"nameWithOwner"`
	} `json:"headRepository"`
	HeadRefOid       string `json:"headRefOid"`
	Mergeable        string `json:"mergeable"`
	MergeStateStatus string `json:"mergeStateStatus"`
	ReviewDecision   string `json:"reviewDecision"`
	MergedAt         string `json:"mergedAt"`
	Commits          struct {
		Nodes []struct {
			Commit struct {
				StatusCheckRollup *struct {
					Contexts struct {
						Nodes []checkNode `json:"nodes"`
						// More than the 100 checks read.
						PageInfo struct {
							HasNextPage bool `json:"hasNextPage"`
						} `json:"pageInfo"`
					} `json:"contexts"`
				} `json:"statusCheckRollup"`
			} `json:"commit"`
		} `json:"nodes"`
	} `json:"commits"`
	ReviewThreads struct {
		Nodes []struct {
			IsResolved bool `json:"isResolved"`
		} `json:"nodes"`
		// More than the 100 threads read: the count is a floor.
		PageInfo struct {
			HasNextPage bool `json:"hasNextPage"`
		} `json:"pageInfo"`
	} `json:"reviewThreads"`
	Comments struct{ Nodes []botPost } `json:"comments"`
	Reviews  struct{ Nodes []botPost } `json:"reviews"`
}

type checkNode struct {
	Typename   string `json:"__typename"`
	Name       string `json:"name"`
	Status     string `json:"status"`
	Conclusion string `json:"conclusion"`
	StartedAt  string `json:"startedAt"`
	Context    string `json:"context"`
	State      string `json:"state"`
	IsRequired bool   `json:"isRequired"`
}

type botPost struct {
	Author      *struct{ Login string } `json:"author"`
	Body        string                  `json:"body"`
	UpdatedAt   string                  `json:"updatedAt"`
	SubmittedAt string                  `json:"submittedAt"`
}

const prStatusQuery = `query($u: URI!, $n: Int!) { resource(url: $u) { ... on PullRequest {
  number url title state isDraft baseRefName headRefName headRepository { nameWithOwner } headRefOid mergeable mergeStateStatus reviewDecision mergedAt
  commits(last: 1) { nodes { commit { statusCheckRollup { contexts(first: 100) { nodes {
    __typename
    ... on CheckRun { name status conclusion startedAt isRequired(pullRequestNumber: $n) }
    ... on StatusContext { context state isRequired(pullRequestNumber: $n) }
  } pageInfo { hasNextPage } } } } } }
  reviewThreads(first: 100) { nodes { isResolved } pageInfo { hasNextPage } }
  comments(last: 40) { nodes { author { login } body updatedAt } }
  reviews(last: 40) { nodes { author { login } body submittedAt } }
} } }`

// ghPRStatus reads one PR's review state. Tests replace it.
var ghPRStatus = func(url string) (prStatus, error) {
	n := url[strings.LastIndex(url, "/")+1:]
	out, err := exec.Command("gh", "api", "graphql", "-f", "query="+prStatusQuery, "-f", "u="+url, "-F", "n="+n).Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return prStatus{}, fmt.Errorf("%s", strings.TrimSpace(string(ee.Stderr)))
		}
		return prStatus{}, err
	}
	var resp struct {
		Data struct {
			Resource *prStatus `json:"resource"`
		} `json:"data"`
	}
	if err := json.Unmarshal(out, &resp); err != nil {
		return prStatus{}, err
	}
	if resp.Data.Resource == nil || resp.Data.Resource.Number == 0 {
		return prStatus{}, fmt.Errorf("%s is not a pull request", url)
	}
	return *resp.Data.Resource, nil
}

// reviewBots are the review bots whose score gates a merge, by GitHub login.
var reviewBots = []struct{ login, name string }{
	{"greptile-apps", "greptile"},
	{"greptile-apps-staging", "greptile-staging"},
}

var (
	confidenceRE = regexp.MustCompile(`Confidence Score: ([0-5])/5`)
	anyScoreRE   = regexp.MustCompile(`(?:^|[^\d])([0-5])/5`)
)

type botScore struct {
	Name   string `json:"name"`
	Score  int    `json:"score"` // -1: no score yet
	OnHead bool   `json:"on_head"`
}

// scores reads each bot's newest score, and whether that review names the
// head commit. A bot that never posted is left out.
func (p prStatus) scores() []botScore {
	var out []botScore
	for _, bot := range reviewBots {
		var newest botPost
		newestAt, posted := "", false
		for _, post := range append(append([]botPost{}, p.Comments.Nodes...), p.Reviews.Nodes...) {
			if post.Author == nil || post.Author.Login != bot.login {
				continue
			}
			posted = true
			at := post.UpdatedAt + post.SubmittedAt
			if anyScoreRE.MatchString(post.Body) && at >= newestAt {
				newest, newestAt = post, at
			}
		}
		if !posted {
			continue
		}
		s := botScore{Name: bot.name, Score: -1}
		if m := confidenceRE.FindStringSubmatch(newest.Body); m != nil {
			s.Score = int(m[1][0] - '0')
		} else if all := anyScoreRE.FindAllStringSubmatch(newest.Body, -1); all != nil {
			s.Score = int(all[len(all)-1][1][0] - '0')
		}
		s.OnHead = s.Score >= 0 && len(p.HeadRefOid) >= 7 && strings.Contains(newest.Body, p.HeadRefOid[:7])
		out = append(out, s)
	}
	return out
}

func (p prStatus) openThreads() int {
	n := 0
	for _, t := range p.ReviewThreads.Nodes {
		if !t.IsResolved {
			n++
		}
	}
	return n
}

var failedChecks = map[string]bool{"FAILURE": true, "TIMED_OUT": true, "CANCELLED": true,
	"ACTION_REQUIRED": true, "STARTUP_FAILURE": true, "ERROR": true}

// allChecksRead is false when the PR has more checks than one page holds.
func (p prStatus) allChecksRead() bool {
	return len(p.Commits.Nodes) == 0 || p.Commits.Nodes[0].Commit.StatusCheckRollup == nil ||
		!p.Commits.Nodes[0].Commit.StatusCheckRollup.Contexts.PageInfo.HasNextPage
}

// checks names the failing checks and counts the running ones. A push can
// start a check twice and GitHub cancels the older run, so only the newest
// run of each name counts. Two runs can start in the same second; then a
// cancelled run loses to the other, whatever order GitHub lists them in.
// When the base branch requires some checks, only those count: an optional
// check that fails or runs does not block a merge. With no required checks,
// every check counts.
func (p prStatus) checks() (failing []string, running int) {
	if len(p.Commits.Nodes) == 0 || p.Commits.Nodes[0].Commit.StatusCheckRollup == nil {
		return nil, 0
	}
	all := p.Commits.Nodes[0].Commit.StatusCheckRollup.Contexts.Nodes
	anyRequired := false
	for _, c := range all {
		anyRequired = anyRequired || c.IsRequired
	}
	newest := map[string]checkNode{}
	var names []string
	for _, c := range all {
		if anyRequired && !c.IsRequired {
			continue
		}
		if c.Typename != "CheckRun" {
			switch {
			case c.State == "PENDING" || c.State == "EXPECTED":
				running++
			case failedChecks[c.State]:
				failing = append(failing, c.Context)
			}
			continue
		}
		old, seen := newest[c.Name]
		if !seen {
			names = append(names, c.Name)
		}
		tieWin := c.StartedAt == old.StartedAt && old.Conclusion == "CANCELLED" && c.Conclusion != "CANCELLED"
		if !seen || c.StartedAt > old.StartedAt || tieWin {
			newest[c.Name] = c
		}
	}
	for _, n := range names {
		c := newest[n]
		switch {
		case c.Status != "COMPLETED":
			running++
		case failedChecks[c.Conclusion]:
			failing = append(failing, c.Name)
		}
	}
	return failing, running
}
