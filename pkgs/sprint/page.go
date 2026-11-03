package main

// Status pages for the sprint log, served by `sprint serve`.
//
// Each request reads the log again, so a page is never stale. Pages:
//
//	/                     every sprint
//	/s/<slug>             the goal page: goal, subgoals, timeline, context
//	/s/<slug>/<subgoal>   one subgoal: its plan, benchmarks, context
//	/api/stamp            changes when the log changes; the pages poll it
//
// The log is the user's own, written by their agents, so Markdown in context
// sections may hold raw HTML (diagrams as inline SVG). Everything else is
// escaped. The server listens on loopback and refuses other Host headers, so
// a web page cannot read it through DNS rebinding.

import (
	"bytes"
	"database/sql"
	_ "embed"
	"encoding/json"
	"fmt"
	"html"
	"net"
	"net/http"
	"os"
	"runtime/debug"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/extension"
	gmhtml "github.com/yuin/goldmark/renderer/html"
)

//go:embed assets/page.css
var pageCSS string

//go:embed assets/page.js
var pageJS string

var statusLabel = map[string]string{
	"planned": "Planned", "active": "Active", "doing": "Doing", "blocked": "Blocked", "done": "Done",
	"dropped": "Dropped", "opened": "Open", "ready": "Ready (5/5)", "merged": "Merged", "closed": "Closed",
}

var statusIcon = map[string]string{
	"planned": "○", "active": "◐", "doing": "◐", "blocked": "⚠", "done": "✓",
	"dropped": "–", "opened": "○", "ready": "◉", "merged": "✓", "closed": "–",
}

var esc = html.EscapeString

var markdown = goldmark.New(
	goldmark.WithExtensions(extension.Table, extension.Strikethrough),
	goldmark.WithRendererOptions(gmhtml.WithUnsafe()),
)

func md(body string) string {
	var b bytes.Buffer
	check(markdown.Convert([]byte(body), &b))
	return b.String()
}

func day(at int64) string  { return time.Unix(at, 0).Format("Mon 02 Jan") }
func when(at int64) string { return time.Unix(at, 0).Format("02 Jan 15:04") }

func ago(at, now int64) string {
	s := max(0, now-at)
	for _, u := range []struct {
		size int64
		unit string
	}{{86400, "d"}, {3600, "h"}, {60, "m"}} {
		if s >= u.size {
			return fmt.Sprintf("%d%s ago", s/u.size, u.unit)
		}
	}
	return "just now"
}

func pill(status string) string {
	label := statusLabel[status]
	if label == "" {
		label = status
	}
	return fmt.Sprintf(`<span class="pill %s"><span aria-hidden="true">%s</span> %s</span>`,
		esc(status), statusIcon[status], esc(label))
}

func percent(done, total int64) int64 {
	if total == 0 {
		return 0
	}
	return (200*done + total) / (2 * total) // rounded
}

func meter(done, total int64, label bool) string {
	pct := percent(done, total)
	text := ""
	if label {
		text = fmt.Sprintf(`<span class="meter-text">%d of %d done · %d%%</span>`, done, total, pct)
	}
	return fmt.Sprintf(`<div class="meter" role="meter" aria-valuenow="%d" aria-valuemin="0" aria-valuemax="100">`+
		`<div style="width:%d%%"></div></div>%s`, pct, pct, text)
}

func link(url, text string) string {
	if url == "" {
		return esc(text)
	}
	return fmt.Sprintf(`<a href="%s" target="_blank" rel="noopener">%s</a>`, esc(url), esc(text))
}

// asJSON is JSON for a <script type="application/json"> block.
func asJSON(v any) string {
	b, err := json.Marshal(v)
	check(err)
	return strings.ReplaceAll(string(b), "</", `<\/`)
}

// ---------------------------------------------------------------------------
// Data

// sprintData is everything one page needs, read in one transaction.
type sprintData struct {
	Sprint
	now           int64
	ended         int64
	goals         []Goal
	subgoals      []Subgoal
	subgoalEvents []Subgoal
	items         []Item
	itemEvents    []Item
	prs           []PR
	prEvents      []PR
	bench         []Bench
	log           []LogRow
	context       []Context
	titles        map[string]string
}

func loadSprint(s Store, slug string, now int64) *sprintData {
	sp, ok := s.sprintBySlug(slug)
	if !ok {
		return nil
	}
	d := &sprintData{Sprint: sp, now: now, titles: map[string]string{}}
	id := []any{sp.ID}
	s.each("SELECT at, text, reason, source FROM goal_versions WHERE sprint_id = ? ORDER BY at, id", id, func(r *sql.Rows) {
		var g Goal
		check(r.Scan(&g.At, &g.Text, &g.Reason, &g.Source))
		d.goals = append(d.goals, g)
	})
	s.each("SELECT g.key, g.at, g.title, g.goal, COALESCE(g.done_when, ''), g.status, g.position, g.reason, g.source, "+
		"p.done, p.in_scope FROM subgoal_state g JOIN subgoal_progress p ON p.sprint_id = g.sprint_id AND p.key = g.key "+
		"WHERE g.sprint_id = ? ORDER BY g.position", id, func(r *sql.Rows) {
		var g Subgoal
		check(r.Scan(&g.Key, &g.At, &g.Title, &g.Goal, &g.DoneWhen, &g.Status, &g.Position, &g.Reason, &g.Source,
			&g.Done, &g.InScope))
		d.subgoals = append(d.subgoals, g)
		d.titles[g.Key] = g.Title
	})
	s.each("SELECT "+subgoalCols+" FROM subgoal_events WHERE sprint_id = ? ORDER BY at, id", id, func(r *sql.Rows) {
		d.subgoalEvents = append(d.subgoalEvents, scanSubgoal(r))
	})
	s.each("SELECT "+itemCols+" FROM item_state WHERE sprint_id = ? ORDER BY position", id, func(r *sql.Rows) {
		d.items = append(d.items, scanItem(r))
	})
	s.each("SELECT "+itemCols+" FROM item_events WHERE sprint_id = ? ORDER BY at, id", id, func(r *sql.Rows) {
		d.itemEvents = append(d.itemEvents, scanItem(r))
	})
	s.each("SELECT "+prCols+" FROM pr_state WHERE sprint_id = ? ORDER BY at DESC, id DESC", id, func(r *sql.Rows) {
		d.prs = append(d.prs, scanPR(r))
	})
	s.each("SELECT "+prCols+" FROM pr_events WHERE sprint_id = ? ORDER BY at, id", id, func(r *sql.Rows) {
		d.prEvents = append(d.prEvents, scanPR(r))
	})
	s.each("SELECT "+benchCols+" FROM bench_results WHERE sprint_id = ? ORDER BY at, id", id, func(r *sql.Rows) {
		d.bench = append(d.bench, scanBench(r))
	})
	s.each("SELECT "+logCols+" FROM log WHERE sprint_id = ? ORDER BY at, id", id, func(r *sql.Rows) {
		l := scanLog(r)
		d.log = append(d.log, l)
		if l.Kind == "end" && d.ended == 0 {
			d.ended = l.At
		}
	})
	s.each("SELECT "+contextCols+" FROM context_state WHERE sprint_id = ? ORDER BY position, id", id, func(r *sql.Rows) {
		d.context = append(d.context, scanContext(r))
	})
	return d
}

func (d *sprintData) subgoal(key string) *Subgoal {
	for i := range d.subgoals {
		if d.subgoals[i].Key == key {
			return &d.subgoals[i]
		}
	}
	return nil
}

func (d *sprintData) url(key string) string { return pagePath(d.Slug, key) }

func (d *sprintData) end() int64 {
	if d.ended != 0 {
		return d.ended
	}
	return d.now
}

// goalChanges lists the subgoal events that changed the subgoal's goal.
func (d *sprintData) goalChanges(key string) []Subgoal {
	var out []Subgoal
	last, seen := "", false
	for _, e := range d.subgoalEvents {
		if e.Key != key {
			continue
		}
		if seen && e.Goal != last {
			out = append(out, e)
		}
		last, seen = e.Goal, true
	}
	return out
}

// burnup gives [time, in scope, done] after each change, for items in key
// ("" for all). An item counts toward the subgoal it was in at that time.
func (d *sprintData) burnup(key string, all bool) [][3]int64 {
	type st struct {
		scope, done int64
		subgoal     string
	}
	state := map[int64]st{}
	var scope, done int64
	var points [][3]int64
	in := func(sg string) bool { return all || sg == key }
	for _, e := range d.itemEvents {
		if old, ok := state[e.Item]; ok && in(old.subgoal) {
			scope -= old.scope
			done -= old.done
		}
		n := st{b2i(e.Status != "dropped"), b2i(e.Status == "done"), e.Subgoal}
		state[e.Item] = n
		if in(n.subgoal) {
			scope += n.scope
			done += n.done
		}
		if len(points) > 0 && points[len(points)-1][0] == e.At {
			points[len(points)-1] = [3]int64{e.At, scope, done}
		} else {
			points = append(points, [3]int64{e.At, scope, done})
		}
	}
	if len(points) > 0 {
		points = append(points, [3]int64{d.end(), scope, done})
	}
	return points
}

func b2i(b bool) int64 {
	if b {
		return 1
	}
	return 0
}

type event struct {
	at      int64
	kind    string
	subgoal string
	html    string
}

func why(text string) string { return fmt.Sprintf(` <span class="why">— %s</span>`, esc(text)) }

// activity lists every change, newest first; only those in key unless all.
func (d *sprintData) activity(key string, all bool) []event {
	var out []event
	for n, g := range d.goals {
		text := fmt.Sprintf("<b>Goal v%d</b>: %s", n+1, esc(g.Text))
		if g.Reason != "sprint start" {
			text += why(g.Reason)
		}
		out = append(out, event{g.At, "goal", "", text})
	}
	lastSub := map[string]Subgoal{}
	for _, e := range d.subgoalEvents {
		old, had := lastSub[e.Key]
		lastSub[e.Key] = e
		name := fmt.Sprintf(`<a href="%s">%s</a>`, esc(d.url(e.Key)), esc(e.Title))
		var text string
		switch {
		case !had:
			text = fmt.Sprintf("Subgoal added: %s — %s", name, esc(e.Goal))
		case old.Goal != e.Goal:
			text = fmt.Sprintf("%s goal changed: %s", name, esc(e.Goal)) + why(e.Reason)
		case old.Status != e.Status:
			text = fmt.Sprintf("%s %s → %s", name, pill(old.Status), pill(e.Status))
		default:
			text = name + " edited"
		}
		out = append(out, event{e.At, "subgoal", e.Key, text})
	}
	lastItem := map[int64]Item{}
	for _, e := range d.itemEvents {
		old, had := lastItem[e.Item]
		lastItem[e.Item] = e
		name := fmt.Sprintf("#%d %s", e.Item, esc(e.Title))
		var text string
		switch {
		case !had:
			text = "Planned " + name
			if e.Owner == "user" {
				text += " (your step)"
			}
		case old.Status != e.Status:
			text = name + " " + pill(e.Status)
		case old.Subgoal != e.Subgoal:
			dest := d.titles[e.Subgoal]
			if dest == "" {
				dest = "the whole sprint"
			}
			text = name + " moved to " + esc(dest)
		default:
			text = name + " updated"
		}
		if e.Note != "" {
			text += why(e.Note)
		}
		out = append(out, event{e.At, "item", e.Subgoal, text})
	}
	for _, e := range d.prEvents {
		out = append(out, event{e.At, "pr", e.Subgoal, "PR " + pill(e.State) + " " + link(e.URL, e.Title)})
	}
	for _, b := range d.bench {
		text := fmt.Sprintf("Benchmark %s %s = <b>%s %s</b>", esc(b.Suite), esc(b.Metric), fmtNum(b.Value), esc(b.Unit))
		if b.Baseline {
			text += " (baseline)"
		}
		if b.Link != "" {
			text += " · " + link(b.Link, "run")
		}
		out = append(out, event{b.At, "bench", b.Subgoal, text})
	}
	for _, l := range d.log {
		text := fmt.Sprintf(`<span class="kind">%s</span> %s`, esc(l.Kind), esc(l.Text))
		if l.Link != "" {
			text += " · " + link(l.Link, "link")
		}
		out = append(out, event{l.At, l.Kind, l.Subgoal, text})
	}
	if !all {
		kept := out[:0]
		for _, e := range out {
			if e.subgoal == key {
				kept = append(kept, e)
			}
		}
		out = kept
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].at > out[j].at })
	return out
}

type mark struct {
	T     int64  `json:"t"`
	Kind  string `json:"kind,omitempty"`
	Label string `json:"label"`
}

type span struct {
	From   int64  `json:"from"`
	To     int64  `json:"to"`
	Status string `json:"status"`
}

type lane struct {
	Name   string `json:"name"`
	Status string `json:"status,omitempty"`
	Href   string `json:"href,omitempty"`
	Spans  []span `json:"spans"`
	Marks  []mark `json:"marks"`
}

// timeline gives the lanes for the timeline chart: when each subgoal was
// active, its merges, and goal changes.
func (d *sprintData) timeline() map[string]any {
	goalLane := lane{Name: "Sprint goal", Spans: []span{}, Marks: []mark{}}
	for n, g := range d.goals {
		goalLane.Marks = append(goalLane.Marks, mark{g.At, "goal", fmt.Sprintf("Goal v%d: %s", n+1, g.Text)})
	}
	lanes := []lane{goalLane}
	merges := func(key string) []mark {
		out := []mark{}
		for _, e := range d.prEvents {
			if e.Subgoal == key && e.State == "merged" {
				out = append(out, mark{e.At, "merge", "Merged: " + e.Title})
			}
		}
		return out
	}
	for _, g := range d.subgoals {
		spans := []span{}
		var start int64
		for _, e := range d.subgoalEvents {
			if e.Key != g.Key {
				continue
			}
			if e.Status == "active" && start == 0 {
				start = e.At
			} else if e.Status != "active" && start != 0 {
				spans = append(spans, span{start, e.At, e.Status})
				start = 0
			}
		}
		if start != 0 {
			spans = append(spans, span{start, d.end(), "active"})
		}
		marks := merges(g.Key)
		for _, e := range d.goalChanges(g.Key) {
			marks = append(marks, mark{e.At, "steer", "Goal changed: " + e.Reason})
		}
		lanes = append(lanes, lane{g.Title, g.Status, d.url(g.Key), spans, marks})
	}
	if loose := merges(""); len(loose) > 0 {
		lanes = append(lanes, lane{Name: "Not in a subgoal", Spans: []span{}, Marks: loose})
	}
	return map[string]any{"from": d.StartedAt, "to": d.end(), "lanes": lanes}
}

// ---------------------------------------------------------------------------
// Sections

type version struct {
	at           int64
	text, reason string
}

func goalHistory(versions []version, title string) string {
	if len(versions) < 2 {
		return ""
	}
	var rows strings.Builder
	for n := len(versions) - 1; n >= 0; n-- {
		v := versions[n]
		fmt.Fprintf(&rows, "<tr><td class=num>v%d</td><td>%s</td><td>%s</td><td>%s</td></tr>",
			n+1, when(v.at), esc(v.text), esc(v.reason))
	}
	return fmt.Sprintf(`<details class="card"><summary><h2>%s</h2> <span class="muted">%d versions</span></summary>`+
		`<table><thead><tr><th>#</th><th>When</th><th>Goal</th><th>Why it changed</th></tr></thead><tbody>%s</tbody>`+
		`</table></details>`, title, len(versions), rows.String())
}

func (d *sprintData) tag(key string) string {
	if t := d.titles[key]; t != "" {
		return fmt.Sprintf(` <span class="tag">%s</span>`, esc(t))
	}
	return ""
}

func (d *sprintData) titleOr(key, dflt string) string {
	if t := d.titles[key]; t != "" {
		return t
	}
	return dflt
}

func doNow(d *sprintData, key string, all bool) string {
	var b strings.Builder
	for _, i := range d.items {
		if i.Owner != "user" || i.Status == "done" || i.Status == "dropped" || (!all && i.Subgoal != key) {
			continue
		}
		fmt.Fprintf(&b, "<li>%s %s", esc(i.Title), pill(i.Status))
		if all {
			b.WriteString(d.tag(i.Subgoal))
		}
		if i.Note != "" {
			fmt.Fprintf(&b, `<div class="why">%s</div>`, esc(i.Note))
		}
		b.WriteString("</li>")
	}
	if b.Len() == 0 {
		return ""
	}
	return `<section class="card do-now"><h2>Do now (you)</h2><ol>` + b.String() + "</ol></section>"
}

func subgoalCards(d *sprintData) string {
	if len(d.subgoals) == 0 {
		return ""
	}
	var b strings.Builder
	for _, g := range d.subgoals {
		var merged, open int
		for _, p := range d.prs {
			if p.Subgoal == g.Key {
				if p.State == "merged" {
					merged++
				} else if p.State == "opened" || p.State == "ready" {
					open++
				}
			}
		}
		doneWhen := ""
		if g.DoneWhen != "" {
			doneWhen = fmt.Sprintf(`<p class="done-when"><b>Done when:</b> %s</p>`, esc(g.DoneWhen))
		}
		fmt.Fprintf(&b, `<a class="subgoal %s" href="%s"><div class="row">%s<span class="muted">%d merged · %d open PRs</span>`+
			`</div><h3>%s</h3><p>%s</p>%s%s</a>`, esc(g.Status), esc(d.url(g.Key)), pill(g.Status), merged, open,
			esc(g.Title), esc(g.Goal), doneWhen, meter(g.Done, g.InScope, true))
	}
	return `<section><h2>Subgoals</h2><div class="subgoals">` + b.String() + "</div></section>"
}

func plan(d *sprintData, key string, all bool, title string) string {
	var b strings.Builder
	for _, i := range d.items {
		if !all && i.Subgoal != key {
			continue
		}
		owner := "agent"
		if i.Owner == "user" {
			owner = "you"
		}
		fmt.Fprintf(&b, `<tr class="%s"><td class=num>%d</td><td>%s</td><td>%s</td><td>%s</td>`,
			esc(i.Status), i.Item, esc(i.Title), pill(i.Status), owner)
		if all {
			fmt.Fprintf(&b, "<td>%s</td>", esc(d.titleOr(i.Subgoal, "—")))
		}
		fmt.Fprintf(&b, `<td>%s</td><td class="why">%s</td></tr>`, when(i.At), esc(i.Note))
	}
	if b.Len() == 0 {
		return ""
	}
	sub := ""
	if all {
		sub = "<th>Subgoal</th>"
	}
	return fmt.Sprintf(`<section class="card"><h2>%s</h2><table><thead><tr><th>#</th><th>Item</th><th>Status</th>`+
		`<th>Owner</th>%s<th>Updated</th><th>Note</th></tr></thead><tbody>%s</tbody></table></section>`, title, sub, b.String())
}

type series struct {
	Name    string   `json:"name"`
	Color   string   `json:"color"`
	Pts     [][2]any `json:"pts"`
	Commits []string `json:"commits,omitempty"`
}

func burnupChart(d *sprintData, key string, all bool) string {
	points := d.burnup(key, all)
	if len(points) == 0 {
		return ""
	}
	markers := []mark{}
	if all {
		for n, g := range d.goals {
			if n > 0 {
				markers = append(markers, mark{T: g.At, Label: fmt.Sprintf("Goal v%d", n+1)})
			}
		}
	} else {
		for _, e := range d.goalChanges(key) {
			markers = append(markers, mark{T: e.At, Label: "Goal changed"})
		}
	}
	scope, done := series{Name: "In scope", Color: "var(--scope)"}, series{Name: "Done", Color: "var(--series-1)"}
	for _, p := range points {
		scope.Pts = append(scope.Pts, [2]any{p[0], p[1]})
		done.Pts = append(done.Pts, [2]any{p[0], p[2]})
	}
	spec := map[string]any{"kind": "step", "series": []series{scope, done}, "markers": markers}
	return `<section class="card"><h2>Burn-up</h2><p class="muted">Items done against items in scope. ` +
		`A rise in scope is new work.</p><div class="chart" data-spec="burnup"></div>` +
		`<script type="application/json">` + asJSON(spec) + `</script></section>`
}

func timelineChart(d *sprintData) string {
	if len(d.subgoals) == 0 && len(d.goals) < 2 {
		return ""
	}
	return `<section class="card"><h2>Timeline</h2><p class="muted">When each subgoal was active, ` +
		`with merges (●) and goal changes (◆).</p><div class="chart" data-spec="timeline"></div>` +
		`<script type="application/json">` + asJSON(d.timeline()) + `</script></section>`
}

func benchSection(d *sprintData, key string, all bool) string {
	type gk struct{ suite, metric, unit string }
	groups := map[gk][]Bench{}
	var order []gk
	for _, b := range d.bench {
		if !all && b.Subgoal != key {
			continue
		}
		k := gk{b.Suite, b.Metric, b.Unit}
		if _, ok := groups[k]; !ok {
			order = append(order, k)
		}
		groups[k] = append(groups[k], b)
	}
	if len(order) == 0 {
		return ""
	}
	sort.Slice(order, func(i, j int) bool {
		a, b := order[i], order[j]
		return a.suite+"\x00"+a.metric+"\x00"+a.unit < b.suite+"\x00"+b.metric+"\x00"+b.unit
	})
	var table, charts strings.Builder
	for _, k := range order {
		rs := groups[k]
		var runs []Bench
		var base *Bench
		for i := range rs {
			if rs[i].Baseline {
				base = &rs[i]
			} else {
				runs = append(runs, rs[i])
			}
		}
		latest, baseline, change := "", "", ""
		if len(runs) > 0 {
			latest = fmtNum(runs[len(runs)-1].Value)
		}
		if base != nil {
			baseline = fmtNum(base.Value)
		}
		if len(runs) > 0 && base != nil && base.Value != 0 {
			change = fmt.Sprintf("%+.1f%%", 100*(runs[len(runs)-1].Value-base.Value)/base.Value)
		}
		where := ""
		if all {
			where = "<td>" + esc(d.titleOr(rs[len(rs)-1].Subgoal, "—")) + "</td>"
		}
		fmt.Fprintf(&table, "<tr><td>%s</td><td>%s</td>%s<td class=num>%s</td><td class=num>%s</td><td>%s</td>"+
			"<td class=num>%s</td><td class=num>%d</td><td>%s</td></tr>",
			esc(k.suite), esc(k.metric), where, latest, baseline, esc(k.unit), change, len(runs), when(rs[len(rs)-1].At))
		if len(runs) > 1 || (len(runs) > 0 && base != nil) {
			s := series{Name: k.metric, Color: "var(--series-1)"}
			for _, r := range runs {
				s.Pts = append(s.Pts, [2]any{r.At, r.Value})
				s.Commits = append(s.Commits, r.Commit)
			}
			spec := map[string]any{"kind": "line", "unit": k.unit, "series": []series{s}, "baseline": nil}
			if base != nil {
				spec["baseline"] = base.Value
			}
			fmt.Fprintf(&charts, `<figure class="mini"><figcaption>%s · %s (%s)</figcaption><div class="chart" data-spec="line">`+
				`</div><script type="application/json">%s</script></figure>`, esc(k.suite), esc(k.metric), esc(k.unit), asJSON(spec))
		}
	}
	sub := ""
	if all {
		sub = "<th>Subgoal</th>"
	}
	minis := ""
	if charts.Len() > 0 {
		minis = `<div class="minis">` + charts.String() + "</div>"
	}
	return fmt.Sprintf(`<section class="card"><h2>Benchmarks</h2><table><thead><tr><th>Suite</th><th>Metric</th>%s`+
		`<th>Latest</th><th>Baseline</th><th>Unit</th><th>Change</th><th>Runs</th><th>Last run</th></tr></thead>`+
		`<tbody>%s</tbody></table>%s</section>`, sub, table.String(), minis)
}

func prTable(d *sprintData, key string, all bool) string {
	var prs []PR
	for _, p := range d.prs {
		if all || p.Subgoal == key {
			prs = append(prs, p)
		}
	}
	if len(prs) == 0 {
		return ""
	}
	order := map[string]int{"ready": 0, "opened": 1, "merged": 2, "closed": 3}
	sort.SliceStable(prs, func(i, j int) bool {
		if order[prs[i].State] != order[prs[j].State] {
			return order[prs[i].State] < order[prs[j].State]
		}
		return prs[i].At > prs[j].At
	})
	var b strings.Builder
	for _, p := range prs {
		fmt.Fprintf(&b, "<tr><td>%s</td><td>%s</td>", link(p.URL, p.Title), pill(p.State))
		if all {
			fmt.Fprintf(&b, "<td>%s</td>", esc(d.titleOr(p.Subgoal, "—")))
		}
		fmt.Fprintf(&b, "<td>%s</td></tr>", when(p.At))
	}
	sub := ""
	if all {
		sub = "<th>Subgoal</th>"
	}
	return fmt.Sprintf(`<section class="card"><h2>Pull requests</h2><table><thead><tr><th>PR</th><th>State</th>%s`+
		`<th>Since</th></tr></thead><tbody>%s</tbody></table></section>`, sub, b.String())
}

func contextSections(d *sprintData, key string) string {
	var b strings.Builder
	for _, c := range d.context {
		if c.Subgoal == key {
			fmt.Fprintf(&b, `<section class="card context" id="ctx-%s"><h2>%s</h2><div class="md">%s</div>`+
				`<p class="muted small">Updated %s</p></section>`, esc(c.Key), esc(c.Title), md(c.Body), when(c.At))
		}
	}
	return b.String()
}

func activitySection(d *sprintData, key string, all, showAll bool) string {
	events := d.activity(key, all)
	if len(events) == 0 {
		return ""
	}
	shown := events
	if !showAll && len(shown) > 60 {
		shown = shown[:60]
	}
	var b strings.Builder
	current := ""
	for _, e := range shown {
		if dd := day(e.at); dd != current {
			if current != "" {
				b.WriteString("</ul>")
			}
			fmt.Fprintf(&b, "<h3>%s</h3><ul>", dd)
			current = dd
		}
		tag := ""
		if all {
			tag = d.tag(e.subgoal)
		}
		fmt.Fprintf(&b, `<li class="ev-%s"><time>%s</time><span>%s%s</span></li>`,
			esc(e.kind), time.Unix(e.at, 0).Format("15:04"), e.html, tag)
	}
	b.WriteString("</ul>")
	if len(events) > len(shown) {
		fmt.Fprintf(&b, `<p><a href="?all=1#activity">Show all %d changes</a></p>`, len(events))
	}
	return `<section class="card" id="activity"><h2>Activity</h2><p class="muted">Every change, newest first. ` +
		`Nothing here is edited or removed.</p>` + b.String() + "</section>"
}

// ---------------------------------------------------------------------------
// Pages

type crumb struct{ text, href string }

func layout(title string, crumbs []crumb, body, stamp string) string {
	parts := make([]string, len(crumbs))
	for i, c := range crumbs {
		if c.href != "" {
			parts[i] = fmt.Sprintf(`<a href="%s">%s</a>`, esc(c.href), esc(c.text))
		} else {
			parts[i] = esc(c.text)
		}
	}
	return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>` + esc(title) + `</title><style>` + pageCSS + `</style></head>
<body><div class="viz-root">
<header class="top"><nav>` + strings.Join(parts, " / ") + `</nav><span class="live" data-stamp="` + esc(stamp) +
		`">● Live</span></header>
<main>` + body + `</main></div><script>` + pageJS + `</script></body></html>`
}

// stamp changes whenever any table gets a row.
func stamp(s Store) string {
	parts := make([]string, len(tables))
	for i, t := range tables {
		parts[i] = strconv.FormatInt(s.int("SELECT COALESCE(MAX(id), 0) FROM "+t), 10)
	}
	return strings.Join(parts, ".")
}

func indexPage(s Store) string {
	open := map[int64]bool{}
	for _, sp := range s.openSprints() {
		open[sp.ID] = true
	}
	var all []Sprint
	s.each("SELECT "+sprintCols+" FROM sprints ORDER BY started_at DESC", nil, func(r *sql.Rows) {
		all = append(all, scanSprint(r))
	})
	var b strings.Builder
	for _, sp := range all {
		var goal string
		s.one("SELECT text FROM goal_current WHERE sprint_id = ?", []any{sp.ID}, &goal)
		var done, scope int64
		s.one("SELECT done, in_scope FROM progress WHERE sprint_id = ?", []any{sp.ID}, &done, &scope)
		active := s.strings("SELECT title FROM subgoal_state WHERE sprint_id = ? AND status = 'active' ORDER BY position", sp.ID)
		status := "done"
		if open[sp.ID] {
			status = "active"
		}
		now := ""
		if len(active) > 0 {
			now = fmt.Sprintf(`<p class="done-when"><b>Now:</b> %s</p>`, esc(strings.Join(active, ", ")))
		}
		fmt.Fprintf(&b, `<a class="subgoal %s" href="%s"><div class="row">%s<span class="muted">started %s</span></div>`+
			`<h3>%s</h3><p>%s</p>%s%s</a>`, status, esc(pagePath(sp.Slug, "")), pill(status), day(sp.StartedAt),
			esc(sp.Title), esc(goal), now, meter(done, scope, true))
	}
	body := "<h1>No sprints yet</h1><p>Start one with <code>sprint start</code>.</p>"
	if b.Len() > 0 {
		body = `<h1>Sprints</h1><div class="subgoals">` + b.String() + "</div>"
	}
	return layout("Sprints", []crumb{{"Sprints", ""}}, body, stamp(s))
}

func hero(title, goalHTML string, done, total int64, extra string) string {
	return fmt.Sprintf(`<section class="hero"><div class="hero-text"><h1>%s</h1>%s%s</div><div class="hero-figure">`+
		`<div class="figure">%d%%</div><div class="muted">%d of %d items done</div>%s</div></section>`,
		esc(title), goalHTML, extra, percent(done, total), done, total, meter(done, total, false))
}

func goalPage(s Store, d *sprintData, showAll bool) string {
	g := d.goals[len(d.goals)-1]
	extra := ""
	if len(d.goals) > 1 {
		extra = fmt.Sprintf(`<p class="muted">Goal v%d · changed %s: %s</p>`, len(d.goals), ago(g.At, d.now), esc(g.Reason))
	}
	if d.ended != 0 {
		extra += fmt.Sprintf("<p>%s Ended %s</p>", pill("done"), when(d.ended))
	}
	var done, total int64
	loose := false
	for _, i := range d.items {
		done += b2i(i.Status == "done")
		total += b2i(i.Status != "dropped")
		loose = loose || i.Subgoal == ""
	}
	versions := make([]version, len(d.goals))
	for i, g := range d.goals {
		versions[i] = version{g.At, g.Text, g.Reason}
	}
	items := ""
	if len(d.subgoals) == 0 || loose {
		items = plan(d, "", true, "All items")
	}
	body := hero(d.Title, `<p class="goal">`+esc(g.Text)+"</p>", done, total, extra) +
		subgoalCards(d) + doNow(d, "", true) + timelineChart(d) + burnupChart(d, "", true) +
		contextSections(d, "") + items + benchSection(d, "", true) + prTable(d, "", true) +
		goalHistory(versions, "Goal history") + activitySection(d, "", true, showAll)
	return layout(d.Title, []crumb{{"Sprints", "/"}, {d.Title, ""}}, body, stamp(s))
}

func subgoalPage(s Store, d *sprintData, key string, showAll bool) string {
	g := d.subgoal(key)
	var versions []version
	for _, e := range d.subgoalEvents {
		if e.Key == key && (len(versions) == 0 || versions[len(versions)-1].text != e.Goal) {
			versions = append(versions, version{e.At, e.Goal, e.Reason})
		}
	}
	extra := ""
	if g.DoneWhen != "" {
		extra = fmt.Sprintf(`<p class="done-when"><b>Done when:</b> %s</p>`, esc(g.DoneWhen))
	}
	extra += fmt.Sprintf(`<p class="muted">Part of: <a href="%s">%s</a></p>`, esc(d.url("")), esc(d.goals[len(d.goals)-1].Text))
	body := hero(g.Title, "<p>"+pill(g.Status)+`</p><p class="goal">`+esc(g.Goal)+"</p>", g.Done, g.InScope, extra) +
		doNow(d, key, false) + plan(d, key, false, "Plan") + burnupChart(d, key, false) + benchSection(d, key, false) +
		contextSections(d, key) + prTable(d, key, false) + goalHistory(versions, "Subgoal history") +
		activitySection(d, key, false, showAll)
	return layout(g.Title+" · "+d.Title, []crumb{{"Sprints", "/"}, {d.Title, d.url("")}, {g.Title, ""}}, body, stamp(s))
}

// ---------------------------------------------------------------------------
// Server

func isLoopback(host string) bool {
	if host == "localhost" {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

type pages struct {
	db        *sql.DB
	checkHost bool
	port      string
}

func send(w http.ResponseWriter, code int, body, ctype string) {
	h := w.Header()
	h.Set("Content-Type", ctype)
	h.Set("Cache-Control", "no-store")
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Referrer-Policy", "no-referrer")
	w.WriteHeader(code)
	w.Write([]byte(body))
}

const htmlType = "text/html; charset=utf-8"

func (p *pages) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if p.checkHost {
		ok := false
		for _, h := range []string{"127.0.0.1", "localhost", "[::1]"} {
			ok = ok || r.Host == h+":"+p.port
		}
		if !ok {
			send(w, http.StatusForbidden, "Forbidden host\n", "text/plain")
			return
		}
	}
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		send(w, http.StatusMethodNotAllowed, "GET only\n", "text/plain")
		return
	}
	tx, err := p.db.BeginTx(r.Context(), &sql.TxOptions{ReadOnly: true})
	if err != nil {
		fmt.Fprintf(os.Stderr, "sprint: %s: %v\n", r.URL.Path, err)
		send(w, http.StatusInternalServerError, "sprint page error\n", "text/plain")
		return
	}
	defer tx.Rollback()
	defer func() {
		if rec := recover(); rec != nil {
			fmt.Fprintf(os.Stderr, "sprint: %s: %v\n%s", r.URL.Path, rec, debug.Stack())
			send(w, http.StatusInternalServerError, "sprint page error\n", "text/plain")
		}
	}()
	s := Store{tx}
	var parts []string
	for _, part := range strings.Split(r.URL.Path, "/") {
		if part != "" {
			parts = append(parts, part)
		}
	}
	showAll := r.URL.Query().Get("all") == "1"
	now := time.Now().Unix()
	switch {
	case len(parts) == 2 && parts[0] == "api" && parts[1] == "stamp":
		send(w, http.StatusOK, stamp(s), "text/plain")
		return
	case len(parts) == 0:
		send(w, http.StatusOK, indexPage(s), htmlType)
		return
	case parts[0] == "s" && (len(parts) == 2 || len(parts) == 3):
		if d := loadSprint(s, parts[1], now); d != nil {
			if len(parts) == 2 {
				send(w, http.StatusOK, goalPage(s, d, showAll), htmlType)
				return
			}
			if d.subgoal(parts[2]) != nil {
				send(w, http.StatusOK, subgoalPage(s, d, parts[2], showAll), htmlType)
				return
			}
		}
	}
	send(w, http.StatusNotFound, layout("Not found", []crumb{{"Sprints", "/"}}, "<h1>Not found</h1>", ""), htmlType)
}

// listen opens the port; port 0 picks a free one (tests).
func listen(dbPath, host, port string) (net.Listener, http.Handler) {
	ln, err := net.Listen("tcp", net.JoinHostPort(host, port))
	check(err)
	_, bound, _ := net.SplitHostPort(ln.Addr().String())
	return ln, &pages{db: openRead(dbPath), checkHost: isLoopback(host), port: bound}
}

func cmdServe(c *call) {
	host, port := c.flag("host"), c.flag("port")
	if host == "" {
		host = "127.0.0.1"
	}
	if port == "" {
		port = "3001"
	}
	ln, h := listen(c.dbPath, host, port)
	fmt.Fprintf(c.out, "sprint pages on http://%s\n", ln.Addr())
	srv := &http.Server{Handler: h, ReadHeaderTimeout: 10 * time.Second}
	check(srv.Serve(ln))
}
