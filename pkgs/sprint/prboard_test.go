package main

import (
	"fmt"
	"strings"
	"testing"
)

func stubStatus(t *testing.T, fn func(string) (prStatus, error)) {
	real := ghPRStatus
	ghPRStatus = fn
	t.Cleanup(func() { ghPRStatus = real })
}

func prURL(n int) string { return fmt.Sprintf("https://github.com/o/r/pull/%d", n) }

// clean is an open PR that is ready to merge: greptile 5/5 on its head,
// checks green, no threads.
func clean(n int, title string) prStatus {
	p := prStatus{Number: n, URL: prURL(n), Title: title, State: "OPEN", BaseRefName: "main",
		HeadRefName: fmt.Sprintf("b%d", n), HeadRefOid: fmt.Sprintf("%07d%s", n, strings.Repeat("a", 33)),
		Mergeable: "MERGEABLE"}
	p.Comments.Nodes = []botPost{greptile(5, p.HeadRefOid, "2026-11-04T01:00:00Z")}
	return p
}

func greptile(score int, commit, at string) botPost {
	return botPost{Author: &struct{ Login string }{"greptile-apps"}, UpdatedAt: at,
		Body: fmt.Sprintf("<h2>Confidence Score: %d/5</h2> Last reviewed commit: https://github.com/o/r/commit/%s", score, commit)}
}

func withChecks(p prStatus, nodes ...checkNode) prStatus {
	p.Commits.Nodes = make([]struct {
		Commit struct {
			StatusCheckRollup *struct {
				Contexts struct {
					Nodes []checkNode `json:"nodes"`
				} `json:"contexts"`
			} `json:"statusCheckRollup"`
		} `json:"commit"`
	}, 1)
	p.Commits.Nodes[0].Commit.StatusCheckRollup = &struct {
		Contexts struct {
			Nodes []checkNode `json:"nodes"`
		} `json:"contexts"`
	}{}
	p.Commits.Nodes[0].Commit.StatusCheckRollup.Contexts.Nodes = nodes
	return p
}

func boardOf(statuses []prStatus, items ...Item) map[int]*prReview {
	out := map[int]*prReview{}
	for _, p := range buildBoard(statuses, items) {
		out[p.Number] = p
	}
	return out
}

func TestBoardGroupsEachPRByWhatBlocksIt(t *testing.T) {
	failing := withChecks(clean(2, "b"), checkNode{Typename: "CheckRun", Name: "test", Status: "COMPLETED", Conclusion: "FAILURE"})
	draft := clean(3, "c")
	draft.IsDraft = true
	low := clean(4, "d")
	low.Comments.Nodes = []botPost{greptile(4, low.HeadRefOid, "2026-11-04T01:00:00Z")}
	old := clean(5, "e")
	old.Comments.Nodes = []botPost{greptile(5, "1234567", "2026-11-04T01:00:00Z")}
	threads := clean(6, "f")
	threads.ReviewThreads.Nodes = []struct {
		IsResolved bool `json:"isResolved"`
	}{{false}, {true}, {false}}
	unscored := clean(7, "g")
	unscored.Comments.Nodes = nil
	running := withChecks(clean(8, "h"), checkNode{Typename: "StatusContext", Context: "ci", State: "PENDING"})
	b := boardOf([]prStatus{clean(1, "a"), failing, draft, low, old, threads, unscored, running})
	got := func(n int) string { return b[n].Group + ": " + strings.Join(b[n].Steps, "; ") }
	eq(t, got(1), "merge: ")
	eq(t, got(2), "fix: Fails `test`")
	eq(t, got(3), "wait: Draft")
	eq(t, got(4), "fix: greptile scores 4/5")
	eq(t, got(5), "wait: greptile has not reviewed the newest commit")
	eq(t, got(6), "fix: 2 open review threads")
	eq(t, got(7), "wait: No review bot has scored it yet")
	eq(t, got(8), "wait: 1 check still running")
	eq(t, b[4].Bots[0], botScore{Name: "greptile", Score: 4, OnHead: true})
}

func TestBoardCountsOnlyTheNewestRunOfACheck(t *testing.T) {
	p := withChecks(clean(1, "a"),
		checkNode{Typename: "CheckRun", Name: "test", Status: "COMPLETED", Conclusion: "CANCELLED", StartedAt: "2026-11-04T01:00:00Z"},
		checkNode{Typename: "CheckRun", Name: "test", Status: "COMPLETED", Conclusion: "SUCCESS", StartedAt: "2026-11-04T02:00:00Z"})
	eq(t, boardOf([]prStatus{p})[1].Group, "merge")
}

func TestStackedPRWaitsForThePRBelowIt(t *testing.T) {
	base := clean(10, "base")
	top := clean(11, "top")
	top.BaseRefName = base.HeadRefName
	b := boardOf([]prStatus{top, base})
	eq(t, b[11].Group, "merge")
	eq(t, strings.Join(b[11].Steps, "; "), "Merge right after #10.")
	eq(t, b[10].Stack+", "+b[11].Stack, "stack 1 of 2, stack 2 of 2")
	eq(t, b[10].Rank < b[11].Rank, true)

	base.IsDraft = true
	b = boardOf([]prStatus{top, base})
	eq(t, b[11].Group+": "+strings.Join(b[11].Steps, "; "), "wait: Stacked: merge #10 first")
	// A base branch that no tracked PR owns is a wait of its own.
	lone := clean(12, "lone")
	lone.BaseRefName = "feature"
	eq(t, strings.Join(boardOf([]prStatus{lone})[12].Steps, "; "), "Based on `feature`, not main")
}

func TestReviewOrderPutsBlockersFirstAndToolingLast(t *testing.T) {
	items := []Item{{Item: 7, Title: "Blocker: rollout needs #22"}, {Item: 9, Title: "Ship it", Note: "after /pull/23 lands"}}
	b := buildBoard([]prStatus{clean(21, "docs: notes"), clean(20, "feat: x"), clean(23, "fix: y"), clean(22, "fix: z")}, items)
	var order []string
	for _, p := range b {
		order = append(order, fmt.Sprintf("#%d %s", p.Number, p.Why))
	}
	eq(t, strings.Join(order, " | "), "#22 Blocker (sprint item 7) | #23 On your sprint list (item 9) | "+
		"#20 Code or infra change | #21 Docs, tests or tooling")
}

func TestPRSyncLogsTheBoardWhenItChanges(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "One", "--goal", "g")
	statuses := map[string]prStatus{prURL(1): clean(1, "a"), prURL(2): clean(2, "b")}
	stubGH(t, func(url string) (prInfo, error) {
		s := statuses[url]
		return prInfo{Title: s.Title, URL: url, State: s.State, CreatedAt: "2026-11-02T10:00:00Z",
			MergedAt: map[bool]string{true: "2026-11-04T01:00:00Z"}[s.State == "MERGED"]}, nil
	})
	stubStatus(t, func(url string) (prStatus, error) { return statuses[url], nil })
	h.ok("pr", "add", prURL(1), prURL(2))
	contains_(t, h.ok("pr", "sync"), "PR board: 2 merge now, 0 fix first, 0 waiting")
	eq(t, h.query("SELECT number, grp, rank FROM pr_review_state ORDER BY rank"), "(1, merge, 1) (2, merge, 2)")
	h.ok("pr", "sync")
	eq(t, h.query("SELECT COUNT(*) FROM pr_reviews"), "(2)")

	h.clock(2000)
	draft := statuses[prURL(2)]
	draft.IsDraft = true
	statuses[prURL(2)] = draft
	h.ok("pr", "sync")
	eq(t, h.query("SELECT number, grp, steps, at FROM pr_review_state WHERE number = 2"), `(2, wait, ["Draft"], 2000)`)
	eq(t, h.query("SELECT COUNT(*) FROM pr_reviews"), "(3)")

	merged := statuses[prURL(1)]
	merged.State = "MERGED"
	statuses[prURL(1)] = merged
	contains_(t, h.ok("pr", "sync"), "PR board: 0 merge now, 0 fix first, 1 waiting")
	// The merged PR keeps its last row: the gate at merge.
	eq(t, h.query("SELECT grp FROM pr_review_state WHERE number = 1"), "(merge)")
	// #2 moved up to first, so it gets a new row.
	eq(t, h.query("SELECT rank FROM pr_review_state WHERE number = 2"), "(1)")
	eq(t, h.query("SELECT COUNT(*) FROM pr_reviews"), "(4)")
}

func TestPRSyncKeepsTheBoardWhenOneReviewStateFails(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "One", "--goal", "g")
	fakeGH(t, "OPEN", "", "", prURL(1))
	h.ok("pr", "add", prURL(1))
	stubStatus(t, func(url string) (prStatus, error) { return prStatus{}, fmt.Errorf("rate limited") })
	code, out, errOut := h.run("pr", "sync")
	eq(t, code, 0)
	contains_(t, errOut, "could not read the review state of "+prURL(1)+": rate limited")
	contains_(t, out, "PR board: 0 merge now")
}

func TestPRNoteIsKeptAndCanBeRemoved(t *testing.T) {
	h := newHarness(t)
	h.ok("start", "s1", "One", "--goal", "g")
	fakeGH(t, "OPEN", "", "", pr3)
	h.ok("pr", "add", pr3)
	h.ok("pr", "note", pr3, "First, run the capacity wizard.")
	eq(t, h.query("SELECT text FROM pr_note_state"), "(First, run the capacity wizard.)")
	h.ok("pr", "note", pr3, "-")
	eq(t, h.query("SELECT COUNT(*) FROM pr_note_state"), "(0)")
	contains_(t, h.fails("pr", "note", prURL(9), "x"), "not in this sprint")
}
