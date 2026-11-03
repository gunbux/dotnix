package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

var (
	sources     = []string{"user", "agent"}
	owners      = []string{"agent", "user"}
	itemStates  = []string{"planned", "doing", "blocked", "done", "dropped"}
	subStates   = []string{"planned", "active", "done", "dropped"}
	subgoalHelp = "subgoal key; default $SPRINT_SUBGOAL or the only active subgoal; - for the whole sprint"
)

var commands []command

func init() {
	commands = []command{
		{path: "init", help: "create the log and its schema", run: func(*call) {}},
		{path: "list", help: "list sprints", run: cmdList},
		{path: "start", help: "start a sprint", run: cmdStart,
			args:     []argDef{{name: "slug"}, {name: "title"}},
			flags:    map[string]flagDef{"goal": {help: "the goal in the user's words"}, "source": {choices: sources}},
			required: []string{"goal"}},
		{path: "goal", help: "add a sprint goal version; the old one stays", run: cmdGoal,
			args: []argDef{{name: "text"}},
			flags: map[string]flagDef{"reason": {help: "why it changed, in the user's words"},
				"source": {choices: sources}},
			required: []string{"reason"}},
		{path: "sub add", help: "add a subgoal: one stage of the sprint goal", run: cmdSubAdd,
			args: []argDef{{name: "key"}, {name: "title"}},
			flags: map[string]flagDef{
				"goal":      {help: "what this stage delivers, in the user's words"},
				"done-when": {help: "the check that says this stage is done"},
				"status":    {choices: []string{"planned", "active"}, help: "default planned"},
				"after":     {help: "place after this subgoal"},
				"source":    {choices: sources}},
			required: []string{"goal"}},
		{path: "sub set", help: "change a subgoal's status, goal, title, or exit check", run: cmdSubSet,
			args: []argDef{{name: "key"}, {name: "status", opt: true, choices: subStates}},
			flags: map[string]flagDef{
				"goal":      {help: "new goal"},
				"reason":    {help: "why; required when the goal changes"},
				"done-when": {help: "new exit check"},
				"title":     {help: "new title"},
				"source":    {choices: sources}}},
		{path: "item add", help: "add a plan item", run: cmdItemAdd,
			args: []argDef{{name: "title"}},
			flags: map[string]flagDef{
				"owner":   {choices: owners, help: "default agent; user for the user's own steps"},
				"status":  {choices: itemStates[:4], help: "default planned"},
				"after":   {help: "place after this item number"},
				"note":    {help: "why"},
				"subgoal": {help: subgoalHelp}}},
		{path: "item set", help: "change an item's status, owner, title, or subgoal", run: cmdItemSet,
			args: []argDef{{name: "item"}, {name: "status", opt: true, choices: itemStates}},
			flags: map[string]flagDef{
				"owner":   {choices: owners},
				"title":   {help: "new title"},
				"note":    {help: "why"},
				"subgoal": {help: "move the item to this subgoal; - for the whole sprint"}}},
		{path: "pr add", help: "track PRs; records their GitHub history", run: cmdPRAdd, prefetch: fetchPRAdd,
			args:  []argDef{{name: "url", many: true}},
			flags: map[string]flagDef{"subgoal": {help: subgoalHelp + " (new PRs only)"}}},
		{path: "pr ready", help: "mark a PR ready to merge (review gate passed)", run: cmdPRReady,
			args: []argDef{{name: "url"}}},
		{path: "pr sync", help: "record merges, closes, and reopens from GitHub", run: cmdPRSync,
			prefetch: fetchPRSync},
		{path: "bench", help: "record a benchmark result", run: cmdBench,
			args: []argDef{{name: "suite"}, {name: "metric"}, {name: "value"}, {name: "unit"}},
			flags: map[string]flagDef{
				"baseline": {isBool: true, help: "this is the reference result"},
				"commit":   {help: "commit measured"},
				"link":     {help: "link to the run"},
				"subgoal":  {help: subgoalHelp}}},
		{path: "log", help: "record a decision, steer, deploy, or note", run: cmdLog,
			args:  []argDef{{name: "kind", choices: []string{"decision", "steer", "deploy", "note"}}, {name: "text"}},
			flags: map[string]flagDef{"link": {help: "link"}, "subgoal": {help: subgoalHelp}}},
		{path: "context set", help: "add or replace a Markdown context section; old versions stay",
			run: cmdContextSet, prefetch: readBody,
			args: []argDef{{name: "key"}},
			flags: map[string]flagDef{
				"title":   {help: "required for a new section"},
				"first":   {isBool: true, help: "show this section first on its page"},
				"file":    {help: "Markdown file, or - for stdin"},
				"subgoal": {help: "put it on this subgoal's page (default: the goal page)"}},
			required: []string{"file"}},
		{path: "context rm", help: "remove a context section from the page", run: cmdContextRm,
			args:  []argDef{{name: "key"}},
			flags: map[string]flagDef{"subgoal": {help: "the subgoal the section is on"}}},
		{path: "end", help: "end the sprint", run: cmdEnd, flags: map[string]flagDef{"note": {help: "how it ended"}}},
		{path: "show", help: "goal, subgoals, progress, do-now list, PRs, page link", run: cmdShow,
			flags: map[string]flagDef{"json": {isBool: true}}},
		{path: "serve", help: "serve the status pages", run: cmdServe, unlocked: true,
			flags: map[string]flagDef{"host": {help: "default 127.0.0.1"}, "port": {help: "default 3001"}}},
	}
}

func source(c *call) string {
	if c.has("source") {
		return c.flag("source")
	}
	return "user"
}

func cmdStart(c *call) {
	s, slug := c.store, c.pos["slug"]
	checkKey("slug", slug)
	if _, ok := s.sprintBySlug(slug); ok {
		fail("sprint %q already exists", slug)
	}
	at := now()
	id := s.insert("INSERT INTO sprints (slug, title, started_at) VALUES (?, ?, ?)", slug, c.pos["title"], at)
	s.exec("INSERT INTO goal_versions (sprint_id, at, text, reason, source) VALUES (?, ?, ?, 'sprint start', ?)",
		id, at, c.flag("goal"), source(c))
	c.printf("started %s\n", slug)
}

func cmdGoal(c *call) {
	s := c.store
	sp := s.resolve(c.flag("sprint"))
	at := now()
	s.exec("INSERT INTO goal_versions (sprint_id, at, text, reason, source) VALUES (?, ?, ?, ?, ?)",
		sp.ID, at, c.pos["text"], c.flag("reason"), source(c))
	s.exec("INSERT INTO log (sprint_id, at, kind, text) VALUES (?, ?, 'steer', ?)",
		sp.ID, at, "goal changed: "+c.flag("reason"))
	c.printf("goal version %d\n", s.int("SELECT versions FROM goal_current WHERE sprint_id = ?", sp.ID))
}

func cmdSubAdd(c *call) {
	s := c.store
	sp := s.resolve(c.flag("sprint"))
	key := c.pos["key"]
	checkKey("subgoal", key)
	if s.int("SELECT COUNT(*) FROM subgoal_events WHERE sprint_id = ? AND key = ?", sp.ID, key) > 0 {
		fail("subgoal %q already exists", key)
	}
	var before *float64
	if c.has("after") {
		p := s.latestSubgoal(sp.ID, c.flag("after")).Position
		before = &p
	}
	status := "planned"
	if c.has("status") {
		status = c.flag("status")
	}
	s.exec("INSERT INTO subgoal_events (sprint_id, key, at, title, goal, done_when, status, position, reason, source) "+
		"VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'added', ?)",
		sp.ID, key, now(), c.pos["title"], c.flag("goal"), null(c.flag("done-when")), status,
		s.positionAfter("subgoal_state", sp.ID, before), source(c))
	c.printf("subgoal %s: %s\n", key, status)
}

func cmdSubSet(c *call) {
	s := c.store
	sp := s.resolve(c.flag("sprint"))
	cur := s.latestSubgoal(sp.ID, c.pos["key"])
	goal, title, doneWhen, status := cur.Goal, cur.Title, cur.DoneWhen, cur.Status
	goalChanged := c.has("goal") && c.flag("goal") != cur.Goal
	if goalChanged && c.flag("reason") == "" {
		fail("a goal change needs --reason, in the user's words")
	}
	if c.has("goal") {
		goal = c.flag("goal")
	}
	if c.has("title") {
		title = c.flag("title")
	}
	if c.has("done-when") {
		doneWhen = c.flag("done-when")
	}
	if v, ok := c.pos["status"]; ok {
		status = v
	}
	reason := c.flag("reason")
	if reason == "" {
		reason = "edited"
		if _, ok := c.pos["status"]; ok {
			reason = "now " + status
		}
	}
	at := now()
	s.exec("INSERT INTO subgoal_events (sprint_id, key, at, title, goal, done_when, status, position, reason, source) "+
		"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		sp.ID, cur.Key, at, title, goal, null(doneWhen), status, cur.Position, reason, source(c))
	if goalChanged {
		s.exec("INSERT INTO log (sprint_id, at, kind, text, subgoal) VALUES (?, ?, 'steer', ?, ?)",
			sp.ID, at, cur.Title+" goal changed: "+c.flag("reason"), cur.Key)
	}
	c.printf("subgoal %s: %s\n", cur.Key, status)
}

func itemNumber(v string) int64 {
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil {
		fail("%q is not an item number", v)
	}
	return n
}

func cmdItemAdd(c *call) {
	s := c.store
	sp := s.resolve(c.flag("sprint"))
	subgoal := s.pickSubgoal(sp.ID, c.flag("subgoal"), c.has("subgoal"), true)
	item := s.int("SELECT COALESCE(MAX(item), 0) + 1 FROM item_events WHERE sprint_id = ?", sp.ID)
	var before *float64
	if c.has("after") {
		p := s.latestItem(sp.ID, itemNumber(c.flag("after"))).Position
		before = &p
	}
	status, owner := "planned", "agent"
	if c.has("status") {
		status = c.flag("status")
	}
	if c.has("owner") {
		owner = c.flag("owner")
	}
	s.exec("INSERT INTO item_events (sprint_id, item, at, title, status, owner, position, note, subgoal) "+
		"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
		sp.ID, item, now(), c.pos["title"], status, owner, s.positionAfter("item_state", sp.ID, before),
		null(c.flag("note")), null(subgoal))
	c.printf("%d\n", item)
}

func cmdItemSet(c *call) {
	s := c.store
	sp := s.resolve(c.flag("sprint"))
	cur := s.latestItem(sp.ID, itemNumber(c.pos["item"]))
	title, status, owner, subgoal := cur.Title, cur.Status, cur.Owner, cur.Subgoal
	if c.has("title") {
		title = c.flag("title")
	}
	if v, ok := c.pos["status"]; ok {
		status = v
	}
	if c.has("owner") {
		owner = c.flag("owner")
	}
	if c.has("subgoal") {
		subgoal = s.pickSubgoal(sp.ID, c.flag("subgoal"), true, false)
	}
	s.exec("INSERT INTO item_events (sprint_id, item, at, title, status, owner, position, note, subgoal) "+
		"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
		sp.ID, cur.Item, now(), title, status, owner, cur.Position, null(c.flag("note")), null(subgoal))
	c.printf("item %d: %s\n", cur.Item, status)
}

func cmdBench(c *call) {
	s := c.store
	sp := s.resolve(c.flag("sprint"))
	v, err := strconv.ParseFloat(c.pos["value"], 64)
	if err != nil {
		fail("value must be a number, not %q", c.pos["value"])
	}
	s.exec("INSERT INTO bench_results (sprint_id, at, suite, metric, value, unit, is_baseline, commit_sha, link, subgoal) "+
		"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		sp.ID, now(), c.pos["suite"], c.pos["metric"], v, c.pos["unit"], c.has("baseline"),
		null(c.flag("commit")), null(c.flag("link")), null(s.pickSubgoal(sp.ID, c.flag("subgoal"), c.has("subgoal"), true)))
	c.printf("%s %s = %s %s\n", c.pos["suite"], c.pos["metric"], fmtNum(v), c.pos["unit"])
}

func cmdLog(c *call) {
	s := c.store
	sp := s.resolve(c.flag("sprint"))
	s.exec("INSERT INTO log (sprint_id, at, kind, text, link, subgoal) VALUES (?, ?, ?, ?, ?, ?)",
		sp.ID, now(), c.pos["kind"], c.pos["text"], null(c.flag("link")),
		null(s.pickSubgoal(sp.ID, c.flag("subgoal"), c.has("subgoal"), true)))
}

// readBody reads the section text before the write lock: stdin can be slow.
func readBody(c *call) {
	var data []byte
	var err error
	if c.flag("file") == "-" {
		data, err = io.ReadAll(os.Stdin)
	} else {
		data, err = os.ReadFile(c.flag("file"))
	}
	check(err)
	body := strings.TrimSpace(string(data))
	if body == "" {
		fail("empty section; use `sprint context rm` to remove one")
	}
	c.fetched = body + "\n"
}

func contextScope(c *call) (Sprint, string, *Context) {
	s := c.store
	sp := s.resolve(c.flag("sprint"))
	key := c.pos["key"]
	checkKey("section", key)
	subgoal := ""
	if c.flag("subgoal") != "" && c.flag("subgoal") != wholeSprint {
		subgoal = s.latestSubgoal(sp.ID, c.flag("subgoal")).Key
	}
	var cur *Context
	s.each("SELECT "+contextCols+" FROM context_versions WHERE sprint_id = ? AND subgoal IS ? AND key = ? "+
		"ORDER BY id DESC LIMIT 1", []any{sp.ID, null(subgoal), key}, func(r *sql.Rows) {
		ctx := scanContext(r)
		cur = &ctx
	})
	return sp, subgoal, cur
}

func cmdContextSet(c *call) {
	s := c.store
	sp, subgoal, cur := contextScope(c)
	live := cur != nil && cur.Body != ""
	title := c.flag("title")
	if title == "" && cur != nil {
		title = cur.Title
	}
	if title == "" {
		fail("new section %q needs --title", c.pos["key"])
	}
	var position float64
	switch {
	case c.has("first"):
		top, ok := s.float("SELECT MIN(position) FROM context_state WHERE sprint_id = ? AND subgoal IS ? AND key != ?",
			sp.ID, null(subgoal), c.pos["key"])
		position = top - 1
		if !ok {
			position = s.positionAfter("context_versions", sp.ID, nil)
		}
	case cur != nil:
		position = cur.Position
	default:
		position = s.positionAfter("context_versions", sp.ID, nil)
	}
	s.exec("INSERT INTO context_versions (sprint_id, subgoal, key, at, title, body, position) VALUES (?, ?, ?, ?, ?, ?, ?)",
		sp.ID, null(subgoal), c.pos["key"], now(), title, c.fetched.(string), position)
	verb := "added"
	if live {
		verb = "updated"
	}
	c.printf("section %s: %s\n", c.pos["key"], verb)
}

func cmdContextRm(c *call) {
	sp, subgoal, cur := contextScope(c)
	if cur == nil || cur.Body == "" {
		fail("no section %q here", c.pos["key"])
	}
	c.store.exec("INSERT INTO context_versions (sprint_id, subgoal, key, at, title, body, position) VALUES (?, ?, ?, ?, ?, '', ?)",
		sp.ID, null(subgoal), cur.Key, now(), cur.Title, cur.Position)
	c.printf("section %s: removed\n", cur.Key)
}

func cmdEnd(c *call) {
	sp := c.store.resolve(c.flag("sprint"))
	note := c.flag("note")
	if note == "" {
		note = "sprint ended"
	}
	c.store.exec("INSERT INTO log (sprint_id, at, kind, text) VALUES (?, ?, 'end', ?)", sp.ID, now(), note)
	c.printf("ended %s\n", sp.Slug)
}

func cmdList(c *call) {
	open := map[int64]bool{}
	for _, sp := range c.store.openSprints() {
		open[sp.ID] = true
	}
	c.store.each("SELECT "+sprintCols+" FROM sprints ORDER BY started_at DESC", nil, func(r *sql.Rows) {
		sp := scanSprint(r)
		state := "ended"
		if open[sp.ID] {
			state = "open"
		}
		c.printf("%s\t%s\t%s\n", sp.Slug, state, sp.Title)
	})
}

type summaryItem struct {
	Item    int64  `json:"item"`
	Title   string `json:"title"`
	Status  string `json:"status"`
	Owner   string `json:"owner"`
	Subgoal any    `json:"subgoal"`
}

type summaryPR struct {
	URL     string `json:"url"`
	Title   string `json:"title"`
	State   string `json:"state"`
	Subgoal any    `json:"subgoal"`
}

type summarySubgoal struct {
	Key      string `json:"key"`
	Title    string `json:"title"`
	Goal     string `json:"goal"`
	DoneWhen any    `json:"done_when"`
	Status   string `json:"status"`
	Done     int64  `json:"done"`
	InScope  int64  `json:"in_scope"`
	Percent  int64  `json:"percent"`
	Page     string `json:"page"`
}

type summary struct {
	Sprint      string           `json:"sprint"`
	Title       string           `json:"title"`
	Goal        string           `json:"goal"`
	GoalVersion int64            `json:"goal_version"`
	Done        int64            `json:"done"`
	InScope     int64            `json:"in_scope"`
	Dropped     int64            `json:"dropped"`
	Percent     int64            `json:"percent"`
	DoNow       []summaryItem    `json:"do_now"`
	Items       []summaryItem    `json:"items"`
	PRs         []summaryPR      `json:"prs"`
	Subgoals    []summarySubgoal `json:"subgoals"`
	Page        string           `json:"page"`
}

func orNil(v string) any {
	if v == "" {
		return nil
	}
	return v
}

func makeSummary(s Store, sp Sprint) summary {
	out := summary{Sprint: sp.Slug, Title: sp.Title, Page: pageBase() + pagePath(sp.Slug, ""),
		DoNow: []summaryItem{}, Items: []summaryItem{}, PRs: []summaryPR{}, Subgoals: []summarySubgoal{}}
	s.one("SELECT text, versions FROM goal_current WHERE sprint_id = ?", []any{sp.ID}, &out.Goal, &out.GoalVersion)
	var pct float64
	s.one("SELECT done, in_scope, dropped, percent FROM progress WHERE sprint_id = ?", []any{sp.ID},
		&out.Done, &out.InScope, &out.Dropped, &pct)
	out.Percent = int64(pct)
	s.each("SELECT "+itemCols+" FROM item_state WHERE sprint_id = ? ORDER BY position", []any{sp.ID}, func(r *sql.Rows) {
		i := scanItem(r)
		si := summaryItem{i.Item, i.Title, i.Status, i.Owner, orNil(i.Subgoal)}
		out.Items = append(out.Items, si)
		if i.Owner == "user" && i.Status != "done" && i.Status != "dropped" {
			out.DoNow = append(out.DoNow, si)
		}
	})
	s.each("SELECT "+prCols+" FROM pr_state WHERE sprint_id = ? ORDER BY at", []any{sp.ID}, func(r *sql.Rows) {
		p := scanPR(r)
		out.PRs = append(out.PRs, summaryPR{p.URL, p.Title, p.State, orNil(p.Subgoal)})
	})
	s.each("SELECT g.key, g.title, g.goal, COALESCE(g.done_when, ''), g.status, p.done, p.in_scope, p.percent "+
		"FROM subgoal_state g JOIN subgoal_progress p ON p.sprint_id = g.sprint_id AND p.key = g.key "+
		"WHERE g.sprint_id = ? ORDER BY g.position", []any{sp.ID}, func(r *sql.Rows) {
		var g summarySubgoal
		var dw string
		var pct float64
		check(r.Scan(&g.Key, &g.Title, &g.Goal, &dw, &g.Status, &g.Done, &g.InScope, &pct))
		g.DoneWhen, g.Percent, g.Page = orNil(dw), int64(pct), pageBase()+pagePath(sp.Slug, g.Key)
		out.Subgoals = append(out.Subgoals, g)
	})
	return out
}

func cmdShow(c *call) {
	d := makeSummary(c.store, c.store.resolve(c.flag("sprint")))
	if c.has("json") {
		b, err := json.MarshalIndent(d, "", "  ")
		check(err)
		c.printf("%s\n", b)
		return
	}
	c.printf("%s (%s)\n", d.Title, d.Sprint)
	c.printf("Goal v%d: %s\n", d.GoalVersion, d.Goal)
	c.printf("Progress: %d%% (%d of %d done, %d dropped)\n", d.Percent, d.Done, d.InScope, d.Dropped)
	for _, g := range d.Subgoals {
		c.printf("  [%s] %s: %s (%d of %d done)\n", g.Status, g.Key, g.Title, g.Done, g.InScope)
	}
	if len(d.DoNow) > 0 {
		c.printf("Do now:\n")
		for n, i := range d.DoNow {
			c.printf("  %d. %s [%s]\n", n+1, i.Title, i.Status)
		}
	}
	for _, i := range d.Items {
		where := ""
		if i.Subgoal != nil {
			where = fmt.Sprintf(" (%s)", i.Subgoal)
		}
		c.printf("  #%d %-8s %-5s %s%s\n", i.Item, i.Status, i.Owner, i.Title, where)
	}
	for _, p := range d.PRs {
		c.printf("  PR %-7s %s\n", p.State, p.URL)
	}
	c.printf("%s\n", d.Page)
}

func fmtNum(v float64) string { return strconv.FormatFloat(v, 'g', -1, 64) }
