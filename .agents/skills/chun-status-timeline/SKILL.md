---
name: chun-status-timeline
description: Track long multi-PR work as a sprint in an append-only log (the `sprint` CLI) shown on a local Grafana dashboard, with the goal and every change to it, progress over time, the user's next steps in merge and deploy order, PRs, and benchmark results. Use for /chun-status-timeline, or when Chun asks for the timeline, overview, "what's next", "what's left", "how far along", or status during multi-PR work.
---

# Chun status timeline

The user should never have to ask for status twice, and never lose track of the goal after steering. Record the work as it happens in the sprint log. The dashboard draws everything from that log, so nothing gets summarized away.

The log is `~/.local/state/sprint/sprint.db`. It is append-only: nothing is edited or deleted. The dashboard is `http://127.0.0.1:3001/d/sprint/sprint`. Run `sprint --help` for every command. If `sprint` is not installed on this machine, say so and give the status in chat.

## Start

At the start of multi-PR work, start a sprint. Use the user's own words for the goal, and confirm it with the question tool.

```bash
sprint start <slug> "<title>" --goal "<goal in the user's words>"
```

One sprint can span repos. Each thread passes `--sprint <slug>` or sets `SPRINT=<slug>` when more than one sprint is open. Add the plan as items, in order. Give the user's own steps (merges, deploys, wizard runs, tests on a device) `--owner user`, in the order the user must do them. Put each deploy or validation after the merge it follows.

## Record as you go

| Event | Command |
| --- | --- |
| The user steers or changes scope | `sprint goal "<new goal>" --reason "<the user's words>"`, then add or drop items |
| Work on an item starts, is blocked, or ends | `sprint item set <n> doing\|blocked\|done\|dropped --note "<why>"` |
| New work appears | `sprint item add "<title>" [--owner user] [--after <n>]` |
| You open a PR | `sprint pr add <url>` |
| A PR passes the review gate (Greptile 5/5) | `sprint pr ready <url>` |
| A PR merges or closes | `sprint pr sync` |
| A benchmark run finishes | `sprint bench <suite> <metric> <value> <unit> [--baseline] [--commit <sha>]` |
| A decision or deploy | `sprint log decision\|deploy "<what>" [--link <url>]` |
| The goal is met | `sprint end` |

Never re-add an old item to rewrite it. Change its status, and drop it with a note if it no longer applies.

## Answer status questions

Run `sprint pr sync`, then `sprint show`. Reply with the progress line, the "Do now" steps, and the dashboard link. Don't repeat what the dashboard shows. List running agents with their task and status in the reply, because the dashboard doesn't show them.
