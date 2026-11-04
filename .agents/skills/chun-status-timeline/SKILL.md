---
name: chun-status-timeline
description: Track long multi-PR work as a sprint (one goal) split into subgoals (stages with their own goal and exit check), in an append-only log (the `sprint` CLI) shown on a local Grafana dashboard and, on trial, a static HTML status page. The dashboard holds the goal and every change to it, progress over time, the user's next steps, PRs, benchmarks, and agent-written context such as architecture, findings, and caveats. Use for /chun-status-timeline, or when Chun asks for the timeline, overview, "what's next", "what's left", "how far along", or status during multi-PR work. Also use when Chun asks to see the sprints of another machine, such as the Mac's sprints from legion-nix.
---

# Chun status timeline

The user must never ask for status twice, and must never lose the goal after steering. Record the work as it happens in the sprint log. The dashboard draws everything from that log, so nothing gets summarized away.

The log is `~/.local/state/sprint/sprint.db`. It is append-only: nothing is edited or deleted. The dashboard is Grafana at `http://127.0.0.1:3001`. Its "View" dropdown shows the whole sprint or one subgoal. `sprint show` prints the link for each. Run `sprint --help` and `sprint <command> --help` for every command. If `sprint` is not installed on this machine, say so and give the status in chat.

## Terms

| Term | Meaning | Example |
| --- | --- | --- |
| Sprint | One goal that takes days or weeks. The dashboard's "Whole sprint" view shows it. | Kubernetes backend for Grepbox |
| Subgoal | One stage of the sprint goal. It has its own goal, a "done when" check, a plan, and its own dashboard view. One or two are active at a time. | Parity; Hot snapshotting |
| Item | One step of the plan, in a subgoal. The user's own steps have `--owner user`. | Port the exec API |
| Context section | Markdown that explains the work: what a reader needs without the chat. | Architecture; Findings |

## Start

At the start of multi-PR work, propose the sprint goal and the first subgoals. Use the user's own words. Give each subgoal a "done when" check that you can verify, such as a test, a benchmark threshold, or a deploy. Confirm with the question tool. Then:

```bash
sprint start <slug> "<title>" --goal "<sprint goal>"
sprint sub add <key> "<title>" --goal "<stage goal>" --done-when "<check>" --status active
sprint sub add <key> "<title>" --goal "<stage goal>" --done-when "<check>"      # later stages
sprint context set architecture --title "Architecture" --file - <<'MD'
...
MD
```

Add the plan of the active subgoal as items, in order. New items, PRs, benchmarks, and log entries go to the only active subgoal. When two subgoals are active, pass `--subgoal <key>`, or set `SPRINT_SUBGOAL=<key>` for the thread. Use `--subgoal -` for work that belongs to the whole sprint. One sprint can span repos and threads. Each thread passes `--sprint <slug>` or sets `SPRINT=<slug>` when more than one sprint is open.

Give the user's own steps (merges, deploys, wizard runs, tests on a device) `--owner user`, in the order the user must do them. Put each deploy or validation after the merge it follows.

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

The charts show the numbers. Context sections show what the numbers mean. Keep them current, so that the user can read the dashboard instead of the chat. They show in the Context panel, in the order you add them. Write each section in ASD-STE100 Simplified Technical English, with Markdown tables, lists, and links to code and runs.

| View | Sections to keep, in this order |
| --- | --- |
| Whole sprint (no `--subgoal`) | Findings so far; Decisions waiting for Chun; Architecture (how the parts fit); How to run it; Environment (clusters, accounts, flags); Risks and open questions |
| One subgoal (`--subgoal <key>`) | Findings so far; Approach; Comparison with the reference system (in parity work); Not measured yet; Caveats |

- Findings so far: 3 to 6 bullets. Start each with the conclusion in bold. Then give its cause, or write "cause not measured yet". Link the evidence: a run, a report, or a file.
- Decisions waiting for Chun: each open decision with your recommendation first. Ask about it with the question tool too.
- Not measured yet and Caveats: what the numbers do not show, and why a result can mislead.

Replace a section with `sprint context set <same key>`. The old version stays in the log. Use `--first` to put a section at the top of its view. Remove a section that no longer applies with `sprint context rm <key>`. Update a section when its facts change, not on every step. Keep secrets, customer names, and customer data out: the log stays on this machine, but the user shares screenshots.

## Static status page (trial)

Chun is comparing two status views. Keep a static HTML page beside the dashboard until Chun picks one.

- Write one generator script per sprint, `/tmp/status/sprint-<slug>/gen.py`. It reads `sprint show --json` and the log (read-only). It also reads live sources that the log doesn't hold, such as a runner's log or the review scores of open PRs. It writes `/tmp/status/sprint-<slug>/index.html`.
- Show the dashboard's facts from the same log, so the two views never disagree: the goal, each subgoal with a progress bar and its "done when" check, "Do now", the open steps in order, benchmarks (latest run against baseline, and how many are within 5%), open PRs with their review verdict, and the context sections. Add live run progress, which the dashboard can't show.
- Follow the **dataviz** skill. Support light and dark mode. Put "Do now" at the top.
- Run the generator every 60 s in a detached loop, `/tmp/status/sprint-<slug>/loop.sh`. Record its PID. The page reloads itself every 30 s.
- Serve `/tmp/status` on `http://localhost:8800`. If nothing listens there, start `python3 -m http.server 8800 --bind 127.0.0.1 --directory /tmp/status` detached, and record its PID.
- After Chun has used both views for a few status answers, ask with the question tool which one to keep.

## Answer status questions

Run `sprint pr sync`, then `sprint show`. Reply with:

1. The active subgoals with their progress (`3 of 5 done`) and "done when" checks.
2. The "Do now" steps for the user.
3. Both links: the dashboard link from `sprint show` (the whole-sprint link, or the subgoal link when the question is about one stage) and the static page.

Don't repeat what the dashboard shows. List running agents with their task and status in the reply, because the views don't show them.

## Another machine's sprints

Each machine has its own log and dashboard on `127.0.0.1`. The work Mac and legion-nix are on different tailnets, so a browser on one machine cannot open the other machine's dashboard. Chun decided to keep both dashboards off the network. Use T3 to show the other machine's sprints as a snapshot:

1. Call `t3_environment_links`. Find the other machine: "Chun's MacBook Pro" or "legion-nix". If it is missing or expired, call `t3_environment_link` with the machine name as the hint.
2. Start one read-only child there with `delegate_task`, `mode: "wait"`, and `target.environmentId`. Tell it to run `sprint list`, then `sprint show --json --sprint <slug>` for each open sprint (or only the one Chun named), and to return the raw JSON. It must not run `sprint pr sync` or write to the log.
3. Render the JSON as one HTML page with `html_render`, in the layout of the static status page: "Do now" first, then subgoals with progress bars and open PRs. `sprint show --json` has no context sections. A large sprint gives about 100 KB of JSON, so the harness saves the result to a file: read it from there. Say which machine the page came from and when.
4. The dashboard links in the JSON point to the other machine's `127.0.0.1`. Don't present them as links. Say they open only on that machine.

The snapshot does not update itself. Make a new one when Chun asks again.
