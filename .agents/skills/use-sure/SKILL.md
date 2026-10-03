---
name: use-sure
description: Use when the user mentions Sure, asks to use the Sure MCP server, or wants to read or change data in the Sure personal finance application, such as accounts, balances, transactions, budgets, or net worth.
---

# Use Sure

Use the available `mcp__sure__*` tools for Sure requests. Their current descriptions and input schemas are the source of truth. Do not maintain or infer a fixed feature catalog in this skill.

## Operating rules

- Select tools from those available in the current session, and explain when Sure does not expose a needed operation.
- Resolve accounts, categories, merchants, and other records through list or search tools instead of guessing IDs or names.
- State the date range, accounts, and currency behind any totals, balances, or trends you report. Do not convert currencies or fill gaps unless the data or the user specifies how.
- Treat financial data as sensitive. Fetch only what the request needs and avoid repeating account numbers or other identifiers unnecessarily.
- Proceed with requested, unambiguous changes. Before each destructive or bulk operation, confirm the exact targets.
- Use the latest successful tool result as state. Report completed changes, partial failures, and unavailable operations precisely.
