# Telegram bridge

Control Paseo agents from a private Telegram bot chat. List and select agents, send prompts, create agents in existing workspaces, and stop running turns. Watched agents send their completed text replies and permission prompts back to your chat, even after you select another agent.

The bridge accepts commands only from the configured numeric Telegram user ID in that user's private chat. Tool, plan, and mode approvals use buttons tied to a specific pending request. Buttons expire after 15 minutes. Structured questions must be answered in Paseo.

Create a dedicated bot with @BotFather and store its token in a daemon-readable secret file with mode 0600 or 0400. In Telegram bridge settings, enter the file's absolute path and your Telegram user ID, enable the bridge, and save. Open a private chat with the bot and send `/start`. Configure a default `provider/model` to use `/new`.

Requires Paseo 0.11.2 with a local TCP listener and the installation ID `telegram-bridge`. Long polling needs outbound HTTPS to Telegram; no public listener is required. Only one daemon may use a bot token, and the bot must not have a webhook.

The plugin reads the bot token on the daemon and sends watched agent replies and permission details through Telegram. It stores selections, update offsets, approval references, and undelivered messages in a private file under the daemon's plugin data directory. It does not copy the token into its settings or state.

The bridge handles text only. Messages older than five minutes are ignored. Commands are checkpointed before execution to prevent replay after a crash; an interrupted command may need to be sent again. Outgoing messages retry after transient failures and can be duplicated if Telegram accepted a message but its acknowledgement was lost. Completion events while the plugin is stopped are not replayed; pending approvals are recovered when it starts.
