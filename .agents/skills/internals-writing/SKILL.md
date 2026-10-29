---
name: internals-writing
description: "Write and refine system-internals study notes in the user's preferred style: visual explanations grounded in code, clear execution boundaries, and Simplified Technical English. Use for codebase walkthroughs, backend comparisons, and section-by-section architecture documentation."
---

# Internals writing

Help the reader build a mental model they can question and verify against the code.
Apply [technical-writing](../technical-writing/SKILL.md) and [unslop](../unslop/SKILL.md). These instructions add the user's preferences for explanations of internals.

## Work with the reader's draft

- Read the current notes before each edit. The reader can change them between turns.
- Establish a rough outline before expanding the document. When the reader is vetting sections, develop the requested section and leave later sections as outlines.
- Update the actual notes when asked. Preserve vetted content, handwritten observations, and unrelated edits. Do not replace the whole document to improve one section.
- Integrate useful follow-up explanations into the relevant section when requested. Consolidate repetition instead of appending the conversation verbatim.
- Keep the final chat reply short. Link the edited section and identify material limitations.

## Organize around understanding

Start with shared concepts and interfaces, then explain the implementation. Use `Context:` and `Infrastructure:` heading prefixes when that distinction fits the document.

For a comparison, normally explain one system completely before the other. Use the same topic order in both chapters. Do not force a comparison into every subsection.

Explain these relationships before relying on their names:

- What each object represents and what it owns.
- Which objects share a remote resource and which allocate separate resources.
- When allocation occurs, which operations reuse state, and what cleanup destroys.

Do not imply one request, review, session, workspace, or lease always equals one VM. Check the code, including replacement after failure.

Keep routine command execution, file transfer, and cleanup brief unless their mechanics are the topic. Use an aside for secondary details.
Explain an optimization's benefit and trade-off beside that mechanism, not in a detached reasons section.

After the foundations, connect the mechanisms with an end-to-end example. State its scope, show the common path, and distinguish optional branches.

## Draw the relationships that prose makes hard to follow

Use diagrams to replace dense explanations, not to repeat them. Prefer a few focused views over one crowded diagram.
Use the repository's architecture-diagram skill when available.

- Put code inside the machine or process where it executes. Distinguish worker-local calls, HTTP clients, remote services, guest processes, and external providers.
- Show ownership with containment. Use labeled arrows for calls, transferred data, and lifecycle transitions. State whether arrows show requests or returned data.
- Show the cache-hit and cache-miss paths when they change the work. Mark snapshot capture, publication, restore, and disposal at their actual points in the lifecycle.
- Distinguish saved artifacts from live resources, and logical state from its physical representation. A full-state snapshot need not be a full-size copy.
- Do not confuse different kinds of lazy access, such as fetching Git objects and reading VM snapshot blocks.

For Markdown notes, embed SVGs with relative asset paths. Do not make the reader open an HTML link to see the explanation.
An interactive HTML companion can help in chat. Use the host's preview and publication tools when available.
Keep diagrams self-contained, provide text alternatives, and render them at the intended reading width. Check arrows, boundaries, labels, and clipping.

## Use code as evidence

Trace the caller, implementation, and configuration before explaining a path. Separate an interface's purpose from its transport mechanism.
When the reader asks which reviews or workflows use a feature, answer in those terms. A function-selection rule alone is insufficient.
Distinguish code defaults from configured workflows and live routing. If live state cannot be checked, say what remains unknown.

Use code links at important entry points and surprising behavior. Avoid linking every bullet or repeating the same source.
Prefer the repository's moving main or default branch over commit permalinks unless a historical claim needs a fixed revision.

Use short, clean fenced code blocks when a signature or call clarifies the explanation. Put the repository-relative path immediately above the block.
Explain the operations a complex type exposes. Do not assume the type signature itself teaches the contract.

Label design rationale as documented or inferred. Distinguish implemented behavior, committed deployment configuration, verified live state, and proposals.
Keep security claims precise: hiding a credential does not necessarily restrict the operations available through it. Explain both the protection and the remaining capability.
Do not modify code or unrelated source documents merely because the writing task reveals a discrepancy.

## Keep the explanation concise and STE-style

Use short, active sentences and stable technical terms. Keep the real code names. Define unfamiliar terms before using them to explain another term.
Apply Simplified Technical English principles without claiming certified ASD-STE100 compliance unless that compliance has been verified.

When a section grows wordy, retain the essential sequence, move relationships into visuals, and remove repeated narration.
Keep qualifications that change the meaning, including authentication variants, fallback behavior, and what is excluded from a measurement.

## Explain timings without inventing a timeline

Use the reader's benchmark reports when available. Identify the repository, date, backend, cache state, run count, and measurement boundary.
Use one recorded run for an example that needs additive stage timings. Do not assemble a fictional run from unrelated medians.

- Separate acquisition, repository preparation, agent execution, and total wall time.
- Check whether an outer duration already includes an inner stage before adding them.
- Label an arithmetic remainder as unsegmented time. Do not assign it to queueing, publication, or cleanup without evidence.
- Do not draw unsegmented intervals as a known chronological sequence.
- Distinguish setup-only benchmarks from complete reviews, and measured values from estimates.

Connect each measured cost to the work it includes. Explain which cache or optimization avoids that work on the next run.
Treat historical measurements as examples with conditions, not fixed budgets or proof of current deployment behavior.
