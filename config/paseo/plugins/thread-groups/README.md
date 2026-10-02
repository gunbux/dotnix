# Thread groups

A Paseo 0.10.3 plugin for organizing agent threads by feature across workspaces.

## Use

Open **Thread groups** in the sidebar, create a named group, then select **Add or remove
threads**. Choose threads from any workspace on that host and save. Search matches thread
titles and workspace names; workspace buttons narrow the list. **Ungrouped** shows threads
that have no group membership.

From a thread, open Command Center and select **Assign thread to groups**, or submit
`/thread-groups`. Choose one or more groups or create a new one in the assignment panel.
Select **Open thread** from a group to return to the original chat.

Groups are flat, and a thread can belong to several. Deleting a group only deletes the
group, never a thread. Missing thread references stay saved. Groups span workspaces on
one daemon; separate daemons do not synchronize group data.

## Install on another machine

The Home Manager module `modules/home/paseo.nix` is imported by `applications.nix`. It exposes
the runtime source at `~/.local/share/paseo/plugins/thread-groups` on the desktop hosts.
Apply your Home Manager configuration through your usual system activation when ready.
Enable plugins under **Settings → Plugins** on the target daemon, then run on that machine:

```sh
paseo plugin install "$HOME/.local/share/paseo/plugins/thread-groups"
paseo plugin ls
```

Alternatively, install directly from a checkout:

```sh
paseo plugin install /absolute/path/to/dotnix/config/paseo/plugins/thread-groups
```

The path must exist on the daemon machine. Installation is explicit; Home Manager does not
start the daemon, modify its config, or register plugins during activation. The plugin is
restricted to Paseo 0.10.x until newer SDKs are verified. Both daemon and client must satisfy
the manifest's version requirement.

Paseo provides the runtime libraries. There is no npm install or build step on deployment.
After source changes or a new Home Manager source generation, run:

```sh
paseo plugin reload thread-groups
paseo plugin logs thread-groups
```

## Data and recovery

Paseo stores the versioned group document at
`<PASEO_HOME>/plugin-settings/thread-groups/groups.json`, outside the source tree and Nix
store. Back up that file with the daemon's state. Copying plugin source does not copy groups
or threads to another daemon.

Saves include the revision displayed when editing began. A conflicting save reports an error
instead of overwriting another client's changes. Cancel the edit, reload, and retry. Invalid
saved data is reported without silently resetting it. Group names are trimmed, limited to
80 characters, and unique without regard to case.

## Develop and verify

Use Node.js 24 or newer for the tests:

```sh
npm ci --ignore-scripts
npm test
npm run typecheck
```

The lockfile pins development dependencies and the official 0.10.3 SDK. Client code uses React
Native primitives and host theme colors, and has no DOM dependency. Shared modules contain
validation and grouping logic; the server entry only registers native persistent settings.

`tests/settings.integration.ts` verifies concurrent revision conflicts, rejected invalid
writes, plugin reload persistence, and client bundle compilation. It only accepts
`ws://127.0.0.1:16877/ws` and writes fake data; run it against a disposable daemon home with
the plugin installed, never against your normal daemon:

```sh
node tests/settings.integration.ts ws://127.0.0.1:16877/ws
```

SDK reference: https://paseo.sh/docs/plugins/reference.md.
