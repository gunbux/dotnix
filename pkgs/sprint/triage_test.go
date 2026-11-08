package main

import (
	"fmt"
	"strings"
	"testing"
)

// world fakes GitHub for triage tests: every PR's state and review state,
// and which ones are the user's.
type world struct {
	prs  map[string]prStatus
	mine []string
}

func newWorld(t *testing.T) *world {
	w := &world{prs: map[string]prStatus{}}
	stubGH(t, func(url string) (prInfo, error) {
		s, ok := w.prs[url]
		if !ok {
			return prInfo{}, fmt.Errorf("no PR %s", url)
		}
		return prInfo{Title: s.Title, URL: url, State: s.State, CreatedAt: "2026-11-02T10:00:00Z",
			MergedAt: map[bool]string{true: "2026-11-04T01:00:00Z"}[s.State == "MERGED"],
			ClosedAt: map[bool]string{true: "2026-11-04T01:00:00Z"}[s.State == "CLOSED"]}, nil
	})
	stubStatus(t, func(url string) (prStatus, error) { return w.prs[url], nil })
	stubMine(t, func(repo string) ([]openPR, error) {
		var out []openPR
		for _, u := range w.mine {
			if s := w.prs[u]; repoOf(u) == repo && s.State == "OPEN" {
				out = append(out, openPR{URL: u, Title: s.Title, State: "OPEN", CreatedAt: "2026-11-03T10:00:00Z",
					HeadRefName: s.HeadRefName})
			}
		}
		return out, nil
	})
	return w
}

// waiting is an open PR no bot has scored: it is not ready to merge.
func waiting(n int, title string) prStatus {
	p := clean(n, title)
	p.Comments.Nodes = nil
	return p
}

func (w *world) set(p prStatus) { w.prs[p.URL] = p }

func (w *world) state(n int, state string) {
	p := w.prs[prURL(n)]
	p.State = state
	w.prs[prURL(n)] = p
}

func stagedSprint(t *testing.T) *harness {
	h := newHarness(t)
	h.ok("start", "s1", "One", "--goal", "g")
	h.ok("sub", "add", "a", "Stage A", "--goal", "ga", "--status", "active")
	h.ok("sub", "add", "b", "Stage B", "--goal", "gb")
	return h
}

func TestPRSetMovesATrackedPR(t *testing.T) {
	h := stagedSprint(t)
	w := newWorld(t)
	w.set(waiting(1, "feat: one"))
	h.ok("pr", "add", prURL(1), "--subgoal", "-")
	eq(t, h.query("SELECT COALESCE(subgoal, '-') FROM pr_state"), "(-)")

	h.clock(2000)
	contains_(t, h.ok("pr", "set", prURL(1), "--subgoal", "b"), "subgoal b")
	eq(t, h.query("SELECT title, state, subgoal, at FROM pr_state"), "(feat: one, opened, b, 2000)")
	// The log keeps both rows.
	eq(t, h.query("SELECT COUNT(*) FROM pr_events"), "(2)")
	eq(t, h.query("SELECT text FROM activity WHERE kind = 'pr' ORDER BY id DESC LIMIT 1"), "(PR moved to Stage B: feat: one)")
	contains_(t, h.ok("pr", "set", prURL(1), "--subgoal", "b"), "already there")
	eq(t, h.query("SELECT COUNT(*) FROM pr_events"), "(2)")

	// A sync keeps the new subgoal.
	h.ok("pr", "sync")
	eq(t, h.query("SELECT subgoal FROM pr_state"), "(b)")

	h.ok("pr", "set", prURL(1), "--subgoal", "-")
	eq(t, h.query("SELECT COALESCE(subgoal, '-') FROM pr_state"), "(-)")
	eq(t, h.query("SELECT text FROM activity WHERE kind = 'pr' ORDER BY id DESC LIMIT 1"),
		"(PR moved to the whole sprint: feat: one)")

	contains_(t, h.fails("pr", "set", prURL(1), "--subgoal", "nope"), `no subgoal "nope"`)
	contains_(t, h.fails("pr", "set", prURL(9), "--subgoal", "a"), "not in this sprint")
	contains_(t, h.fails("pr", "set", prURL(1)), "--subgoal is required")
}

func TestPRSyncFindsTheUsersOpenPRs(t *testing.T) {
	h := stagedSprint(t)
	w := newWorld(t)
	w.set(waiting(1, "feat: tracked"))
	h.ok("pr", "add", prURL(1), "--subgoal", "a")
	w.set(waiting(2, "feat: new"))
	w.set(waiting(3, "chore: scratch"))
	p4 := waiting(4, "wip")
	p4.HeadRefName = "tmp/experiment"
	w.set(p4)
	// Another repository: no PR of the sprint lives there.
	other := waiting(5, "elsewhere")
	other.URL = "https://github.com/o/other/pull/5"
	w.set(other)
	w.mine = []string{prURL(1), prURL(2), prURL(3), prURL(4), other.URL}

	h.ok("pr", "ignore", "^chore")
	h.ok("pr", "ignore", "^tmp/")
	eq(t, h.ok("pr", "ignore"), "^chore\n^tmp/\n")
	contains_(t, h.fails("pr", "ignore", "("), "bad pattern")

	out := h.ok("pr", "sync")
	contains_(t, out, prURL(2)+": found open, added with no stage: feat: new")
	eq(t, h.query("SELECT url, COALESCE(subgoal, '-') FROM pr_state ORDER BY url"),
		"("+prURL(1)+", a) ("+prURL(2)+", -)")
	// The found PR is on the board at once.
	eq(t, h.query("SELECT number FROM pr_review_state ORDER BY number"), "(1) (2)")

	// Removing a pattern lets the next sync find that PR.
	h.ok("pr", "ignore", "^chore", "--rm")
	eq(t, h.ok("pr", "ignore"), "^tmp/\n")
	contains_(t, h.ok("pr", "sync"), prURL(3)+": found open")
	eq(t, h.query("SELECT COUNT(*) FROM pr_state"), "(3)")
}

func TestPRSyncSkipsPRsAnotherOpenSprintTracks(t *testing.T) {
	h := newHarness(t)
	w := newWorld(t)
	w.set(waiting(1, "one"))
	w.set(waiting(2, "two"))
	w.mine = []string{prURL(1), prURL(2)}
	h.ok("start", "s1", "One", "--goal", "g")
	h.ok("start", "s2", "Two", "--goal", "g")
	h.ok("--sprint", "s1", "pr", "add", prURL(1))
	h.ok("--sprint", "s2", "pr", "add", prURL(2))
	h.ok("--sprint", "s1", "pr", "sync")
	eq(t, h.query("SELECT COUNT(*) FROM pr_events WHERE url = ?", prURL(2)), "(1)")
}

func TestPRSyncCountsAFailedSearch(t *testing.T) {
	h := newHarness(t)
	w := newWorld(t)
	h.ok("start", "s1", "One", "--goal", "g")
	w.set(clean(1, "one"))
	h.ok("pr", "add", prURL(1))
	stubMine(t, func(string) ([]openPR, error) { return nil, fmt.Errorf("rate limited") })
	code, out, errOut := h.run("pr", "sync")
	eq(t, code, 0)
	contains_(t, errOut, "could not list your open PRs in o/r: rate limited")
	contains_(t, out, "PR board: 1 merge now")
	eq(t, h.query("SELECT COUNT(*) FROM pr_syncs"), "(0)")
}

func TestPRSyncKeepsDoNowCoveringPRs(t *testing.T) {
	h := stagedSprint(t)
	w := newWorld(t)
	w.set(clean(1, "feat: ready"))
	w.set(waiting(2, "feat: not ready"))
	w.set(clean(3, "feat: named"))
	w.set(waiting(4, "feat: found"))
	w.mine = []string{prURL(4)}
	h.ok("pr", "add", prURL(1), prURL(2), prURL(3), "--subgoal", "a")
	h.ok("item", "add", "Land #3 after the deploy", "--owner", "user", "--subgoal", "a")

	out := h.ok("pr", "sync")
	contains_(t, out, "Merge #1: feat: ready")
	contains_(t, out, "Pick a stage for #4: feat: found")
	doNow := func() string {
		return h.query("SELECT title, COALESCE(subgoal, '-') FROM do_now ORDER BY rank")
	}
	eq(t, doNow(), "(Pick a stage for #4: feat: found, -) (Land #3 after the deploy, a) (Merge #1: feat: ready, a)")
	// The steps sync adds don't move their PR up the review order.
	eq(t, h.query("SELECT why FROM pr_review_state WHERE number = 1"), "(Code or infra change)")

	// Idempotent: a second sync adds nothing.
	n := h.query("SELECT COUNT(*) FROM item_events")
	out = h.ok("pr", "sync")
	eq(t, h.query("SELECT COUNT(*) FROM item_events"), n)
	eq(t, doNow(), "(Pick a stage for #4: feat: found, -) (Land #3 after the deploy, a) (Merge #1: feat: ready, a)")

	// The user edits the step (a new event with no note); sync still knows it.
	h.ok("item", "set", "2", "doing")
	h.ok("pr", "sync")
	eq(t, h.query("SELECT COUNT(*) FROM item_events"), "(4)")

	// A PR that gets ready later gets its step then.
	w.set(clean(2, "feat: not ready"))
	contains_(t, h.ok("pr", "sync"), "Merge #2: feat: not ready")

	// The Merge steps sync adds merge their PR.
	eq(t, h.query("SELECT item, merges FROM item_state WHERE merges IS NOT NULL ORDER BY item"),
		"(2, "+prURL(1)+") (4, "+prURL(2)+")")

	// A merge, a close, and a stage close the steps sync added.
	w.state(1, "MERGED")
	w.state(2, "CLOSED")
	h.ok("pr", "set", prURL(4), "--subgoal", "b")
	out = h.ok("pr", "sync")
	contains_(t, out, "item 2: done: Merged Wed 4 Nov 09:00 SGT (pr sync)")
	contains_(t, out, "item 4: dropped: #2 closed without merging (pr sync)")
	contains_(t, out, "item 3: done (PR moved to b)")
	eq(t, doNow(), "(Land #3 after the deploy, a)")
	eq(t, h.query("SELECT item, status FROM item_state WHERE item IN (2, 3, 4) ORDER BY item"),
		"(2, done) (3, done) (4, dropped)")

	// Steps the user closed stay closed, and none come back.
	n = h.query("SELECT COUNT(*) FROM item_events")
	h.ok("pr", "sync")
	eq(t, h.query("SELECT COUNT(*) FROM item_events"), n)
}

func TestPickAStageNeedsStages(t *testing.T) {
	h := newHarness(t)
	w := newWorld(t)
	h.ok("start", "s1", "One", "--goal", "g")
	w.set(waiting(1, "one"))
	h.ok("pr", "add", prURL(1))
	h.ok("pr", "sync")
	eq(t, h.query("SELECT COUNT(*) FROM item_events"), "(0)")
	eq(t, len(h.show().NeedsStage), 0)

	h.ok("sub", "add", "a", "Stage A", "--goal", "ga")
	contains_(t, h.ok("show"), "Needs a stage")
	s := h.show()
	eq(t, len(s.NeedsStage), 1)
	eq(t, s.NeedsStage[0].URL, prURL(1))
	h.ok("pr", "sync")
	eq(t, h.query("SELECT title FROM do_now"), "(Pick a stage for #1: one)")

	// Dropping the step leaves it dropped.
	h.ok("item", "set", "1", "dropped")
	h.ok("pr", "sync")
	eq(t, h.query("SELECT COUNT(*) FROM do_now"), "(0)")
}

func TestPRSyncLinksEachStepThatMergesOnePR(t *testing.T) {
	h := newHarness(t)
	w := newWorld(t)
	h.ok("start", "s1", "One", "--goal", "g")
	w.set(clean(1, "feat: one"))
	w.set(waiting(2, "feat: two"))
	w.set(waiting(3, "feat: three"))
	w.set(clean(4, "fix: hotfix"))
	h.ok("pr", "add", prURL(1), prURL(2), prURL(3), prURL(4))
	steps := []struct{ title, want string }{
		{"Merge #1 (feat: one; both bots 5/5)", prURL(1)},
		{"After a code owner approves #2: merge #2 (ships off)", prURL(2)},
		{"After #1 merges: merge #3", prURL(3)},
		{"After #1 merges: ask James to pin the image", "-"},
		{"Merge #1, #2, #3 in order, one at a time", "-"},
		{"Merge #3 after #2", "-"},
		{"Merge https://github.com/o/r/pull/2 once #99 lands", prURL(2)},
		{"Apply the plan before merging #3", "-"},
	}
	for _, st := range steps {
		h.ok("item", "add", st.title, "--owner", "user")
	}
	h.ok("item", "set", "1", "--note", "`gh pr merge 1`")
	h.ok("item", "add", "Merge #1 (the agent's own check)")
	h.ok("item", "add", "Merge #1 when the deploy ends", "--owner", "user", "--merges", "#3", "--note", "keep me")
	h.ok("item", "add", "Land the hotfix", "--owner", "user", "--merges", "#4")
	merges := func() string {
		return h.query("SELECT item, COALESCE(merges, '-') FROM item_state ORDER BY item")
	}

	out := h.ok("pr", "sync")
	var want []string
	for k, st := range steps {
		want = append(want, fmt.Sprintf("(%d, %s)", k+1, st.want))
	}
	eq(t, merges(), strings.Join(want, " ")+" (9, -) (10, "+prURL(3)+") (11, "+prURL(4)+")")
	contains_(t, out, "item 3: merges #3\n")
	// A link keeps the step's note.
	eq(t, h.query("SELECT note FROM item_state WHERE item IN (1, 10) ORDER BY item"), "(`gh pr merge 1`) (keep me)")
	// #1 and #4 are ready to merge, and steps 1 and 11 merge them: sync
	// adds no Merge step.
	if strings.Contains(out, "Merge #1:") || strings.Contains(out, "Merge #4:") {
		t.Fatalf("added a second Merge step:\n%s", out)
	}

	n := h.query("SELECT COUNT(*) FROM item_events")
	h.ok("pr", "sync")
	eq(t, h.query("SELECT COUNT(*) FROM item_events"), n)
}

func TestPRSyncClosesALinkedStepOnceItsPRMergesOrCloses(t *testing.T) {
	h := newHarness(t)
	w := newWorld(t)
	h.ok("start", "s1", "One", "--goal", "g")
	for n := 1; n <= 3; n++ {
		w.set(waiting(n, fmt.Sprintf("feat: %d", n)))
		h.ok("pr", "add", prURL(n))
	}
	h.ok("item", "add", "Merge #1", "--owner", "user")
	h.ok("item", "add", "Land the second one", "--owner", "user", "--merges", "#2", "--waits-on", "James")
	h.ok("item", "add", "Merge #3", "--owner", "user")
	h.ok("pr", "sync")
	state := func() string {
		return h.query("SELECT item, status, COALESCE(note, '-') FROM item_state ORDER BY item")
	}
	eq(t, state(), "(1, planned, -) (2, planned, -) (3, planned, -)")

	w.state(1, "MERGED")
	w.state(2, "CLOSED")
	h.clock(2000)
	out := h.ok("pr", "sync")
	contains_(t, out, "item 1: done: Merged Wed 4 Nov 09:00 SGT (pr sync)\n")
	contains_(t, out, "item 2: dropped: #2 closed without merging (pr sync)\n")
	eq(t, state(), "(1, done, Merged Wed 4 Nov 09:00 SGT (pr sync)) "+
		"(2, dropped, #2 closed without merging (pr sync)) (3, planned, -)")
	eq(t, h.query("SELECT COUNT(*) FROM do_now"), "(1)")

	n := h.query("SELECT COUNT(*) FROM item_events")
	h.ok("pr", "sync")
	eq(t, h.query("SELECT COUNT(*) FROM item_events"), n)

	// A step that names a PR merged before the step was linked closes in the
	// same sync.
	h.ok("item", "add", "Merge #1 again", "--owner", "user")
	out = h.ok("pr", "sync")
	contains_(t, out, "item 4: merges #1\nitem 4: done: Merged")
}

func TestPRSyncLinksAMergeStepItAddedBeforeLinks(t *testing.T) {
	h := newHarness(t)
	w := newWorld(t)
	h.ok("start", "s1", "One", "--goal", "g")
	// The PR's title names another PR after the word "merge", so the title
	// alone would not link the step.
	w.set(clean(1, "fix: merge rules after #2"))
	w.set(waiting(2, "feat: two"))
	h.ok("pr", "add", prURL(1), prURL(2))
	h.ok("item", "add", "Merge #1: fix: merge rules after #2", "--owner", "user",
		"--note", syncNote+"merge "+prURL(1))
	contains_(t, h.ok("pr", "sync"), "item 1: merges #1")
	w.state(1, "MERGED")
	contains_(t, h.ok("pr", "sync"), "item 1: done: Merged")
}

func TestAMergeStepWaitsWhileGitHubBlocksTheMerge(t *testing.T) {
	h := newHarness(t)
	w := newWorld(t)
	h.ok("start", "s1", "One", "--goal", "g")
	blocked := withChecks(clean(1, "feat: one"), checkNode{Typename: "StatusContext", Context: "ci", State: "PENDING"})
	blocked.ReviewDecision = "REVIEW_REQUIRED"
	w.set(blocked)
	w.set(clean(2, "feat: two"))
	h.ok("pr", "add", prURL(1), prURL(2))
	h.ok("item", "add", "ask James to review", "--owner", "user")
	h.ok("item", "add", "Merge #1", "--owner", "user")
	h.ok("item", "add", "Land #2", "--owner", "user", "--merges", "#2")
	h.ok("item", "add", "Land #1 when James is back", "--owner", "user", "--merges", "#1", "--waits-on", "James")
	h.ok("item", "add", "Land #1 after the review", "--owner", "user", "--merges", "#1", "--needs", "1")
	doNow := func() string {
		return h.query("SELECT rank, item, state, COALESCE(pr, '-'), COALESCE(gate, '-'), COALESCE(since, '-') " +
			"FROM do_now ORDER BY rank")
	}
	// No board row yet: a merge step is ready.
	eq(t, h.query("SELECT item, state, COALESCE(pr, '-') FROM do_now WHERE item IN (2, 3) ORDER BY item"),
		"(2, ready, -) (3, ready, 2)")

	h.clock(2000)
	h.ok("pr", "sync")
	gate := "1 check still running; Needs an approval"
	eq(t, doNow(), "(1, 1, ready, -, -, -) (2, 3, ready, 2, -, -) "+
		"(3, 2, waiting, 1, "+gate+", 2000) (4, 4, waiting, 1, -, 1000) (5, 5, later, 1, -, -)")
	out := h.ok("show")
	contains_(t, out, "  3. Merge #1 [waiting: GitHub: "+gate+"]\n")
	contains_(t, out, "  4. Land #1 when James is back [waiting on James]\n")
	contains_(t, out, "  5. Land #1 after the review [after #1]\n")
	eq(t, h.show().DoNow[2].Gate, any(gate))
	eq(t, h.query("SELECT item, state, merges, pr, gate, at FROM timeline WHERE item = 2"),
		"(2, waiting, "+prURL(1)+", 1, "+gate+", 2000)")

	// Still blocked, for another reason: it has waited since the first.
	w.set(withChecks(blocked))
	h.clock(3000)
	h.ok("pr", "sync")
	eq(t, h.query("SELECT gate, since FROM do_now WHERE item = 2"), "(Needs an approval, 2000)")

	// Merge now, then blocked again: it waits from then.
	w.set(clean(1, "feat: one"))
	h.clock(4000)
	h.ok("pr", "sync")
	eq(t, h.query("SELECT state, gate, since FROM do_now WHERE item = 2"), "(ready, <nil>, <nil>)")
	w.set(blocked)
	h.clock(5000)
	h.ok("pr", "sync")
	eq(t, h.query("SELECT state, since FROM do_now WHERE item = 2"), "(waiting, 5000)")

	// The needed step done, the GitHub gate decides.
	h.ok("item", "set", "1", "done")
	eq(t, h.query("SELECT state, gate FROM do_now WHERE item = 5"), "(waiting, "+gate+")")
}
