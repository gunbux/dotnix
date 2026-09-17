---
name: use-trek
description: Use when the user mentions Trek, asks to use the Trek MCP server, or wants to read or change data in the Trek travel planning application.
---

# Use Trek

Use the available `mcp__trek__*` tools for Trek requests. Their current descriptions and input schemas are the source of truth. Do not maintain or infer a fixed feature catalog in this skill.

## Operating rules

- Select tools from those available in the current session. Check availability before relying on an optional add-on, and explain when Trek does not expose a needed operation.
- When a trip ID is absent, call `list_trips` and resolve the trip instead of guessing. Call `get_trip_summary` before planning or changing an existing trip.
- Read `get_display_settings` before presenting unit-sensitive distances, temperatures, times, or default currency values.
- For real-world places, follow the place-search and creation sequence in the current tool descriptions so Trek retains provider IDs and map metadata.
- Resolve Trek member IDs before operations involving payers, splits, travelers, participants, or assignees.
- Proceed with requested, unambiguous changes. Before each destructive operation, confirm the exact target. Warn that deleting a place also removes its day assignments.
- Use the latest successful tool result as state. Report completed changes, partial failures, and unavailable operations precisely.
