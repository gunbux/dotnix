// Command t3-activity prints T3 Code agent activity as JSON, like the phone's
// Live Activity. It backs the chun/t3-activity Noctalia plugin.
//
// It reads T3's projection database read-only, so it needs no token and works
// while the app is closed. Phases mirror the server's projectThreadAwarenessV2:
// waiting_for_input, waiting_for_approval, starting, running, completed, failed.
// Threads made by agents (subagents, launched threads) are left out unless
// they wait on you. With --relay it adds the other machines' threads from
// T3 Connect (relay.go).
package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

var urgency = map[string]int{
	"waiting_for_input":    0,
	"waiting_for_approval": 1,
	"failed":               2,
	"running":              3,
	"starting":             4,
	"completed":            5,
}

type thread struct {
	ID      string  `json:"id"`
	Title   string  `json:"title"`
	Project string  `json:"project"`
	Phase   string  `json:"phase"`
	Model   string  `json:"model"`
	Branch  string  `json:"branch"`
	Machine string  `json:"machine"`
	Since   float64 `json:"since"`
	Updated float64 `json:"updated"`
	URL     string  `json:"url"`
}

type output struct {
	OK      bool     `json:"ok"`
	Machine string   `json:"machine"`
	Error   string   `json:"error,omitempty"`
	Threads []thread `json:"threads"`
	// Connect is the T3 Connect fetch, present with --relay.
	Connect *relayStatus `json:"connect,omitempty"`
}

type run struct {
	status      string
	requestedAt string
	completedAt string
}

type project struct {
	title string
	root  string
}

type request struct {
	kind     string
	blocking bool
}

type threadPayload struct {
	CreatedBy string `json:"createdBy"`
	Lineage   struct {
		RelationshipToParent *string `json:"relationshipToParent"`
	} `json:"lineage"`
	SettledOverride *string `json:"settledOverride"`
	Branch          *string `json:"branch"`
	WorktreePath    *string `json:"worktreePath"`
	LastVisitedAt   *string `json:"lastVisitedAt"`
	UpdatedAt       *string `json:"updatedAt"`
	ModelSelection  struct {
		Model string `json:"model"`
	} `json:"modelSelection"`
}

func live(status string) bool {
	switch status {
	case "preparing", "starting", "running", "waiting":
		return true
	}
	return false
}

func epoch(value *string) float64 {
	if value == nil || *value == "" {
		return 0
	}
	t, err := time.Parse(time.RFC3339Nano, *value)
	if err != nil {
		return 0
	}
	return float64(t.UnixMilli()) / 1000
}

func main() {
	home := flag.String("home", envOr("T3CODE_HOME", "~/.t3"), "T3 Code data directory")
	window := flag.Int("finished-window", 30, "minutes to keep finished and failed threads")
	relay := flag.Bool("relay", false, "add other machines' threads from T3 Connect")
	relayInterval := flag.Int("relay-interval", 10, "seconds between T3 Connect fetches")
	seenID := flag.String("seen", "", "mark a thread opened from the pill, then exit")
	clear := flag.Bool("clear-done", false, "hide every finished and failed thread so far, then exit")
	flag.Parse()

	if *seenID != "" {
		markSeen(*seenID)
		return
	}
	if *clear {
		writeRuntime("cleared.json", time.Now().UTC().Format(time.RFC3339Nano))
		return
	}
	cleared := clearedAt()

	userdata := filepath.Join(expand(*home), "userdata")
	envID := ""
	if raw, err := os.ReadFile(filepath.Join(userdata, "environment-id")); err == nil {
		envID = strings.TrimSpace(string(raw))
	}
	machine, _ := os.Hostname()

	threads, err := collect(userdata, envID, time.Duration(*window)*time.Minute, cleared)
	out := output{OK: err == nil, Machine: machine, Threads: threads}
	if err != nil {
		out.Error = err.Error()
		out.Threads = []thread{}
	}
	for i := range out.Threads {
		out.Threads[i].Machine = machine
	}

	if *relay {
		rows, labels, status := relayActivity(userdata, time.Duration(*relayInterval)*time.Second)
		seen := loadSeen(rows)
		now := float64(time.Now().UnixMilli()) / 1000
		out.Connect = &status
		if label := labels[envID]; label != "" {
			out.Machine = label
			for i := range out.Threads {
				out.Threads[i].Machine = label
			}
		}
		for _, row := range rows {
			// This machine's rows come from its database, with more detail.
			if row.EnvironmentID == envID {
				continue
			}
			label := labels[row.EnvironmentID]
			if label == "" {
				label = "remote"
			}
			updated := epoch(&row.UpdatedAt)
			// The relay has no lineage; agent-made threads show by their ids.
			if agentThreadID(row.ThreadID) && !needsUser(row.Phase) {
				continue
			}
			// The relay keeps finished threads until they are settled; opening
			// one is invisible to it. Drop them once opened from the pill,
			// cleared, or, like local ones, older than the window.
			if row.Phase == "completed" || row.Phase == "failed" {
				if seen[row.ThreadID] == row.UpdatedAt || updated <= cleared || now-updated >= float64(*window*60) {
					continue
				}
			}
			out.Threads = append(out.Threads, thread{
				ID:      row.ThreadID,
				Title:   row.ThreadTitle,
				Project: row.ProjectTitle,
				Phase:   row.Phase,
				Model:   row.ModelTitle,
				Machine: label,
				Updated: updated,
				URL:     "t3code:/" + row.DeepLink,
			})
		}
		sortThreads(out.Threads)
	}
	json.NewEncoder(os.Stdout).Encode(out)
}

// clearedAt is when "Clear done" was last pressed, in epoch seconds.
func clearedAt() float64 {
	var at string
	if raw, err := os.ReadFile(runtimePath("cleared.json")); err == nil {
		json.Unmarshal(raw, &at)
	}
	return epoch(&at)
}

func needsUser(phase string) bool {
	return phase == "waiting_for_input" || phase == "waiting_for_approval"
}

// agentThreadID matches threads made by delegate_task (subagents) and
// t3_thread_launch, as the relay names them.
func agentThreadID(id string) bool {
	return strings.HasPrefix(id, "thread:delegated-task:") || strings.HasPrefix(id, "mcp:launch:")
}

func sortThreads(threads []thread) {
	sort.SliceStable(threads, func(i, j int) bool {
		if urgency[threads[i].Phase] != urgency[threads[j].Phase] {
			return urgency[threads[i].Phase] < urgency[threads[j].Phase]
		}
		return threads[i].Updated > threads[j].Updated
	})
}

func collect(userdata, envID string, window time.Duration, cleared float64) ([]thread, error) {
	dbPath := filepath.Join(userdata, "statev2.sqlite")
	if _, err := os.Stat(dbPath); err != nil {
		return nil, fmt.Errorf("no T3 database at %s", dbPath)
	}

	dsn := (&url.URL{Scheme: "file", Path: dbPath, RawQuery: "mode=ro&_pragma=busy_timeout(2000)"}).String()
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	defer db.Close()

	projects := map[string]project{}
	rows, err := db.Query(`select project_id, title, workspace_root from projection_projects`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var id string
		var p project
		if rows.Scan(&id, &p.title, &p.root) == nil {
			projects[id] = p
		}
	}
	rows.Close()

	// Latest live run per thread wins; otherwise the latest run of any status.
	runs := map[string]run{}
	rows, err = db.Query(`select thread_id, status, requested_at, coalesce(completed_at, '')
		from orchestration_v2_projection_runs order by ordinal`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var id string
		var r run
		if rows.Scan(&id, &r.status, &r.requestedAt, &r.completedAt) != nil {
			continue
		}
		if prev, ok := runs[id]; !ok || live(r.status) || !live(prev.status) {
			runs[id] = r
		}
	}
	rows.Close()

	pending := map[string]request{}
	rows, err = db.Query(`select thread_id, kind, payload_json
		from orchestration_v2_projection_runtime_requests
		where status = 'pending' order by created_at`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var id, kind, payload string
		if rows.Scan(&id, &kind, &payload) != nil {
			continue
		}
		var p struct {
			ResponseCapability struct {
				Type string `json:"type"`
			} `json:"responseCapability"`
		}
		json.Unmarshal([]byte(payload), &p)
		pending[id] = request{kind: kind, blocking: p.ResponseCapability.Type != "message"}
	}
	rows.Close()

	now := float64(time.Now().UnixMilli()) / 1000
	out := []thread{}
	rows, err = db.Query(`select thread_id, project_id, coalesce(title, ''), payload_json
		from orchestration_v2_projection_threads
		where archived_at is null and deleted_at is null`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id, projectID, title, payload string
		if rows.Scan(&id, &projectID, &title, &payload) != nil {
			continue
		}
		r, hasRun := runs[id]
		req, hasReq := pending[id]
		if !hasRun && !hasReq {
			continue
		}
		var p threadPayload
		json.Unmarshal([]byte(payload), &p)
		// Subagents and threads other agents launched report to their parent
		// agent, so they only show while they wait on you.
		rel := p.Lineage.RelationshipToParent
		byAgent := p.CreatedBy == "agent" || (rel != nil && *rel == "subagent") || agentThreadID(id)

		phase := ""
		switch {
		case hasReq && req.kind == "user_input" && (req.blocking || !live(r.status)):
			phase = "waiting_for_input"
		case hasReq && req.kind != "user_input" && req.kind != "auth_refresh":
			phase = "waiting_for_approval"
		case r.status == "preparing" || r.status == "starting":
			phase = "starting"
		case r.status == "running" || r.status == "waiting":
			phase = "running"
		case r.status == "completed" || r.status == "failed":
			// The phone keeps these until dismissed; here they clear once the
			// thread is opened, settled, cleared, or older than the window.
			done := epoch(&r.completedAt)
			settled := p.SettledOverride != nil && *p.SettledOverride == "settled"
			if !settled && now-done < window.Seconds() && epoch(p.LastVisitedAt) < done && done > cleared {
				phase = r.status
			}
		}
		if phase == "" || (byAgent && !needsUser(phase)) {
			continue
		}

		if title == "" {
			title = "Untitled thread"
		}
		proj := projects[projectID]
		branch := ""
		if p.Branch != nil {
			branch = *p.Branch
		} else if p.WorktreePath != nil {
			branch = gitBranch(*p.WorktreePath)
		} else {
			branch = gitBranch(proj.root)
		}
		t := thread{
			ID:      id,
			Title:   title,
			Project: proj.title,
			Phase:   phase,
			Model:   p.ModelSelection.Model,
			Branch:  branch,
			Since:   epoch(&r.requestedAt),
			Updated: epoch(p.UpdatedAt),
		}
		if envID != "" {
			t.URL = "t3code://threads/" + envID + "/" + id
		}
		out = append(out, t)
	}

	sortThreads(out)
	return out, rows.Err()
}

// gitBranch reads the checked-out branch of the repo at dir from .git/HEAD,
// following a worktree's .git file. It returns "" outside a repo or when the
// HEAD is detached.
func gitBranch(dir string) string {
	if dir == "" {
		return ""
	}
	gitDir := filepath.Join(dir, ".git")
	if raw, err := os.ReadFile(gitDir); err == nil {
		target := strings.TrimSpace(strings.TrimPrefix(string(raw), "gitdir:"))
		if !filepath.IsAbs(target) {
			target = filepath.Join(dir, target)
		}
		gitDir = target
	}
	head, err := os.ReadFile(filepath.Join(gitDir, "HEAD"))
	if err != nil {
		return ""
	}
	ref, ok := strings.CutPrefix(strings.TrimSpace(string(head)), "ref: refs/heads/")
	if !ok {
		return ""
	}
	return ref
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func expand(path string) string {
	if path == "~" || strings.HasPrefix(path, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, strings.TrimPrefix(path, "~"))
		}
	}
	return path
}
