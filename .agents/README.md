# Shared skills

Home Manager links each directory under `skills/` into `~/.agents/skills` and
`~/.claude/skills`. Adding a skill here makes it available in this repository;
global links are updated by the next Home Manager activation.

## Vendored additions

| Source | Commit | Selection |
| --- | --- | --- |
| [t3dotgg/tstack](https://github.com/t3dotgg/tstack) | `7de017b3fc9d50c03cf3ecb98fb71e0ca65a78bd` | All nine skills |
| [mattpocock/skills](https://github.com/mattpocock/skills) | `5beb35b040e3de97e54fa9e386d7e42d15c295c2` | `grilling`, `wizard`, `research`, `prototype` |
| [backnotprop/pstack](https://github.com/backnotprop/pstack) | `f51fdeba3d803ef90e4eaa4a95ffb4e76008ab37` | All 58 top-level skills |

Each added skill includes its upstream MIT license. Pstack is installed from
the standalone mirror, which adapts Cursor's skills for Codex and other agents.
Cursor plugin registrations and the separate Benny automation pack are excluded.
The links in `poteto-help/SKILL.md` to repository-level documentation use pinned
GitHub URLs so they remain valid when Home Manager links individual directories.

Pstack supplies `teach` instead of Matt Pocock's version and replaces the previous
`unslop`. Prefer pstack for overlapping workflows as described in `../AGENTS.md`.
Older workflow skills remain available to satisfy references from other skills.

Use `/setup-pstack` to configure models when needed. Installing the skills does
not change model settings or start any workflow.
