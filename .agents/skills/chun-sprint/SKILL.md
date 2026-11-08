---
name: chun-sprint
description: Track long multi-PR work as a sprint (one goal) split into subgoals (stages with their own goal and exit check), in an append-only log (the `sprint` CLI) shown on a local Grafana dashboard. The dashboard holds the goal and every change to it, progress over time, the user's next steps, PRs, benchmarks, and agent-written context such as architecture, findings, and caveats. Use for /chun-sprint, when multi-PR work starts or a new stage of it starts, or when Chun asks for the timeline, overview, "what's next", "what's left", "how far along", or status during multi-PR work. Also use when Chun asks to see the sprints of another machine, such as the Mac's sprints from legion-nix. One T3 thread, "Sprint dashboard", writes the log and keeps the dashboard current; every other thread sends it updates.
---

# Chun sprint

The user must never ask for status twice, and must never lose the goal after steering. Record the work as it happens in the sprint log. The dashboard draws everything from that log, so nothing gets summarized away.

One T3 thread, the **dashboard thread**, writes the log. Every other thread (a **work thread**) sends it the events as they happen. See "The dashboard thread" below. This applies to every write in this skill: the command tables below are what the dashboard thread runs.

The log is `~/.local/state/sprint/sprint.db`. It is append-only: nothing is edited or deleted. The dashboard is Grafana at `http://127.0.0.1:3001`. Its "View" dropdown shows the whole sprint or one subgoal. `sprint show` prints the link for each. Run `sprint --help` and `sprint <command> --help` for every command. If `sprint` is not installed on this machine, say so and give the status in chat.

## Terms

| Term | Meaning | Example |
| --- | --- | --- |
| Sprint | One goal that takes days or weeks. The dashboard's "Whole sprint" view shows it. | Kubernetes backend for Grepbox |
| Subgoal | One stage of the sprint goal. It has its own goal, a "done when" check, a plan, and its own dashboard view. One or two are active at a time. | Parity; Hot snapshotting |
| Item | One step of the plan, in a subgoal. The user's own steps have `--owner user`. | Port the exec API |
| Context section | Markdown that explains the work: what a reader needs without the chat. | Architecture; Findings |
| Dashboard thread | The one T3 thread, titled `Sprint dashboard`, that runs every `sprint` command that writes. It does no other work. | |
| Work thread | Any other thread that works on a sprint. It reads the log and sends updates to the dashboard thread. | The thread that ports the exec API |

## The dashboard thread

Chun runs one long-lived T3 thread whose only job is the sprint log and the dashboard. Only this thread writes. This keeps one order for Do now, one owner for each poller, and no two threads that replace the same context section.

| The dashboard thread owns | Commands |
| --- | --- |
| Sprints, goals, subgoals, and items, with the Do now order | `start`, `goal`, `sub add\|set`, `item add\|set`, `end` |
| PRs and the PR board | `pr add\|set\|ready\|sync\|note\|ignore` |
| Benchmarks and the log | `bench`, `bench rm`, `log` |
| Context sections, with the "Threads" section | `context set\|rm`, `seed.sh` |
| The Live section and every poller | `live set\|done\|rm`, `poll`, `poll stop` |
| Changes to the dashboard layout | `dash dev`, `dash reset`, edits to `modules/home/sprint/` |

A work thread runs only commands that read: `sprint list`, `sprint show [--json]`, `sprint context ls`, `sprint live ls`, `sprint poll ls`, `sprint pr ignore` with no argument, and `sprint dash check`. It never writes, also not for a one-line fix. If it can't reach the dashboard thread, it tells Chun and keeps the events to send later.

Each machine has its own log, so each machine with an open sprint has its own dashboard thread. Most sprints are on the Mac.

### Find the dashboard thread

1. Call `t3_thread_list` with `allProjects: true` and `titleContains: "Sprint dashboard"`. To reach the log on another machine, add that machine's `environmentId` (from `t3_environment_links`).
2. If there is one, use its `threadId`. If there are more than one, use the newest, and tell Chun which ones to close.
3. If there is none, start it with `t3_thread_launch`: `title: "Sprint dashboard"`, the dotnix project (`t3_project_list`), `workspaceStrategy: {"type": "root"}`, and the message "Use the chun-sprint skill. You are the dashboard thread. Run its start-up steps." Give Chun its `link`.

### Send an update (work thread)

Send in the same turn as the event, with `t3_thread_send`, `mode: "queue"`. Queue mode gives each update its own turn, so an update never cuts into the one before it. Put all events of one turn in one message. Use this shape, and leave out lines that don't apply:

```text
sprint-update
sprint: <slug>    subgoal: <key, or - for the whole sprint>
from: <your thread title>, branch <branch>, <machine>
events:
- item <n> doing|done|dropped: <why>
- item <n> waits on: <person or outside event, in words> | <why>
- item <n> waits on nothing: <why>
- item <n> needs: <item n> | nothing
- item <n> merges: <pr url or #N> | nothing
- new item [owner user] [after <n>] [needs <n>] [waits on <who or what>]: <step, condition first> | note: `<command>`
- pr opened: <url>
- pr ready (Greptile 5/5): <url>
- pr next step: <url> | <step>
- bench: <suite> <metric> <value> <unit> [baseline] | commit <sha> | link <run>
- decision|deploy|note: <what> | link <url>
- finding for "<context section>": <Markdown: conclusion in bold, cause, evidence link>
- wait: <title> | every <interval> | `<probe command>` | ends about <HH:MM SGT>
- wait over: <title>
- subgoal done: <key> | evidence: <test, run, or deploy>
- steer (Chun confirmed): "<Chun's words>" | changes: <goal, stage, focus, or scope>
- new sprint or subgoal (Chun confirmed): <slug or key> | goal: <goal> | done when: <check> | plan: <items, in order>
- thread: <what you work on now> | <working | waiting on X | done>
```

Write facts, not commands. Give item numbers from `sprint show` when you know them. Don't send `item <n> done` for a step that merges a PR: `sprint pr sync` closes it when the PR merges (see "Merge steps follow GitHub"). The dashboard thread picks the commands, the order, and the item numbers. Don't wait for a reply: it replies only when it can't apply an event.

### Run the dashboard thread

At start, and when Chun restarts it:

1. Rename the thread to `Sprint dashboard` with `t3_thread_update` if its title is different.
2. Run `sprint list`, then `sprint show` for each open sprint.
3. Make sure each open sprint has a PR board poller (`sprint poll ls`). If one is missing, start it: `sprint poll prs --every 3m --background --title "PR board sync" -- sprint pr sync`.
4. Make sure each open sprint has a "Threads" context section (see below).

For each `sprint-update` message:

1. Apply each event with the commands in this skill. Use `sprint show` to find item numbers, the stage, and where a new step goes.
2. Keep Do now in the order Chun must act. When a new user step changes the order, move it with `sprint item set <n> --first` or `--after <n>`. Follow "Shared rules" for each user step.
3. For each `wait`, start or replace its poller with `sprint poll`, and pick a key from the title. For each `wait over`, run `sprint poll stop <key>` and `sprint live done <key>`.
4. For each `finding`, update that context section when the finding changes its facts.
5. After a PR event, run `sprint pr sync`. Don't mark a merge step done or dropped by hand: sync does it from GitHub.
6. Update the "Threads" section.
7. When you change the layout or add a kind of section, run `sprint dash check`.
8. End the turn with one line that says what changed.

If an event is not clear, names an item that doesn't exist, or changes a goal without Chun's yes, don't guess. Send a question back to the sender with `t3_thread_send` (find it with `t3_thread_search` on its title or branch), and apply the other events.

At the start of each turn, check the "Threads" section. When a thread marked "working" has sent nothing for 2 hours, read its last messages with `t3_thread_read` (`limit: 5`, `maxCharsPerItem: 2000`). Record what it did not send, and mark it "done" if it finished.

Chun can also talk to the dashboard thread: to steer, to ask for status, or to change the layout. Handle that as in the sections below.

### The "Threads" section

The dashboard thread keeps one context section, key `threads`, title "Threads on this sprint", in the whole-sprint view. It is a table with one row per work thread: thread title, machine, subgoal, task, state (working, waiting on X, or done), and the last update in SGT. Keep "done" rows for 24 hours, then remove them. This section answers "what is running" on the dashboard.

## New sprint or new subgoal

Before you record new work, run `sprint list` and `sprint show`. Then pick one:

| The new work | Do this |
| --- | --- |
| Serves the goal of an open sprint, as a new stage | Add a subgoal to that sprint |
| Has its own end result, which no open sprint's goal covers | Start a new sprint |
| Is one step of an active subgoal | `sprint item add`, not a subgoal |
| Is not clear | Ask with the question tool. Recommend one option first. |

Use the user's own words for each goal. Give each subgoal a "done when" check that you can verify, such as a test, a benchmark threshold, or a deploy. Confirm the goal and the subgoals with the question tool before you record them. The thread that talks with Chun asks. A work thread then sends a "new sprint or subgoal" event, and the dashboard thread runs the commands below.

### Start a sprint

```bash
sprint start <slug> "<title>" --goal "<sprint goal>"
sprint sub add <key> "<title>" --goal "<stage goal>" --done-when "<check>" --status active
sprint sub add <key> "<title>" --goal "<stage goal>" --done-when "<check>"      # later stages
SPRINT=<slug> ~/.agents/skills/chun-sprint/templates/seed.sh sprint
SPRINT=<slug> ~/.agents/skills/chun-sprint/templates/seed.sh subgoal <key>      # each subgoal
```

### Add a subgoal

```bash
sprint sub add <key> "<title>" --goal "<stage goal>" --done-when "<check>" [--status active] [--after <key>]
~/.agents/skills/chun-sprint/templates/seed.sh subgoal <key>
```

Then add the subgoal's plan as items, in order.

### The template

`templates/` (in this skill's folder, `~/.agents/skills/chun-sprint/templates/`) holds the context sections that every sprint and subgoal starts with. It copies the layout of the k8s-sandbox sprint. `seed.sh` adds the sections in order, and skips a section that already exists.

| Scope | Sections, in order |
| --- | --- |
| Whole sprint (`templates/sprint/`) | Findings so far; Decisions waiting for Chun; Architecture; Environment; How to run it; Risks and open questions |
| One subgoal (`templates/subgoal/`) | Findings so far; Approach; Not measured yet; Caveats |
| Add when needed (`templates/optional/`) | What blocks `<milestone>` (whole sprint, `--first`); Comparison with `<reference>` (parity work); What's left (when the items don't show the order) |

Add an optional section with `sprint context set <key> --title "<title>" [--subgoal <key>] --file ~/.agents/skills/chun-sprint/templates/optional/<key>.md`, then fill it in. Replace every `<placeholder>` and `{{now}}` in the turn you seed it. If you can't fill a section yet, write "Not known yet" and what will tell you. Never leave a placeholder on the dashboard. To change the shape for every future sprint, edit `templates/`, not one sprint's sections.

### Shared rules

Add the plan of the active subgoal as items, in order. New items, PRs, benchmarks, and log entries go to the only active subgoal. When two subgoals are active, pass `--subgoal <key>`. Use `--subgoal -` for work that belongs to the whole sprint. One sprint can span repos and threads. Each update names its sprint and subgoal, and the dashboard thread passes `--sprint <slug>` when more than one sprint is open.

Give the user's own steps (merges, deploys, wizard runs, tests on a device) `--owner user`, in the order the user must do them. Put each deploy or validation after the merge it follows. Give each step one action. Put its condition first, then the action: "When #18259 scores 5/5, run the Datadog wizard", then a separate step "Merge #18259". Never join two actions in one step with "then" or "after". Put the step's copy-paste command in `--note`, in backticks, such as a rerun script or a wizard path. If the order is not obvious, say why in the note. The "Do now" panel shows it.

Record what a user step waits for, not only in its title, so Do now shows only the steps Chun can do now:

| The step can't start until | Flag |
| --- | --- |
| A person or an outside event: James, a code owner's approval, a reviewer, the next staging release | `--waits-on "<who or what, in words>"`, such as `--waits-on "a code owner's approval on #18620"` |
| An earlier step is done or dropped | `--needs <item number>` |
| GitHub lets its PR merge (the PR board puts it in Merge now) | `--merges <pr url or #N>`; `pr sync` sets it for "merge #N" titles |

`sprint item set` keeps all three until you clear them with `--waits-on -`, `--needs -`, or `--merges -`. Clear `--waits-on` when the person acts. `--needs` clears itself in effect: the step is ready once the needed item is done or dropped. `--needs` must name an item of the sprint and must not make a loop. Use `--waits-on` instead of the old `blocked` status; a step still marked `blocked` counts as waiting, with its reason in its note.

The `do_now` view gives each open user step a state, and `sprint show` prints it:

| State | When | Where it shows |
| --- | --- | --- |
| `ready` | Nothing below applies | A numbered card in Do now, and the Timeline when it is part of a chain |
| `waiting` | `waits_on` is set, or the status is `blocked` | The Timeline, orange, with what it waits on and since when: `[waiting on James]` |
| `later` | `needs` names an item that is not done or dropped | The Timeline, dashed, after the step it needs: `[after #260]` |
| `waiting` | The step merges a PR, and the PR board does not put the PR in Merge now | The Timeline, orange, with the board's reasons and a link to the PR: `[waiting: GitHub: Needs an approval]` |

The rows apply in this order: a person or event the step waits on, then `needs`, then GitHub. A merge step whose PR has no board row yet is `ready`.

Do now ranks ready steps first, then waiting, then later, and a step keeps its number in every view. Under its cards, Do now counts the steps that wait on others or come later. The Timeline panel draws each chain of `needs` links as one track, left to right: the last two done steps with their done times, then the open steps. A lone waiting step is a track of its own.

## Steering

Each time the user steers, decide what the steer changes before you record it. If you are not sure, ask with the question tool. The thread where Chun steers decides and asks. A work thread then sends a "steer" event with Chun's words, and the dashboard thread runs the command.

| The steer changes | Command |
| --- | --- |
| The end result of the sprint (rare) | `sprint goal "<new goal>" --reason "<the user's words>"` |
| What the current stage delivers, or its exit check | `sprint sub set <key> --goal "<new>" [--done-when "<new>"] --reason "<the user's words>"` |
| A new stage, now or later | `sprint sub add <key> "<title>" --goal ... --done-when ... [--status active] [--after <key>]` |
| The focus: which stage is active | `sprint sub set <key> active` and `sprint sub set <other> planned` |
| The scope of a stage | `sprint item add` or `sprint item set <n> dropped --note "<why>"` |

Then add, drop, or move items (`sprint item set <n> --subgoal <key>`) to match.

## Record as you go

A work thread sends the event in the left column. The dashboard thread runs the command.

| Event | Command |
| --- | --- |
| Work on an item starts or ends | `sprint item set <n> doing\|done\|dropped --note "<why>"` |
| A step starts or stops waiting on someone | `sprint item set <n> --waits-on "<who or what>"`, or `--waits-on -` |
| A step can start only after another | `sprint item set <n> --needs <item>`, or `--needs -` |
| A step merges a PR that sync did not link | `sprint item set <n> --merges <pr url or #N>`, or `--merges -` |
| New work appears | `sprint item add "<title>" [--owner user] [--after <n>] [--needs <n>] [--waits-on "<who or what>"] [--merges <pr url or #N>]` |
| You open a PR | `sprint pr add <url>` |
| A PR belongs to another stage, or has none | `sprint pr set <url> --subgoal <key>` (`-` for the whole sprint) |
| A PR passes the review gate (Greptile 5/5) | `sprint pr ready <url>` |
| A PR merges or closes | `sprint pr sync`; it closes the steps that merge the PR |
| A benchmark run finishes | `sprint bench <suite> <metric> <value> <unit> [--baseline] [--commit <sha>] [--link <run>]` |
| A decision, deploy, or note | `sprint log decision\|deploy\|note "<what>" [--link <url>]` |
| You learn something a reader needs | `sprint context set <key> [--subgoal <key>] --file -` (see below) |
| A subgoal's "done when" check passes | `sprint sub set <key> done --reason "<the evidence>"`, then ask which subgoal is next |
| The sprint goal is met | `sprint end` |

Never re-add an old item or subgoal to rewrite it. Change its status, and drop it with a note if it no longer applies.

## Context sections

The charts show the numbers. Context sections show what the numbers mean. Keep them current, so that the user can read the dashboard instead of the chat. They show in the Context panel, in the order you add them. Start a section that agents keep current with "AI-written. Updated <date> <time> SGT." Write each section in ASD-STE100 Simplified Technical English, with Markdown tables, lists, and links to code and runs.

The template sets which sections each view has (see "The template" above). Work threads send what they learn as "finding" events. The dashboard thread writes the sections, so the AI-written stamp shows when it last wrote them.

- Findings so far: 3 to 6 bullets. Start each with the conclusion in bold. Then give its cause, or write "cause not measured yet". Link the evidence: a run, a report, or a file.
- Decisions waiting for Chun: each open decision with your recommendation first. Ask about it with the question tool too.
- Not measured yet and Caveats: what the numbers do not show, and why a result can mislead.

Replace a section with `sprint context set <same key>`. The old version stays in the log. Use `--first` to put a section at the top of its view. Remove a section that no longer applies with `sprint context rm <key>`. Update a section when its facts change, not on every step. Keep secrets, customer names, and customer data out: the log stays on this machine, but the user shares screenshots.

## Live data

Everything an agent waits on or polls goes in the dashboard's Live section, so the user can see it without asking: a benchmark run, CI, a review bot, a deploy. A work thread sends a "wait" event with the probe command from the table below. The dashboard thread starts and stops the poller. A work thread can still poll for its own use, but only the dashboard thread writes to the Live section. Each item is a card with a progress bar, the end time in SGT, and a "stale" tag when updates stop. A subgoal view shows its own items and the whole sprint's. Live items live in `~/.local/state/sprint/live.db`, not in the append-only log, so you can update them in place.

| Need | Command |
| --- | --- |
| Poll a source every N seconds | `sprint poll <key> --every 60s --title "<title>" [--subgoal <key>] -- <cmd>` |
| A GitHub Actions run | `sprint poll ci --every 60s --title "CI" -- sprint probe gh-run <run url>` |
| A PR's review bots | `sprint poll review --every 2m --title "Review" -- sprint probe greptile <pr url> --until five` |
| A runner's log | `sprint poll bench --every 30s --title "Bench" -- sprint probe tail <file> --until '<done regex>'` |
| Keep the PR board current | `sprint poll prs --every 3m --background --title "PR board sync" -- sprint pr sync` |
| One update by hand | `sprint live set <key> [--title ..] [--subgoal <key>\|-] [--progress 7/12] [--ends-at +45m] [--stale-after 3m] [--link <url>] --file -` |
| Finish or remove an item | `sprint live done <key>` (it stays 1 h), `sprint live rm <key>` |
| See pollers and items | `sprint poll ls`, `sprint live ls` |
| Stop a poller | `sprint poll stop <key>`. The card stays: then `live done` or `live rm` it. |

- `--title` is required for a new item. Flags you leave out keep their values. `-` clears `--progress`, `--ends-at`, `--stale-after` and `--link`. `--subgoal -` moves an item to the whole sprint.
- A poller runs detached and outlives your turn. Its files are in `~/.local/state/sprint/pollers/<sprint>/<key>.{json,pid,log}`. Running `sprint poll` again with the same key replaces the poller. `--stale-after` defaults to 3 times `--every`.
- For a source without a probe, write a small script. It prints Markdown, or JSON `{"body", "progress": "7/12", "ends_at", "title", "link"}`. `progress` is a string, not a number. A field with the wrong type is skipped and shows as an error on the card; the other fields still apply. Exit 100 when the wait is over. Any other non-zero exit, or a timeout, keeps the last body and shows the error on the card. Set `ends_at` whenever you can estimate it.

The PR board comes from the log: `sprint pr sync` records each PR's review state. Add each PR with `sprint pr add` when you open it, so it gets its stage. Set your next step for a PR with `sprint pr note <url> "<step>"` (`-` removes it).

`sprint pr sync` also triages, so no open PR is missed:

- It lists your open PRs in each GitHub repository the sprint already tracks a PR in, and adds each one new to the log with no stage. It skips a PR that another open sprint tracks, and a PR whose head branch, title, or URL matches one of the sprint's ignore patterns (`sprint pr ignore '<regexp>'`; `--rm` removes one; no argument lists them).
- While the sprint has stages, a PR with no stage shows "Needs a stage" on the PR board and in `sprint show`. Give it one with `sprint pr set <url> --subgoal <key>`.
- It adds your steps to Do now: "Merge #N: <title>" on the PR's stage when the board puts the PR in Merge now and no open step of yours names `#N` or merges it, and "Pick a stage for #N: <title>" for a PR with no stage. It adds each step once per PR. It marks a "Pick a stage" step done when the PR merges, closes, or gets a stage. Its steps carry the note "Added by sprint pr sync: ...". Drop a step you don't want; sync does not add it again.

### Merge steps follow GitHub

A user step that merges a PR records the PR in `merges`. Each `sprint pr sync` keeps these steps in step with GitHub, so Do now and the Timeline never show a merged PR as a step:

- It links each open step of yours that has no `merges` and says to merge one tracked PR: the title names exactly one tracked PR after its last word "merge". "Merge #18624 (pins the AMI)" and "After #18620 merges: merge #18621" link. "Merge #18132, #18139 in order" and "Merge #18479 after #18232" name two PRs and stay unlinked: set `--merges` by hand if one of them is the step's PR. The link keeps the step's note. The "Merge #N" steps sync adds are linked when it adds them.
- When the PR merges, it marks the step done with the note "Merged <time> SGT (pr sync)". When the PR closes without a merge, it drops the step with the note "#N closed without merging (pr sync)". It writes each change once. To keep a step open after its PR merges, clear its link with `--merges -`.
- While the board does not put the PR in Merge now, the step is `waiting`, and the Timeline and `sprint show` say why: "GitHub: 1 check still running; Needs an approval".

The PR board poller runs `sprint pr sync` every 3 minutes, so a merge shows in Do now within about 3 minutes. There is no GitHub webhook: a laptop has no public address that GitHub can call, and the poller already reads GitHub.

### Change the dashboard

The dashboard thread makes layout changes. A work thread that wants one sends a "note" event that says what to change and why.

Edit `modules/home/sprint/dashboard.nix` in a dotnix worktree. Run `sprint dash dev --checkout <worktree> [--watch]`, and Grafana shows the change within 10 s, with no build or switch. The header shows "dev: <branch>@<sha>" (`+` means uncommitted) while a dev copy is live. Check it on `http://127.0.0.1:3001`. Then run `sprint dash check`, and open the PR only when it reports no problem.

Grafana gives each panel a fixed height, but the data sets how tall a section is. So `page/fit.js` fits each section into its panel: it folds items marked `.fit` and adds a "Show all" bar, and no panel scrolls on its own. In a new section, mark each repeated item (a card, a table row) `.fit`. `sprint dash check` renders every view of the open sprints in headless Chrome. It fails when a section didn't render, content is wider than its box, content is cut where the panel doesn't scroll, or a Live card shows raw JSON. It notes folds, cut sections, and large gaps. Use `--width` to check another window size, and `--open` to check with every list opened (Merged, Waiting, context sections). Opening a list shows the whole panel and lets it scroll, like Show all. After you merge, `sprint dash reset` puts the built dashboard back. The next switch does the same. Data sources and Grafana settings still need a switch. To change the shape of every future sprint's context sections, edit `templates/` instead.

## Answer status questions

Any thread can answer. Run `sprint show`. Don't run `sprint pr sync` in a work thread: the dashboard thread's PR board poller keeps PR states current. Reply in the chat with:

1. Where the work stands against the sprint goal, for a reader with no context.
2. The active subgoals with their progress (`3 of 5 done`), the items left in each, and their "done when" checks.
3. The "Do now" steps the user can do now (state `ready`), with their commands. Then, in one line each, the steps that wait on someone (and on whom) or come after another step.
4. For running work, the time left and the expected end time in SGT.
5. The dashboard link from `sprint show`: the whole-sprint link, or the subgoal link when the question is about one stage.

List the threads from the "Threads" section with their task and state, and your own subagents with theirs.

## Another machine's sprints

Each machine has its own log, dashboard thread, and dashboard on `127.0.0.1`. To record work in another machine's sprint, send the update to that machine's dashboard thread (see "Find the dashboard thread").

The work Mac and legion-nix are on different tailnets, so a browser on one machine cannot open the other machine's dashboard. Chun decided to keep both dashboards off the network. Use T3 to show the other machine's sprints as a snapshot:

1. Call `t3_environment_links`. Find the other machine: "Chun's MacBook Pro" or "legion-nix". If it is missing or expired, call `t3_environment_link` with the machine name as the hint.
2. Start one read-only child there with `delegate_task`, `mode: "wait"`, and `target.environmentId`. Tell it to run `sprint list`, then `sprint show --json --sprint <slug>` for each open sprint (or only the one Chun named), and to return the raw JSON. It must not run `sprint pr sync` or write to the log.
3. Render the JSON as one HTML page with `html_render`, in the layout of the dashboard: "Do now" first, then subgoals with progress bars and open PRs. `sprint show --json` has no context sections. A large sprint gives about 100 KB of JSON, so the harness saves the result to a file: read it from there. Say which machine the page came from and when.
4. The dashboard links in the JSON point to the other machine's `127.0.0.1`. Don't present them as links. Say they open only on that machine.

The snapshot does not update itself. Make a new one when Chun asks again.
