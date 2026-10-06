# Cloud agents

A Paseo 0.10.3 plugin for driving Anthropic- and OpenAI-hosted coding agents from Paseo.

| Service | What you get | Backed by |
| --- | --- | --- |
| Claude Managed Agents | A **Claude (cloud)** provider: cloud sessions are ordinary Paseo threads with streaming replies, tool calls, approvals, interrupt, archive, and import of existing sessions | `api.anthropic.com/v1/{agents,environments,sessions}` (beta `managed-agents-2026-04-01`) |
| Codex Cloud | A control plane: list tasks, read diffs, apply a task to a local workspace, and submit new tasks | the `codex cloud` CLI |

Claude Code on the web and Remote Control sessions are not covered: neither has a public API.
Codex Cloud is a control plane rather than a chat because `codex cloud` has no follow-up
messages; each prompt is a new task.

## Use

**Chat with Claude in the cloud.** Create an agent in any workspace and choose the **Claude
(cloud)** provider. Its *model* picker lists your managed agents; its *mode* picker lists your
environments. The agent runs in Anthropic's sandbox, not in the workspace directory; the
workspace only groups the thread. Tools that your agent's permission policy marks `ask` show
up as normal Paseo approval prompts. Closing a thread detaches it. Archiving it archives the
cloud session. Sessions started elsewhere appear in the provider's import list.

**Control plane.** Open **Cloud agents** from the sidebar or Command Center.

- *Claude*: list sessions, with status, agent, model, and cost; interrupt running sessions; archive.
- *Codex Cloud*: pick a local workspace, submit a task (environment, branch, best-of-N
  attempts), browse recent tasks, view a diff per attempt, open the task in the browser, and
  apply it into the chosen workspace.

From any thread's composer, `/codex-cloud <task>` submits a task from that thread's workspace
to the default Codex environment and opens the control plane.

## Credentials

**Claude** needs an Anthropic API key on the daemon host. The plugin reads `ANTHROPIC_API_KEY`
from the daemon's environment, or else the file configured under **Settings → Plugins →
Cloud agents** (default `/run/secrets/anthropic_api_key`). Settings store only the path,
because they are readable by every connected client. The key never leaves the daemon.

To provide it through SOPS, add `anthropic_api_key` to `secrets/secrets.yaml`, then declare it
next to the other secrets in `modules/sops.nix`:

```nix
sops.secrets.anthropic_api_key = {
  path = "/run/secrets/anthropic_api_key";
  owner = "chun";
  mode = "0600";
};
```

Add the encrypted value before you declare the secret; sops-nix fails activation for a
missing key.

You also need at least one managed agent and environment in your Anthropic workspace. Set
defaults in settings so new threads can skip the pickers.

**Codex** uses the `codex` CLI's own ChatGPT login. Run `codex login` as the user who runs the
daemon. Set the binary path in settings if the daemon's `PATH` does not include `codex`.
Environments are created in the Codex web UI; settings take an environment id or label.

## Install

The Home Manager module `modules/home/paseo.nix` exposes the runtime source at
`~/.local/share/paseo/plugins/cloud-agents` on the desktop hosts. Enable plugins under
**Settings → Plugins** on the target daemon, then:

```sh
paseo plugin install "$HOME/.local/share/paseo/plugins/cloud-agents"
paseo plugin ls
```

After source changes or a new Home Manager generation:

```sh
paseo plugin reload cloud-agents
paseo plugin logs cloud-agents
```

## Layout

- `server/claude-api.ts`: Managed Agents HTTP client, key resolution, and SSE parser.
- `server/translate.ts`: maps Managed Agents events to Paseo timeline, turn, permission, and usage events.
- `server/provider.ts`: the provider connection. It follows each session's event stream and
  backfills from the event list after every reconnect, deduplicating by event id, so a dropped
  stream loses nothing. On reopen it replays history, resumes a running turn, and re-raises
  unanswered approvals.
- `server/codex.ts`: `codex cloud` wrapper. It only parses `list --json`; `exec` prints the task URL.
- `shared/`: RPC contracts and settings. `client/`: React Native screens.

## Develop and verify

```sh
npm ci --ignore-scripts
npm test            # unit tests plus a provider round trip against a fake API
npm run typecheck
```

`tests/daemon.integration.ts` runs the whole plugin inside a real daemon against a fake
Managed Agents API and a fake `codex`. It covers settings, every RPC, and a cloud chat with
an approval. It rewrites this plugin's settings, so only run it against a disposable daemon
listening on `127.0.0.1:16877` with the plugin installed:

```sh
node tests/daemon.integration.ts ws://127.0.0.1:16877/ws
```

SDK reference: https://paseo.sh/docs/plugins/reference.md and
https://paseo.sh/docs/plugins/providers.md.
