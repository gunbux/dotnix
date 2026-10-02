---
name: goal
description: Use when the user invokes $goal or explicitly asks to set, inspect, pause, or resume a persistent goal and keep working until a completion condition is verified. Do not activate for ordinary task requests or discussions of goals.
---

# Goal

Treat the user's objective as a completion condition. Keep making concrete progress until it is verified, the user pauses or cancels, a requested budget is exhausted, or progress requires user input or an external change.

## Invocation

- `$goal <condition>` sets a goal and starts work immediately.
- `$goal status` reports the objective, progress, remaining checks, and blockers.
- `$goal pause` stops goal work and preserves the checkpoint.
- `$goal resume` resumes the saved objective from the next unfinished step.
- `$goal clear` cancels the goal without undoing completed work.

These are instructions through the skill, not a registration of native slash commands. In Claude Code, leave the built-in `/goal` command to the client.

## Establish the goal

Read the requested condition and existing goal state. Turn the condition into observable acceptance criteria without expanding its scope. Ask only when ambiguity would materially change the work. State the condition briefly, then act; setting a goal does not require a second confirmation.

Use native goal tools when available. Inspect state with `get_goal` before `create_goal`, and pass a token budget only when the user explicitly requests one. Do not replace an unfinished native goal silently. Follow the tools' supported transitions and host instructions. If pause, resume, cancellation, or a budget change requires client controls, explain the exact limitation instead of inventing an API or marking incomplete work complete.

Without native goal tools, keep a checkpoint in the conversation. Include the objective, acceptance criteria, status, verified progress, next action, and blocker. Preserve it across compaction. If the user requests persistence across sessions, save it to a user-approved writable location, with separate records for separate conversations. Do not put credentials in checkpoints or modify project instructions to make the goal persist.

## Work toward completion

Choose the next unfinished criterion, do the authorized work, inspect the result, and adjust the approach. A failed check calls for diagnosis and another useful attempt. Finish independent work while waiting for missing information.

Preserve the goal when the user asks a status question or steers implementation. Incorporate corrections into the checkpoint. Pause or cancel immediately when requested. Do not start unrelated work, deploy, activate systems, spend money, or contact people merely because a goal is active; existing authorization still governs those actions.

Update progress after meaningful milestones. Do not stop at a plan, a partial implementation, or an offer to continue while an authorized next step remains. If attempts repeat the same failure without new evidence, change approach or identify what must change. Follow native blocking thresholds when present. Otherwise report a concrete blocker and the input needed to resume.

## Verify before completing

Check every acceptance criterion against current evidence. Run relevant checks and inspect their outputs. Distinguish passing checks from skipped or unavailable checks. A partial result or exhausted budget is not completion.

Mark a native goal complete only after every required criterion holds. Otherwise preserve the unfinished checkpoint and report the stopping reason. Finish with the result, verification evidence, and any remaining limitation. Report native budget usage when required by the host.

A skill supplies instructions, not a scheduler or Stop hook. Without native continuation support it cannot restart a stopped turn, survive a closed client automatically, or enforce exact token accounting. Explain that limitation when the requested workflow depends on it.

Example: `$goal All four NixOS configurations evaluate without changing flake.lock.` Evaluate each configuration, diagnose failures, and finish only when all four pass and the lockfile is unchanged.
