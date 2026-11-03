---
name: chun-status-timeline
description: Track long multi-PR work as a sprint (one goal) split into subgoals (stages with their own goal and exit check), in an append-only log (the `sprint` CLI) shown as local status pages. The pages hold the goal and every change to it, progress over time, the user's next steps, PRs, benchmarks, and agent-written context such as architecture, findings, and caveats. Use for /chun-status-timeline, or when Chun asks for the timeline, overview, "what's next", "what's left", "how far along", or status during multi-PR work.
---

# Chun status timeline

The user must never ask for status twice, and must never lose the goal after steering. Record the work as it happens in the sprint log. The status pages draw everything from that log, so nothing gets summarized away.

The log is `~/.local/state/sprint/sprint.db`. It is append-only: nothing is edited or deleted. The pages are at `http://127.0.0.1:3001`. Run `sprint --help` and `sprint <command> --help` for every command. If `sprint` is not installed on this machine, say so and give the status in chat.

## Terms

| Term | Meaning | Example |
| --- | --- | --- |
| Sprint | One goal that takes days or weeks. It has a goal page. | Kubernetes backend for Grepbox |
| Subgoal | One stage of the sprint goal. It has its own goal, a "done when" check, a plan, and a page. One or two are active at a time. | Parity; Hot snapshotting |
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

The pages show the numbers. Context sections show what the numbers mean. Keep them current, so that the user can read the page instead of the chat. Write each section in ASD-STE100 Simplified Technical English, with tables, lists, and links to code and runs. Markdown can hold inline SVG for diagrams.

| Page | Sections to keep |
| --- | --- |
| Goal page (no `--subgoal`) | Architecture (how the parts fit), How to run it, Environment (clusters, accounts, flags), Risks and open questions |
| Subgoal page (`--subgoal <key>`) | Approach, Findings so far, Comparison with the reference system (in parity work), Benchmark method and caveats, What is left |

Replace a section with `sprint context set <same key>`. The old version stays in the log. Remove a section that no longer applies with `sprint context rm <key>`. Update a section when its facts change, not on every step. Keep secrets, customer names, and customer data out: the log stays on this machine, but the user shares screenshots.

## Answer status questions

Run `sprint pr sync`, then `sprint show`. Reply with:

1. The active subgoals with their progress (`3 of 5 done`) and "done when" checks.
2. The "Do now" steps for the user.
3. The page link: the goal page, or the subgoal page when the question is about one stage.

Don't repeat what the page shows. List running agents with their task and status in the reply, because the page doesn't show them.
