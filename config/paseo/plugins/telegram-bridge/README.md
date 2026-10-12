# Paseo Telegram bridge

See [OVERVIEW.md](OVERVIEW.md) for behavior and limits.

## Setup

The Home Manager module links this source to `~/.local/share/paseo/plugins/telegram-bridge`. After your next Home Manager activation, register it once:

```sh
paseo plugin install ~/.local/share/paseo/plugins/telegram-bridge
```

For development, install this source directory directly. Keep the default installation ID `telegram-bridge`; startup and persistent data use that ID. The daemon's global plugin switch must be enabled.

Create a dedicated bot using Telegram's @BotFather. Add its token to your SOPS-encrypted secrets and expose it as an owner-readable secret on the daemon host. For example, a NixOS declaration after adding the encrypted key:

```nix
sops.secrets.paseo_telegram_bot_token = {
  owner = "chun";
  mode = "0400";
};
```

Use the resulting `/run/secrets/paseo_telegram_bot_token` path in the plugin settings. Do not put the token itself in Nix, plugin settings, source files, or chat. Existing secret files with mode 0600 or 0400 also work. Rotate a token by updating its secret file and reloading the plugin.

Open **Settings → Plugins → Telegram bridge**, enter your numeric Telegram user ID and token file path, enable, and save. Enter a supported `provider/model` if you want to create new agents. The status panel reports connection state. Start a private conversation with the bot by sending `/start`.

## Commands

| Command | Action |
| --- | --- |
| `/agents` | List unarchived agents in this chat’s workspace. |
| `/use <id>` | Select an agent and watch its replies and approvals. Unique ID prefixes work. |
| `/workspace` | Show this chat’s workspace. |
| `/new <prompt>` | Create and select an agent using the configured provider/model. |
| Plain text | Send a prompt to the selected agent. Sending during a turn follows Paseo's default interruption behavior. |
| `/send <text>` | Send text beginning with a slash to the agent. |
| `/status` | Show selection and watched agents; issue fresh buttons for pending approvals. |
| `/stop` | Interrupt the selected agent. |
| `/unwatch [id]` | Stop notifications for an agent; defaults to the selected agent. |
| `/help` | Show command help. |

Selecting another agent keeps the previous one watched. Approval buttons always target the agent and request shown on the message, independently of selection. Resolved or expired requests cannot be answered with old buttons. Provider-supplied actions retain their labels and scope; a button can therefore grant more than one use if its label says so.

## Operations

```sh
npm ci --ignore-scripts
npm test
npm run typecheck
paseo plugin reload telegram-bridge
paseo plugin logs telegram-bridge
```

No runtime npm dependencies are needed. Paseo provides the plugin SDK and Zod. Server modules use Node built-ins. Development dependencies pin the matching Paseo types.

The daemon must publish a TCP listener in its `paseo.pid`. Startup makes one authenticated loopback call to its own RPC to obtain the daemon-owned SDK session. Cancellation uses the same session protocol because Paseo 0.11.2 does not expose it in `PaseoApi`. Other agent operations use the SDK. Local authentication uses the daemon's existing `local-credential` file.

State is stored at `$PASEO_HOME/plugin-data/telegram-bridge/state.json` with mode 0600. Changing the owner ID or bot identity clears the old selection, approval references, and delivery queue. Corrupt state stops startup rather than resetting the Telegram offset. Disable the bridge before repairing state.

Telegram 409 means another poller is using the bot. A webhook also prevents polling; the bridge never deletes another integration's webhook. A rejected token or permanent delivery error stops the bridge. A blocked or removed bot revokes only that chat. Correct the cause and reload. Transient network errors and rate limits retry automatically.

The bridge does not replay missed completion events after downtime. Incoming messages older than five minutes are skipped. The durable offset is advanced before executing a command to avoid repeating side effects after a crash; check Paseo before resending an interrupted command. Telegram message delivery is at least once, so a lost acknowledgement can result in duplicate outgoing messages.

## Per-chat workspaces and TREK

Your private chat gets a workspace automatically on its first message. Register each group by sending `/start@clam_maid_bot` yourself. All members of a registered group may then prompt agents and answer approval buttons. A first prompt creates an agent; `/new <prompt>` starts another in the same workspace. `/agents`, `/use`, replies, and approvals are scoped to that workspace. `/workspace` shows the mapping.

The directory `$PASEO_HOME/telegram-workspaces/<bot-id>/<chat-id>` gives each chat a stable identity independent of its title. Missing workspaces are reopened or created. Group-to-supergroup upgrades retain the original directory. Removing or blocking the bot clears chat registration and queued deliveries, leaving Paseo workspaces and agents intact. Only the owner can register the group again.

New agents get `trek` as an HTTP MCP server at `https://trek.chunyu.sh/mcp`. Authentication comes from the selected provider on the daemon. With the live Codex setup, the default is `codex/gpt-6.1-sol`. No TREK token is stored in plugin settings.

For groups with Telegram privacy mode enabled, use `/send@clam_maid_bot <prompt>`, `/new@clam_maid_bot <prompt>`, or reply to the bot. To receive ordinary text, disable privacy mode through @BotFather and re-add the bot. Forum topics share the group's workspace. Anonymous administrator messages and channels are ignored.

State version 2 preserves the old update offset and queued private replies. It resets old global selections and approval buttons so unrelated agents cannot become visible in groups. Workspaces isolate routing, not filesystem permissions; agents still run under the daemon's normal security policy.
