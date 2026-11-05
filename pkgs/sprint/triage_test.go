package main

import (
	"fmt"
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

	// A merge, a close, and a stage close the steps sync added.
	w.state(1, "MERGED")
	w.state(2, "CLOSED")
	h.ok("pr", "set", prURL(4), "--subgoal", "b")
	out = h.ok("pr", "sync")
	contains_(t, out, "done (PR merged)")
	contains_(t, out, "done (PR closed)")
	contains_(t, out, "done (PR moved to b)")
	eq(t, doNow(), "(Land #3 after the deploy, a)")
	eq(t, h.query("SELECT COUNT(*) FROM item_state WHERE status = 'done'"), "(3)")

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
