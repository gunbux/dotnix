# Paseo for Vicinae

Two commands for the local Paseo daemon:

- **Paseo Workspaces**: search workspaces grouped by project (agent titles are searchable
  too). Enter opens the workspace's most recent agent in Paseo Desktop. Other actions show
  each agent, pin or unpin (auto-archive skips pinned workspaces), archive, and copy the path.
- **Ask Paseo**: type a question and press Enter, or pass it as the command argument. Each
  chat gets its own workspace in the chat directory, labelled `Quick chat`, and its answer
  streams into Vicinae. Follow up, copy the answer, open the chat in Paseo, or pin it.
  Earlier quick chats are listed below the prompt.

Settings are under the extension's preferences in Vicinae: default model (Claude, the
OpenRouter auto or free router through OpenCode, Codex, or any `provider/model`), thinking
effort, plan mode, chat directory, and chat label. The search bar dropdown changes the model
for one chat.

The auto-archive plugin (`config/paseo/plugins/auto-archive`) archives `Quick chat`
workspaces after 12 idle hours by default. Keep its **Quick chat label** in sync with the
**Chat Workspace Label** preference here.

## How it talks to Paseo

The public CLI's JSON output leaves out each agent's workspace id and the reply text, so
`bridge/paseo-bridge.mjs` runs on Paseo Desktop's bundled runtime and uses the installed
CLI's daemon client (`@getpaseo/cli/dist/utils/client.js`). `modules/home/vicinae.nix`
wraps it as `paseo-vicinae-bridge` and replaces `@paseoBridge@` and `@paseo@` in
`src/lib/paseo.ts` with store paths. Paseo updates can move those internal modules, so
check the bridge after bumping `pkgs/paseo-desktop`.

## Develop

```sh
npm ci
npm run typecheck
```

`npm run build` installs into `~/.local/share/vicinae/extensions/paseo`, where Home Manager
puts its symlink. Delete that directory before switching.
