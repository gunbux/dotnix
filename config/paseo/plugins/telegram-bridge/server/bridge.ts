import { randomBytes } from 'node:crypto';
import type { AgentPermissionRequest, AgentPermissionResponse, AgentTimelineItem } from '@getpaseo/protocol/agent-types';
import type { PluginTurnOutcome } from '@getpaseo/plugin/server';
import { migrateChat, revokeChat, emptyChat, type Chat, type State } from './state.ts';
import { splitText, type Update, type Button } from './telegram.ts';

export interface AgentPort {
  agents(workspace: string): Promise<{ id: string; title: string; status: string }[]>;
  ensureWorkspace(key: string, title: string, existing: string | null): Promise<string>;
  create(workspace: string, provider: string): Promise<string>;
  send(agent: string, text: string, key: string): Promise<void>;
  stop(agent: string): Promise<void>;
  permissions(agent: string): Promise<AgentPermissionRequest[]>;
  respond(agent: string, request: string, response: AgentPermissionResponse): Promise<void>;
}
type Options = { state: State; port: AgentPort; save(): Promise<void>; now(): number; defaultProvider: string; botUsername: string };
const help = '/agents — list agents\n/use <id> — select and watch an agent\n/workspace — show this chat’s workspace\n/new <prompt> — create and select an agent\n/status — show selection and pending approvals\n/stop — interrupt the selected agent\n/unwatch <id> — stop its notifications\n/help — show commands\n\nSend ordinary text to your selected agent, or start a new agent with your first message. Use /send <text> for a prompt beginning with a slash.';

function resolveId<T extends { id: string }>(items: T[], input: string): T {
  if (!input) throw new Error('Provide an ID from the list.');
  const exact = items.find(x => x.id === input);
  if (exact) return exact;
  const matches = items.filter(x => x.id.startsWith(input));
  if (matches.length !== 1) throw new Error(matches.length ? 'That ID is ambiguous. Use a longer ID.' : 'That ID was not found.');
  return matches[0];
}

export class Bridge {
  private options: Options;
  constructor(options: Options) { this.options = options; }
  private get state() { return this.options.state; }
  private async say(chatId: string, text: string, buttons?: Button[][]) {
    const chunks = splitText(text);
    chunks.forEach((text, i) => this.state.outbox.push({ chatId, text, ...(i === chunks.length - 1 && buttons ? { buttons } : {}) }));
    await this.options.save();
  }
  async update(update: Update): Promise<{ callbackId: string; text: string } | undefined> {
    if (!Number.isSafeInteger(update.update_id) || update.update_id < this.state.offset) return;
    // Checkpoint BEFORE effects. An interrupted command is never replayed after a restart.
    this.state.offset = update.update_id + 1;
    await this.options.save();
    const membership = update.my_chat_member;
    if (membership && ['left', 'kicked'].includes(membership.new_chat_member.status)) {
      revokeChat(this.state, String(membership.chat.id));
      await this.options.save();
      return;
    }
    const migration = update.message;
    if (migration && ['group', 'supergroup'].includes(migration.chat.type)) {
      const oldId = migration.migrate_from_chat_id ?? (migration.migrate_to_chat_id ? migration.chat.id : undefined);
      const newId = migration.migrate_to_chat_id ?? (migration.migrate_from_chat_id ? migration.chat.id : undefined);
      if (oldId && newId && Number.isSafeInteger(oldId) && Number.isSafeInteger(newId) && oldId < 0 && newId < 0) {
        if (migrateChat(this.state, String(oldId), String(newId))) await this.options.save();
        return;
      }
    }
    const callback = update.callback_query;
    const message = callback?.message ?? update.message;
    const from = callback?.from ?? update.message?.from;
    if (!from || from.is_bot || !message || message.sender_chat) return;
    const chatId = String(message.chat.id);
    const privateChat = message.chat.type === 'private' && chatId === this.state.owner && String(from.id) === this.state.owner;
    const group = Number.isSafeInteger(message.chat.id) && message.chat.id < 0 && ['group', 'supergroup'].includes(message.chat.type);
    if (!privateChat && !group) return;
    if (callback) {
      if (!this.state.chats[chatId]) return;
      try { return { callbackId: callback.id, text: await this.answer(chatId, callback.data ?? '') }; }
      catch { await this.say(chatId, 'Could not answer this request. Check /status or answer it in Paseo.'); return { callbackId: callback.id, text: 'Request was not confirmed.' }; }
    }
    if (!update.message || this.options.now() - update.message.date * 1000 > 300000) return;
    let text = update.message.text?.trim();
    if (!text) return;
    const addressed = /^([^\s@]+)@([^\s]+)([\s\S]*)$/.exec(text);
    if (addressed && text.startsWith('/')) {
      if (addressed[2].toLowerCase() !== this.options.botUsername.toLowerCase()) return;
      text = addressed[1] + addressed[3];
    }
    if (!this.state.chats[chatId]) {
      if (!privateChat && !(String(from.id) === this.state.owner && text.split(/\s/, 1)[0].toLowerCase() === '/start')) return;
      this.state.chats[chatId] = emptyChat(message.chat.title || message.chat.first_name || `Telegram ${chatId}`);
      await this.options.save();
    }
    const chat = this.state.chats[chatId];
    try {
      const workspace = await this.options.port.ensureWorkspace(chat.workspaceKey ?? `${this.state.botId}/${chatId}`, chat.title, chat.workspaceId);
      if (workspace !== chat.workspaceId) {
        chat.workspaceId = workspace;
        chat.selectedAgent = null;
        chat.watchedAgents = [];
        for (const [key, value] of Object.entries(this.state.approvals)) if (value.chatId === chatId) delete this.state.approvals[key];
        await this.options.save();
      }
      await this.command(chatId, chat, text, update.update_id);
    } catch (error) {
      await this.say(chatId, error instanceof InputError ? error.message : 'The command could not be completed. Check the agent in Paseo before retrying.');
    }
  }
  private async command(chatId: string, chat: Chat, text: string, updateId: number): Promise<void> {
    const [word] = text.split(/\s/, 1);
    const command = word.toLowerCase();
    const args = text.slice(word.length).trim();
    const { port } = this.options;
    const select = () => {
      if (!chat.selectedAgent) throw new InputError('Select an agent first with /use <id>.');
      return chat.selectedAgent;
    };
    if (command === '/start' || command === '/help') return this.say(chatId, help);
    if (command === '/agents') {
      const agents = await port.agents(chat.workspaceId!);
      return this.say(chatId, agents.map(a => `${a.title} [${a.status}]\n/use ${a.id}`).join('\n\n') || 'No agents found.');
    }
    if (command === '/workspace' || command === '/workspaces') return this.say(chatId, `${chat.title}\n${chat.workspaceId}`);
    if (command === '/use') {
      const agents = await port.agents(chat.workspaceId!);
      let agent;
      try { agent = resolveId(agents, args); } catch (e) { throw new InputError((e as Error).message); }
      chat.selectedAgent = agent.id;
      if (!chat.watchedAgents.includes(agent.id)) chat.watchedAgents.push(agent.id);
      await this.say(chatId, `Selected ${agent.title} (${agent.id}).`);
      return this.pending(agent.id);
    }
    if (command === '/new') {
      if (!this.options.defaultProvider.includes('/')) throw new InputError('Set the default provider/model in the Telegram bridge settings in Paseo first.');
      if (!args) throw new InputError('Use /new <prompt>.');
      const id = await port.create(chat.workspaceId!, this.options.defaultProvider);
      chat.selectedAgent = id;
      chat.watchedAgents.push(id);
      await this.say(chatId, `Created and selected ${id} in ${chat.title}.`);
      await port.send(id, args, `telegram:${this.state.botId}:${updateId}`);
      return;
    }
    if (command === '/status') {
      await this.say(chatId, `Selected: ${chat.selectedAgent ?? 'none'}\nWatching: ${chat.watchedAgents.join(', ') || 'none'}`);
      if (chat.selectedAgent) await this.pending(chat.selectedAgent, true);
      return;
    }
    if (command === '/stop') { const id = select();
      if (!(await port.agents(chat.workspaceId!)).some(a => a.id === id)) throw new InputError('Agent is no longer in this workspace.');
      await port.stop(id); return this.say(chatId, `Stop requested for ${id}.`); }
    if (command === '/unwatch') {
      let id;
      try { id = resolveId(chat.watchedAgents.map(id => ({ id })), args || select()).id; } catch (e) { throw new InputError((e as Error).message); }
      chat.watchedAgents = chat.watchedAgents.filter(a => a !== id);
      if (chat.selectedAgent === id) chat.selectedAgent = null;
      for (const [key, value] of Object.entries(this.state.approvals)) if (value.chatId === chatId && value.agentId === id) delete this.state.approvals[key];
      return this.say(chatId, `Stopped watching ${id}.`);
    }
    if (text.startsWith('/') && command !== '/send') throw new InputError('Unknown command. Use /help, or /send <text> to send a slash command to the agent.');
    const prompt = command === '/send' ? args : text;
    if (!prompt) throw new InputError('Provide a message after /send.');
    if (!chat.selectedAgent) return this.command(chatId, chat, `/new ${prompt}`, updateId);
    if (!(await port.agents(chat.workspaceId!)).some(a => a.id === chat.selectedAgent)) throw new InputError('Selected agent is no longer in this workspace. Use /new <prompt>.');
    await port.send(select(), prompt, `telegram:${this.state.botId}:${updateId}`);
    await this.say(chatId, `Sent to ${select()}.`);
  }
  async pending(agentId: string, repeat = false) {
    for (const request of await this.options.port.permissions(agentId)) await this.permission(agentId, request, repeat);
  }
  async permission(agentId: string, request: AgentPermissionRequest, repeat = false) {
    const entry = Object.entries(this.state.chats).find(([, chat]) => chat.watchedAgents.includes(agentId));
    if (!entry) return;
    const [chatId, chat] = entry;
    if (!chat.workspaceId || !(await this.options.port.agents(chat.workspaceId)).some(a => a.id === agentId)) return;
    for (const [key, old] of Object.entries(this.state.approvals)) {
      if (old.expires <= this.options.now()) delete this.state.approvals[key];
      else if (old.agentId === agentId && old.requestId === request.id) {
        if (!repeat) return;
        delete this.state.approvals[key];
      }
    }
    const description = [request.description, request.input ? JSON.stringify(request.input, null, 2) : '', request.detail ? JSON.stringify(request.detail, null, 2) : ''].filter(Boolean).join('\n');
    const title = `${request.title ?? request.name}\nAgent: ${agentId}\nRequest: ${request.id}`;
    if (request.kind === 'question' || request.kind === 'other') {
      await this.say(chatId, `${title}\n${description}\nAnswer this request in Paseo. It requires structured input.`);
      return;
    }
    const actions = request.actions?.length
      ? request.actions.map(a => ({ label: a.label, behavior: a.behavior, selectedActionId: a.id }))
      : [{ label: 'Allow once', behavior: 'allow' as const }, { label: 'Deny', behavior: 'deny' as const }];
    const key = randomBytes(12).toString('hex');
    this.state.approvals[key] = { chatId, agentId, requestId: request.id, expires: this.options.now() + 15 * 60000, actions };
    // Always put the complete request before its buttons, even when it spans messages.
    if (description) await this.say(chatId, `${title}\n\n${description}`);
    await this.say(chatId, `${title}\nChoose a response. Buttons expire after 15 minutes.`, actions.map((action, index) => [{ text: action.label.slice(0, 60), callback_data: `p:${key}:${index}` }]));
  }
  private async answer(chatId: string, data: string): Promise<string> {
    const match = /^p:([a-f0-9]{24}):(\d+)$/.exec(data);
    const approval = match && this.state.approvals[match[1]];
    if (!match || !approval || approval.chatId !== chatId || approval.expires <= this.options.now()) {
      await this.say(chatId, 'This approval expired. Use /status for current requests.');
      return 'Expired request.';
    }
    const chat = this.state.chats[chatId];
    if (!chat?.workspaceId || !chat.watchedAgents.includes(approval.agentId) || !(await this.options.port.agents(chat.workspaceId)).some(a => a.id === approval.agentId)) return 'Agent is no longer in this workspace.';
    const action = approval.actions[Number(match[2])];
    if (!action) return 'Invalid response.';
    const pending = await this.options.port.permissions(approval.agentId);
    if (!pending.some(p => p.id === approval.requestId)) {
      delete this.state.approvals[match[1]];
      await this.say(chatId, 'This request is no longer pending.');
      return 'Already resolved.';
    }
    // Consume before the RPC so a lost response cannot trigger a second approval.
    delete this.state.approvals[match[1]];
    await this.options.save();
    const response: AgentPermissionResponse = { behavior: action.behavior, ...(action.selectedActionId ? { selectedActionId: action.selectedActionId } : {}) };
    await this.options.port.respond(approval.agentId, approval.requestId, response);
    await this.say(chatId, `${action.label}: ${approval.requestId} (${approval.agentId}).`);
    return 'Response sent.';
  }
  async resolved(agentId: string, requestId: string) {
    for (const [key, value] of Object.entries(this.state.approvals)) if (value.agentId === agentId && value.requestId === requestId) delete this.state.approvals[key];
    await this.options.save();
  }
  async finished(agentId: string, title: string, timeline: readonly AgentTimelineItem[], outcome: PluginTurnOutcome) {
    const entry = Object.entries(this.state.chats).find(([, chat]) => chat.watchedAgents.includes(agentId));
    if (!entry) return;
    const [chatId, chat] = entry;
    if (!chat.workspaceId || !(await this.options.port.agents(chat.workspaceId)).some(a => a.id === agentId)) return;
    const start = timeline.findLastIndex(item => item.type === 'user_message');
    const text = timeline.slice(start + 1).filter(item => item.type === 'assistant_message').map(item => item.text).join('\n\n');
    const status = outcome.kind === 'completed' ? '' : `\nTurn ${outcome.kind}.`;
    await this.say(chatId, `${title} (${agentId})${status}\n\n${text || 'No text reply. Open Paseo for details.'}`);
  }
}
class InputError extends Error {}
