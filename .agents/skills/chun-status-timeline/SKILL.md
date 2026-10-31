---
name: chun-status-timeline
description: Keep a live status timeline for long multi-PR work as an auto-reloading HTML dashboard on localhost, with done-today, the user's next steps in merge and deploy order, a merge verdict per open PR, running agents, and key links. Use for /chun-status-timeline, or when Chun asks for the timeline, overview, "what's next", "what's left", or status during multi-PR work.
---

# Chun status timeline

The user should never have to ask for status twice. Keep one live page that answers "what's done and what do I do next?" at a glance.

## Page

One page per project at `/tmp/status/<project>/index.html`. Use the repo or feature name for `<project>`. Build it from live state: `gh pr view`, `gh pr checks`, review bot scores, agent status, and deploy output. Never build it from memory.

Put these on the page, top to bottom:

1. **Do now.** The single next action for the user, with its link or command.
2. **Timeline.** One ordered list of the user's remaining steps. Each merge is a step. Place each deploy, wizard run, or validation after the merge it follows. Mark steps done, next, waiting, or blocked.
3. **Open PRs.** One row per PR in merge order: number and link, title, and a merge verdict. The verdict is "ready" or what the PR waits on: bot scores (`greptile`, `greptile-staging`), approvals, required checks, a deploy, or an earlier PR.
4. **Done today.** Merges, deploys, and decisions, newest first.
5. **Agents.** Each running agent with its task, status, and thread link.
6. **Links.** Key docs, wizards, dashboards, and reports.

Add `<meta http-equiv="refresh" content="30">` and an "updated at" time. Follow the chun-mode reply rules for prose. Use the **dataviz** skill for any chart.

## Serve it

Serve `/tmp/status` on localhost port 8800:

```bash
curl -fsS -o /dev/null http://localhost:8800/ \
  || python3 -m http.server 8800 --bind 127.0.0.1 --directory /tmp/status
```

Start the server as a background task so it outlives the turn. If the port already answers, reuse that server. Bind to `127.0.0.1` only. Give the user `http://localhost:8800/<project>/` once, when you create the page.

## Update it

Rewrite the page after each of these events:

- A PR merges, opens, or changes its merge verdict.
- A deploy or wizard run starts, finishes, or fails.
- An agent finishes or gets blocked.
- The user makes a decision.

Rewrite the whole file from live state each time. Don't patch it by hand.

When the user asks for status, refresh the page first. Then reply with the URL and the "Do now" step only. Don't post chat messages for updates the page already shows.
