---
name: chun-sprint
description: Track long multi-PR work as a sprint (one goal) split into subgoals (stages with their own goal and exit check), in an append-only log (the `sprint` CLI) shown on a local Grafana dashboard. The dashboard holds the goal and every change to it, progress over time, the user's next steps, PRs, benchmarks, and agent-written context such as architecture, findings, and caveats. Use for /chun-sprint, when multi-PR work starts or a new stage of it starts, or when Chun asks for the timeline, overview, "what's next", "what's left", "how far along", or status during multi-PR work. Also use when Chun asks to see the sprints of another machine, such as the Mac's sprints from legion-nix.
---

# Chun sprint

The user must never ask for status twice, and must never lose the goal after steering. Record the work as it happens in the sprint log. The dashboard draws everything from that log, so nothing gets summarized away.

The log is `~/.local/state/sprint/sprint.db`. It is append-only: nothing is edited or deleted. The dashboard is Grafana at `http://127.0.0.1:3001`. Its "View" dropdown shows the whole sprint or one subgoal. `sprint show` prints the link for each. Run `sprint --help` and `sprint <command> --help` for every command. If `sprint` is not installed on this machine, say so and give the status in chat.

## Terms

| Term | Meaning | Example |
| --- | --- | --- |
| Sprint | One goal that takes days or weeks. The dashboard's "Whole sprint" view shows it. | Kubernetes backend for Grepbox |
| Subgoal | One stage of the sprint goal. It has its own goal, a "done when" check, a plan, and its own dashboard view. One or two are active at a time. | Parity; Hot snapshotting |
| Item | One step of the plan, in a subgoal. The user's own steps have `--owner user`. | Port the exec API |
| Context section | Markdown that explains the work: what a reader needs without the chat. | Architecture; Findings |

## New sprint or new subgoal

Before you record new work, run `sprint list` and `sprint show`. Then pick one:

| The new work | Do this |
| --- | --- |
| Serves the goal of an open sprint, as a new stage | Add a subgoal to that sprint |
| Has its own end result, which no open sprint's goal covers | Start a new sprint |
| Is one step of an active subgoal | `sprint item add`, not a subgoal |
| Is not clear | Ask with the question tool. Recommend one option first. |

Use the user's own words for each goal. Give each subgoal a "done when" check that you can verify, such as a test, a benchmark threshold, or a deploy. Confirm the goal and the subgoals with the question tool before you record them.

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

Add the plan of the active subgoal as items, in order. New items, PRs, benchmarks, and log entries go to the only active subgoal. When two subgoals are active, pass `--subgoal <key>`, or set `SPRINT_SUBGOAL=<key>` for the thread. Use `--subgoal -` for work that belongs to the whole sprint. One sprint can span repos and threads. Each thread passes `--sprint <slug>` or sets `SPRINT=<slug>` when more than one sprint is open.

Give the user's own steps (merges, deploys, wizard runs, tests on a device) `--owner user`, in the order the user must do them. Put each deploy or validation after the merge it follows. Put the step's copy-paste command in `--note`, in backticks, such as a rerun script or a wizard path. The "Do now" panel shows it.

## Steering

Each time the user steers, decide what the steer changes before you record it. If you are not sure, ask with the question tool.

| The steer changes | Command |
| --- | --- |
| The end result of the sprint (rare) | `sprint goal "<new goal>" --reason "<the user's words>"` |
| What the current stage delivers, or its exit check | `sprint sub set <key> --goal "<new>" [--done-when "<new>"] --reason "<the user's words>"` |
| A new stage, now or later | `sprint sub add <key> "<title>" --goal ... --done-when ... [--status active] [--after <key>]` |
| The focus: which stage is active | `sprint sub set <key> active` and `sprint sub set <other> planned` |
| The scope of a stage | `sprint item add` or `sprint item set <n> dropped --note "<why>"` |

Then add, drop, or move items (`sprint item set <n> --subgoal <key>`) to match.

## Record as you go

| Event | Command |
| --- | --- |
| Work on an item starts, is blocked, or ends | `sprint item set <n> doing\|blocked\|done\|dropped --note "<why>"` |
| New work appears | `sprint item add "<title>" [--owner user] [--after <n>]` |
| You open a PR | `sprint pr add <url>` |
| A PR passes the review gate (Greptile 5/5) | `sprint pr ready <url>` |
| A PR merges or closes | `sprint pr sync` |
| A benchmark run finishes | `sprint bench <suite> <metric> <value> <unit> [--baseline] [--commit <sha>] [--link <run>]` |
| A decision, deploy, or note | `sprint log decision\|deploy\|note "<what>" [--link <url>]` |
| You learn something a reader needs | `sprint context set <key> [--subgoal <key>] --file -` (see below) |
| A subgoal's "done when" check passes | `sprint sub set <key> done --reason "<the evidence>"`, then ask which subgoal is next |
| The sprint goal is met | `sprint end` |

Never re-add an old item or subgoal to rewrite it. Change its status, and drop it with a note if it no longer applies.

## Context sections

The charts show the numbers. Context sections show what the numbers mean. Keep them current, so that the user can read the dashboard instead of the chat. They show in the Context panel, in the order you add them. Start a section that agents keep current with "AI-written. Updated <date> <time> SGT." Write each section in ASD-STE100 Simplified Technical English, with Markdown tables, lists, and links to code and runs.

The template sets which sections each view has (see "The template" above).

- Findings so far: 3 to 6 bullets. Start each with the conclusion in bold. Then give its cause, or write "cause not measured yet". Link the evidence: a run, a report, or a file.
- Decisions waiting for Chun: each open decision with your recommendation first. Ask about it with the question tool too.
- Not measured yet and Caveats: what the numbers do not show, and why a result can mislead.

Replace a section with `sprint context set <same key>`. The old version stays in the log. Use `--first` to put a section at the top of its view. Remove a section that no longer applies with `sprint context rm <key>`. Update a section when its facts change, not on every step. Keep secrets, customer names, and customer data out: the log stays on this machine, but the user shares screenshots.

## Live data

Everything an agent waits on or polls goes in the dashboard's Live section, so the user can see it without asking: a benchmark run, CI, a review bot, a deploy. Each item is a card with a progress bar, the end time in SGT, and a "stale" tag when updates stop. A subgoal view shows its own items and the whole sprint's. Live items live in `~/.local/state/sprint/live.db`, not in the append-only log, so you can update them in place.

| Need | Command |
| --- | --- |
| Poll a source every N seconds | `sprint poll <key> --every 60s --title "<title>" [--subgoal <key>] -- <cmd>` |
| A GitHub Actions run | `sprint poll ci --every 60s --title "CI" -- sprint probe gh-run <run url>` |
| A PR's review bots | `sprint poll review --every 2m --title "Review" -- sprint probe greptile <pr url> --until five` |
| A runner's log | `sprint poll bench --every 30s --title "Bench" -- sprint probe tail <file> --until '<done regex>'` |
| Keep the PR board current | `sprint poll prs --every 3m --title "PR board sync" -- sprint pr sync` |
| One update by hand | `sprint live set <key> [--title ..] [--subgoal <key>\|-] [--progress 7/12] [--ends-at +45m] [--stale-after 3m] [--link <url>] --file -` |
| Finish or remove an item | `sprint live done <key>` (it stays 1 h), `sprint live rm <key>` |
| See pollers and items | `sprint poll ls`, `sprint live ls` |
| Stop a poller | `sprint poll stop <key>`. The card stays: then `live done` or `live rm` it. |

- `--title` is required for a new item. Flags you leave out keep their values. `-` clears `--progress`, `--ends-at`, `--stale-after` and `--link`. `--subgoal -` moves an item to the whole sprint.
- A poller runs detached and outlives your turn. Its files are in `~/.local/state/sprint/pollers/<sprint>/<key>.{json,pid,log}`. Running `sprint poll` again with the same key replaces the poller. `--stale-after` defaults to 3 times `--every`.
- For a source without a probe, write a small script. It prints Markdown, or JSON `{"body", "progress": "7/12", "ends_at", "title", "link"}`. Exit 100 when the wait is over. Any other non-zero exit, or a timeout, keeps the last body and shows the error on the card. Set `ends_at` whenever you can estimate it.

The PR board comes from the log: `sprint pr sync` records each PR's review state. It shows only PRs tracked with `sprint pr add`, so add each PR when you open it. Set your next step for a PR with `sprint pr note <url> "<step>"` (`-` removes it).

### Change the dashboard

Edit `modules/home/sprint/dashboard.nix` in a dotnix worktree. Run `sprint dash dev --checkout <worktree> [--watch]`, and Grafana shows the change within 10 s, with no build or switch. The header shows "dev: <branch>@<sha>" (`+` means uncommitted) while a dev copy is live. Check it on `http://127.0.0.1:3001`, then open the PR. After you merge, `sprint dash reset` puts the built dashboard back. The next switch does the same. Data sources and Grafana settings still need a switch. To change the shape of every future sprint's context sections, edit `templates/` instead.

## Answer status questions

Run `sprint pr sync`, then `sprint show`. Reply in the chat with:

1. Where the work stands against the sprint goal, for a reader with no context.
2. The active subgoals with their progress (`3 of 5 done`), the items left in each, and their "done when" checks.
3. The "Do now" steps for the user, with their commands.
4. For running work, the time left and the expected end time in SGT.
5. The dashboard link from `sprint show`: the whole-sprint link, or the subgoal link when the question is about one stage.

List running agents with their task and status, because the dashboard doesn't show them.

## Another machine's sprints

Each machine has its own log and dashboard on `127.0.0.1`. The work Mac and legion-nix are on different tailnets, so a browser on one machine cannot open the other machine's dashboard. Chun decided to keep both dashboards off the network. Use T3 to show the other machine's sprints as a snapshot:

1. Call `t3_environment_links`. Find the other machine: "Chun's MacBook Pro" or "legion-nix". If it is missing or expired, call `t3_environment_link` with the machine name as the hint.
2. Start one read-only child there with `delegate_task`, `mode: "wait"`, and `target.environmentId`. Tell it to run `sprint list`, then `sprint show --json --sprint <slug>` for each open sprint (or only the one Chun named), and to return the raw JSON. It must not run `sprint pr sync` or write to the log.
3. Render the JSON as one HTML page with `html_render`, in the layout of the dashboard: "Do now" first, then subgoals with progress bars and open PRs. `sprint show --json` has no context sections. A large sprint gives about 100 KB of JSON, so the harness saves the result to a file: read it from there. Say which machine the page came from and when.
4. The dashboard links in the JSON point to the other machine's `127.0.0.1`. Don't present them as links. Say they open only on that machine.

The snapshot does not update itself. Make a new one when Chun asks again.
