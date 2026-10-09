# Auto archive

A Paseo 0.10.3 plugin that archives workspaces with no activity for a configurable number of
days (4 by default).

## Behavior

- The daemon side sweeps hourly, when its settings change, and as soon as it gets a daemon
  session (an app connecting, a workspace being created, or a turn starting or ending).
- Idle time is measured from the workspace's `activityAt`, falling back to when its status
  last changed. A workspace with neither is never archived.
- Running workspaces are never archived. Pinned workspaces are kept unless **Pinned workspaces**
  is switched off.
- Archiving the last workspace on a managed worktree removes the worktree. With **Worktrees with
  uncommitted changes** on (the default), a worktree workspace is only archived when Paseo
  reports it clean. Local workspaces are archived regardless of git state; their directory stays.
- Workspaces carrying any of the comma-separated **Quick chat labels** (`Quick chat, Glance` by
  default) are archived after **Quick chat hours** (12 by default) instead. The Vicinae Paseo
  extension (`config/vicinae/paseo`) labels its quick chats `Quick chat`, and glance's Paseo
  backend labels its ask-about-screen chats `Glance`; pin one to keep it. Set the hours to 0 or
  clear the labels to treat them like any other workspace.
- Failures are logged and retried on the next sweep.

Configure under **Settings → Plugins → Auto archive**, or open **Auto archive settings** from the
Command Center. The settings screen previews which workspaces are idle now. **Archive now** and
the **Archive idle workspaces now** command run a sweep even while automatic archiving is off.

## Install

`modules/home/paseo.nix` exposes the runtime source at
`~/.local/share/paseo/plugins/auto-archive`. With plugins enabled on the daemon:

```sh
paseo plugin install "$HOME/.local/share/paseo/plugins/auto-archive"
paseo plugin reload auto-archive   # after source changes
paseo plugin logs auto-archive
```

## Develop

```sh
npm ci --ignore-scripts
npm test
npm run typecheck
```
