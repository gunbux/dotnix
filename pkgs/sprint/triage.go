package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
)

// PR triage: `sprint pr sync` finds the user's open PRs that no one added,
// and keeps the Do now list covering the PRs that need the user: one to
// merge, or one with no stage. The items it adds carry a note that starts
// with syncNote, on their first event, so a later sync can find and close
// them however the user edits them.

const syncNote = "Added by sprint pr sync: "

// openPR is one of the user's open PRs, from a repository search.
type openPR struct {
	URL         string `json:"url"`
	Title       string `json:"title"`
	State       string `json:"state"`
	CreatedAt   string `json:"createdAt"`
	HeadRefName string `json:"headRefName"`
}

// ghMyOpenPRs lists the authenticated user's open PRs in one repository.
// Tests replace it. gh reads no stdin: exec gives it /dev/null.
var ghMyOpenPRs = func(repo string) ([]openPR, error) {
	out, err := exec.Command("gh", "pr", "list", "--repo", repo, "--author", "@me", "--state", "open",
		"--limit", "200", "--json", "url,title,state,createdAt,headRefName").Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return nil, fmt.Errorf("%s", strings.TrimSpace(string(ee.Stderr)))
		}
		return nil, err
	}
	var prs []openPR
	return prs, json.Unmarshal(out, &prs)
}

// prNumber is the number at the end of a PR URL.
func prNumber(url string) int {
	n, _ := strconv.Atoi(url[strings.LastIndex(url, "/")+1:])
	return n
}

// mentionRE matches text that names the PR: a bare #N, or its full URL.
func mentionRE(url string, number int) *regexp.Regexp {
	return regexp.MustCompile(fmt.Sprintf(`(?i)(^|[^\w/])#%d(\D|$)|github\.com/%s/pull/%d(\D|$)`,
		number, regexp.QuoteMeta(repoOf(url)), number))
}

// ignorePatterns are the sprint's active `sprint pr ignore` patterns.
func (s Store) ignorePatterns(sprintID int64) []*regexp.Regexp {
	var out []*regexp.Regexp
	for _, p := range s.strings("SELECT pattern FROM pr_ignore_state WHERE sprint_id = ? ORDER BY pattern", sprintID) {
		if re, err := regexp.Compile("(?i)" + p); err == nil {
			out = append(out, re)
		}
	}
	return out
}

// discoverPRs lists the user's open PRs in every repository the sprint
// tracks PRs in, and returns those new to the log. It skips a PR that
// another open sprint tracks, or that an ignore pattern matches by head
// branch, title, or URL. A repository it cannot list counts as failed.
func discoverPRs(c *call, sp Sprint, known map[string]bool) (found []fetchedPR, failed int) {
	s := c.store
	repos := map[string]bool{}
	var order []string
	for _, u := range s.strings("SELECT DISTINCT url FROM pr_events WHERE sprint_id = ? ORDER BY url", sp.ID) {
		known[u] = true
		if r := repoOf(u); r != "" && !repos[r] {
			repos[r] = true
			order = append(order, r)
		}
	}
	elsewhere := map[string]bool{}
	for _, other := range s.openSprints() {
		if other.ID == sp.ID {
			continue
		}
		for _, u := range s.strings("SELECT DISTINCT url FROM pr_events WHERE sprint_id = ?", other.ID) {
			elsewhere[u] = true
		}
	}
	ignore := s.ignorePatterns(sp.ID)
	for _, repo := range order {
		prs, err := ghMyOpenPRs(repo)
		if err != nil {
			fmt.Fprintf(c.errOut, "sprint: could not list your open PRs in %s: %v\n", repo, err)
			failed++
			continue
		}
	next:
		for _, p := range prs {
			if p.URL == "" || known[p.URL] || elsewhere[p.URL] {
				continue
			}
			for _, re := range ignore {
				if re.MatchString(p.HeadRefName) || re.MatchString(p.Title) || re.MatchString(p.URL) {
					continue next
				}
			}
			known[p.URL] = true
			info := prInfo{Title: p.Title, URL: p.URL, State: p.State, CreatedAt: p.CreatedAt}
			found = append(found, fetchedPR{key: p.URL, info: info, found: true})
		}
	}
	return found, failed
}

// syncItem is an item `sprint pr sync` added, read from its first event.
type syncItem struct {
	item       int64
	kind, url  string // kind: merge or stage
	status     string // its status now
	subgoalNow string
}

func (s Store) syncItems(sprintID int64) []syncItem {
	var out []syncItem
	s.each(`SELECT f.item, f.note, i.status, COALESCE(i.subgoal, '')
	        FROM item_events f JOIN item_state i ON i.sprint_id = f.sprint_id AND i.item = f.item
	        WHERE f.sprint_id = ? AND f.note LIKE ? || '%'
	          AND f.id = (SELECT MIN(f2.id) FROM item_events f2 WHERE f2.sprint_id = f.sprint_id AND f2.item = f.item)
	        ORDER BY f.item`, []any{sprintID, syncNote}, func(r *sql.Rows) {
		var it syncItem
		var note string
		check(r.Scan(&it.item, &note, &it.status, &it.subgoalNow))
		it.kind, it.url, _ = strings.Cut(strings.TrimPrefix(note, syncNote), " ")
		out = append(out, it)
	})
	return out
}

func closed(status string) bool { return status == "done" || status == "dropped" }

// triageItems keeps Do now covering the open PRs: a "Merge" step for each
// PR on the board's Merge now list that no open step of the user's names,
// and a "Pick a stage" step for each open PR with no subgoal while the
// sprint has stages. Each is added once per PR. When the PR merges or
// closes, or gets a stage, sync marks its own step done. board is nil when
// this sync dropped its board.
func triageItems(c *call, sprintID int64, board []*prReview, key map[string]string) {
	s := c.store
	items := s.syncItems(sprintID)
	had := map[string]bool{} // kind + " " + url
	auto := map[int64]bool{}
	for _, it := range items {
		had[it.kind+" "+it.url] = true
		auto[it.item] = true
	}
	setStatus := func(it syncItem, note string) {
		cur := s.latestItem(sprintID, it.item)
		cur.At, cur.Status, cur.Note = now(), "done", note
		s.addItemEvent(sprintID, cur)
		c.printf("item %d: done (%s)\n", cur.Item, note)
	}
	for _, it := range items {
		if closed(it.status) {
			continue
		}
		pr, ok := s.prLatest(sprintID, it.url)
		switch {
		case !ok:
		case pr.State == "merged" || pr.State == "closed":
			setStatus(it, "PR "+pr.State)
		case it.kind == "stage" && pr.Subgoal != "":
			setStatus(it, "PR moved to "+pr.Subgoal)
		}
	}
	add := func(kind, url, title, subgoal string) {
		item := s.int("SELECT COALESCE(MAX(item), 0) + 1 FROM item_events WHERE sprint_id = ?", sprintID)
		s.addItemEvent(sprintID, Item{Item: item, At: now(), Title: title, Status: "planned", Owner: "user",
			Position: s.positionAfter("item_state", sprintID, nil), Note: syncNote + kind + " " + url, Subgoal: subgoal})
		c.printf("item %d: %s\n", item, title)
	}
	var userItems []Item
	for _, i := range s.openItems(sprintID) {
		if i.Owner == "user" && !auto[i.Item] {
			userItems = append(userItems, i)
		}
	}
	for _, p := range board {
		url := key[p.URL]
		if url == "" {
			url = p.URL
		}
		if p.Group != "merge" || had["merge "+url] {
			continue
		}
		named := false
		re := mentionRE(p.URL, p.Number)
		for _, i := range userItems {
			named = named || re.MatchString(i.Title+" "+i.Note)
		}
		pr, ok := s.prLatest(sprintID, url)
		if named || !ok {
			continue
		}
		add("merge", url, fmt.Sprintf("Merge #%d: %s", p.Number, pr.Title), pr.Subgoal)
	}
	if s.int("SELECT COUNT(*) FROM subgoal_state WHERE sprint_id = ? AND status != 'dropped'", sprintID) == 0 {
		return
	}
	for _, pr := range s.unstagedPRs(sprintID) {
		if !had["stage "+pr.URL] {
			add("stage", pr.URL, fmt.Sprintf("Pick a stage for #%d: %s", prNumber(pr.URL), pr.Title), "")
		}
	}
}

// unstagedPRs are the open PRs with no subgoal, in a sprint that has stages.
func (s Store) unstagedPRs(sprintID int64) []PR {
	var out []PR
	s.each("SELECT "+prCols+" FROM pr_state p WHERE sprint_id = ? AND state IN ('opened', 'ready') AND subgoal IS NULL "+
		"AND EXISTS (SELECT 1 FROM subgoal_state g WHERE g.sprint_id = p.sprint_id AND g.status != 'dropped') ORDER BY at",
		[]any{sprintID}, func(r *sql.Rows) { out = append(out, scanPR(r)) })
	return out
}

// cmdPRSet moves a tracked PR to a subgoal, or to the whole sprint with -.
func cmdPRSet(c *call) {
	s := c.store
	sp := s.resolve(c.flag("sprint"))
	url := c.pos["url"]
	cur, ok := s.prLatest(sp.ID, url)
	if !ok {
		fail("%s is not in this sprint; run `sprint pr add` first", url)
	}
	subgoal := s.pickSubgoal(sp.ID, c.flag("subgoal"), true, false)
	if subgoal == cur.Subgoal {
		c.printf("%s: already there\n", url)
		return
	}
	s.exec("INSERT INTO pr_events (sprint_id, at, url, title, state, subgoal) VALUES (?, ?, ?, ?, ?, ?)",
		sp.ID, now(), url, cur.Title, cur.State, null(subgoal))
	if subgoal == "" {
		subgoal = wholeSprint
	}
	c.printf("%s: subgoal %s\n", url, subgoal)
}

// cmdPRIgnore adds, removes, or lists the patterns `pr sync` skips when it
// finds new PRs.
func cmdPRIgnore(c *call) {
	s := c.store
	sp := s.resolve(c.flag("sprint"))
	pattern, given := c.pos["pattern"]
	if !given {
		if c.has("rm") {
			fail("pr ignore: --rm needs a pattern")
		}
		for _, p := range s.strings("SELECT pattern FROM pr_ignore_state WHERE sprint_id = ? ORDER BY pattern", sp.ID) {
			c.printf("%s\n", p)
		}
		return
	}
	if _, err := regexp.Compile(pattern); err != nil {
		fail("bad pattern %q: %v", pattern, err)
	}
	active := !c.has("rm")
	if active == (s.int("SELECT COUNT(*) FROM pr_ignore_state WHERE sprint_id = ? AND pattern = ?", sp.ID, pattern) > 0) {
		c.printf("%s: unchanged\n", pattern)
		return
	}
	s.exec("INSERT INTO pr_ignores (sprint_id, at, pattern, active) VALUES (?, ?, ?, ?)", sp.ID, now(), pattern, active)
	if active {
		c.printf("%s: ignored\n", pattern)
	} else {
		c.printf("%s: removed\n", pattern)
	}
}
