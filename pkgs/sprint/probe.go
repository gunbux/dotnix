package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"strings"
)

// Stock commands for `sprint poll`. Each prints the poll output format
// (Markdown, or JSON with body and progress) and ends with exit 100 when the
// thing it watches is done. A failure exits 1 with the reason on stderr.
//
//   sprint poll ci --every 60s --title "CI" -- sprint probe gh-run <run url>
//   sprint poll review --every 2m --title "Review" -- sprint probe greptile <pr url>
//   sprint poll bench --every 30s --title "Bench" -- sprint probe tail <file> --until 'DONE'

// probeDone is how a probe says "done": run() turns it into exit 100.
type probeDone struct{}

func emit(c *call, v any) {
	b, err := json.Marshal(v)
	check(err)
	c.printf("%s\n", b)
}

func ghJSON(args ...string) ([]byte, error) {
	out, err := exec.Command("gh", args...).Output()
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		return nil, fmt.Errorf("%s", strings.TrimSpace(string(ee.Stderr)))
	}
	return out, err
}

var runURLRE = regexp.MustCompile(`github\.com/([^/]+/[^/]+)/actions/runs/(\d+)`)

func cmdProbeGHRun(c *call) {
	run, repo := c.pos["run"], c.flag("repo")
	if m := runURLRE.FindStringSubmatch(run); m != nil {
		repo, run = m[1], m[2]
	}
	args := []string{"run", "view", run, "--json", "status,conclusion,displayTitle,workflowName,url,jobs"}
	if repo != "" {
		args = append(args, "--repo", repo)
	}
	out, err := ghJSON(args...)
	if err != nil {
		fail("gh run view: %v", err)
	}
	var r struct {
		Status, Conclusion, DisplayTitle, WorkflowName, URL string
		Jobs                                                []struct{ Name, Status, Conclusion string }
	}
	check(json.Unmarshal(out, &r))
	var b strings.Builder
	state := strings.ToLower(r.Status)
	if r.Conclusion != "" {
		state = strings.ToLower(r.Conclusion)
	}
	fmt.Fprintf(&b, "**%s**: [%s](%s), %s\n\n", r.WorkflowName, r.DisplayTitle, r.URL, state)
	done := 0
	if len(r.Jobs) > 0 {
		b.WriteString("| Job | State |\n|---|---|\n")
	}
	for _, j := range r.Jobs {
		js := strings.ToLower(j.Status)
		if j.Status == "completed" || j.Status == "COMPLETED" {
			done++
			js = strings.ToLower(j.Conclusion)
		}
		fmt.Fprintf(&b, "| %s | %s |\n", strings.ReplaceAll(j.Name, "|", "/"), js)
	}
	res := map[string]any{"body": b.String(), "link": r.URL}
	if len(r.Jobs) > 0 {
		res["progress"] = fmt.Sprintf("%d/%d", done, len(r.Jobs))
	}
	emit(c, res)
	if strings.EqualFold(r.Status, "completed") {
		panic(probeDone{})
	}
}

func cmdProbeGreptile(c *call) {
	p, err := ghPRStatus(c.pos["pr"])
	if err != nil {
		fail("%v", err)
	}
	until := c.flag("until")
	if until == "" {
		until = "reviewed"
	}
	head := p.HeadRefOid
	if len(head) > 7 {
		head = head[:7]
	}
	var b strings.Builder
	fmt.Fprintf(&b, "[#%d %s](%s), head `%s`, %s\n\n", p.Number, p.Title, p.URL, head, strings.ToLower(p.State))
	scores := p.scores()
	reviewed, five := len(scores) > 0, len(scores) > 0
	for _, s := range scores {
		switch {
		case s.Score < 0:
			fmt.Fprintf(&b, "- %s: no score yet\n", s.Name)
		case s.OnHead:
			fmt.Fprintf(&b, "- %s: **%d/5** on the head commit\n", s.Name, s.Score)
		default:
			fmt.Fprintf(&b, "- %s: %d/5 on an older commit; the head is not reviewed yet\n", s.Name, s.Score)
		}
		reviewed = reviewed && s.OnHead
		five = five && s.OnHead && s.Score == 5
	}
	if len(scores) == 0 {
		b.WriteString("- No review bot has posted yet.\n")
	}
	threads, allRead := p.openThreads(), !p.ReviewThreads.PageInfo.HasNextPage
	if allRead {
		fmt.Fprintf(&b, "- %d open review threads\n", threads)
	} else {
		fmt.Fprintf(&b, "- %d or more open review threads (over 100 threads; check GitHub)\n", threads)
	}
	emit(c, map[string]any{"body": b.String(), "link": p.URL})
	closed := p.State == "MERGED" || p.State == "CLOSED"
	if closed || (until == "reviewed" && reviewed) || (until == "five" && five && threads == 0 && allRead) {
		panic(probeDone{})
	}
}

// tailBytes reads at most the last n bytes of a file.
func tailBytes(path string, n int64) string {
	f, err := os.Open(path)
	if err != nil {
		fail("%v", err)
	}
	defer f.Close()
	info, err := f.Stat()
	check(err)
	if info.Size() > n {
		_, err = f.Seek(-n, io.SeekEnd)
		check(err)
	}
	data, err := io.ReadAll(f)
	check(err)
	return string(data)
}

func cmdProbeTail(c *call) {
	lines := 15
	if c.has("lines") {
		n, err := fmt.Sscanf(c.flag("lines"), "%d", &lines)
		if n != 1 || err != nil || lines < 1 {
			fail("--lines must be a positive number")
		}
	}
	var until *regexp.Regexp
	if c.has("until") {
		re, err := regexp.Compile(c.flag("until"))
		if err != nil {
			fail("bad --until: %v", err)
		}
		until = re
	}
	all := strings.Split(strings.TrimRight(tailBytes(c.pos["file"], 256<<10), "\n"), "\n")
	last := all[max(0, len(all)-lines):]
	text := strings.ReplaceAll(strings.Join(last, "\n"), "```", "'''")
	c.printf("```\n%s\n```\n", text)
	if until != nil {
		for _, l := range all {
			if until.MatchString(l) {
				panic(probeDone{})
			}
		}
	}
}
