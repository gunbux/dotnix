# Telegram bridge

Give each Telegram chat its own Paseo workspace. The bridge creates the workspace on first use and reuses it after restarts. Send a prompt to start an agent, use `/new <prompt>` for a new thread, or select an existing agent in that chat with `/agents` and `/use`. Replies and permission prompts return to the same chat.

Private access is limited to the configured owner. To connect a group, the owner sends `/start@your_bot` there. After registration, every group member can send prompts and approve actions. Group replies, permission details, and TREK results are visible to the group. Channels and messages sent as anonymous administrators are ignored. Removing the bot revokes registration; adding it again requires the owner's `/start`.

New agents receive the TREK MCP server at `https://trek.chunyu.sh/mcp` and use the configured provider/model. TREK uses that provider's existing authentication on the daemon. Credentials are not copied into the plugin.

Create a dedicated bot with @BotFather and store its token in a daemon-readable secret file with mode 0600 or 0400. In Telegram bridge settings, enter its absolute path and your numeric Telegram user ID, choose a provider/model, enable the bridge, and save. Send `/start` privately or `/start@your_bot` in a group. With Telegram privacy mode enabled, use `/send@your_bot <prompt>` or reply to a bot message. To receive ordinary group text, disable privacy mode in @BotFather and re-add the bot.

Requires Paseo 0.11.2 with a local TCP listener and the installation ID `telegram-bridge`. Long polling needs outbound HTTPS to Telegram; no public listener is required. Only one daemon may use a bot token, and the bot must not have a webhook.

The plugin reads the bot token on the daemon and sends watched agent replies and permission details through Telegram. It stores chat-to-workspace mappings, selections, update offsets, approval references, and undelivered messages in a private file under the daemon's plugin data directory. It does not copy the token into its settings or state.

The bridge handles text only. Messages older than five minutes are ignored. Commands are checkpointed before execution to prevent replay after a crash; an interrupted command may need to be sent again. Outgoing messages retry after transient failures and can be duplicated if Telegram accepted a message but its acknowledgement was lost. Completion events while the plugin is stopped are not replayed; pending approvals are recovered when it starts.

Workspace directories live under `$PASEO_HOME/telegram-workspaces/<bot-id>/<chat-id>`. A group upgrade preserves its workspace. Upgrading from the private-only bridge keeps the Telegram offset and queued private replies, but clears global agent selections and old approval buttons. Existing Paseo agents are retained; new selections are limited to each chat's workspace.

Chat routing is isolated, but agents run on the same daemon with its normal permissions. These workspaces are not a security sandbox between group members.
