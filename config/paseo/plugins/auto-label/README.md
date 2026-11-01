# Auto label

A Paseo 0.10.3 plugin that gives every unlabelled sidebar workspace one workspace label, so
the sidebar can be grouped with **Display → Grouping → Labels**.

## Behavior

- When a thread in an unlabelled workspace starts or finishes a turn, the daemon classifies the
  workspace title, the first prompt of its oldest thread, and its directory with headless
  Claude Code (`claude -p`, Haiku by default). Tools, MCP servers, hooks, skills, and session
  history are disabled for that run, and it reuses your existing Claude login. No API key is
  stored.
- After the plugin starts, the first lifecycle event queues every unlabelled workspace.
- A workspace that already has any label is never touched, including one labelled by hand
  while classification runs. Change a wrong label from the sidebar.
- The classifier prefers existing workspace labels, keeping their casing and colour, plus the
  configured list. With **Allow new labels** on, it can create a new label with a stable
  colour. With it off, anything unmatched becomes `Misc`.
- Classifications run one at a time. A failure is logged and retried on the workspace's next turn.

Configure under **Settings → Plugins → Auto label**, or open **Auto label settings** from the
Command Center. **Label unlabelled workspaces** is available in both places.

## Install

`modules/home/paseo.nix` exposes the runtime source at
`~/.local/share/paseo/plugins/auto-label`. With plugins enabled on the daemon:

```sh
paseo plugin install "$HOME/.local/share/paseo/plugins/auto-label"
paseo plugin reload auto-label   # after source changes
paseo plugin logs auto-label
```

The daemon needs `claude` on its PATH (or `PASEO_AUTO_LABEL_CLAUDE` set to its executable).
The 0.10.3 plugin SDK and CLI cannot read or assign workspace labels, so the backend sends the
app's own label requests over an authenticated local connection. That requires a TCP daemon
listener and Node.js with built-in WebSocket support.

## Develop

```sh
npm ci --ignore-scripts
npm test
npm run typecheck
```
