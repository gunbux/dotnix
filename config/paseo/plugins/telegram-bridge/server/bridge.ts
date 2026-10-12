import { randomBytes } from 'node:crypto';
import type { AgentPermissionRequest, AgentPermissionResponse, AgentTimelineItem } from '@getpaseo/protocol/agent-types';
import type { PluginTurnOutcome } from '@getpaseo/plugin/server';
import type { State } from './state.ts';
import { splitText, type Update, type Button } from './telegram.ts';

export interface AgentPort {
  agents(): Promise<{ id: string; title: string; status: string }[]>;
  workspaces(): Promise<{ id: string; title: string }[]>;
  create(workspace: string, provider: string): Promise<string>;
  send(agent: string, text: string, key: string): Promise<void>;
  stop(agent: string): Promise<void>;
  permissions(agent: string): Promise<AgentPermissionRequest[]>;
  respond(agent: string, request: string, response: AgentPermissionResponse): Promise<void>;
}
type Options = { state: State; port: AgentPort; save(): Promise<void>; now(): number; defaultProvider: string };
const help = '/agents — list agents\n/use <id> — select and watch an agent\n/workspaces — list workspaces\n/new <workspace-id> <prompt> — create and select an agent\n/status — show selection and pending approvals\n/stop — interrupt the selected agent\n/unwatch <id> — stop its notifications\n/help — show commands\n\nSend ordinary text to your selected agent. Use /send <text> for a prompt beginning with a slash.';

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
  private async say(text: string, buttons?: Button[][]) {
    const chunks = splitText(text);
    chunks.forEach((text, i) => this.state.outbox.push({ text, ...(i === chunks.length - 1 && buttons ? { buttons } : {}) }));
    await this.options.save();
  }
  async update(update: Update): Promise<{ callbackId: string; text: string } | undefined> {
    if (!Number.isSafeInteger(update.update_id) || update.update_id < this.state.offset) return;
    // Checkpoint BEFORE effects. An interrupted command is never replayed after a restart.
    this.state.offset = update.update_id + 1;
    await this.options.save();
    const callback = update.callback_query;
    const message = callback?.message ?? update.message;
    const from = callback?.from ?? update.message?.from;
    if (!from || String(from.id) !== this.state.owner || !message || message.chat.type !== 'private' || String(message.chat.id) !== this.state.owner) return;
    if (callback) {
      try { return { callbackId: callback.id, text: await this.answer(callback.data ?? '') }; }
      catch { await this.say('Could not answer this request. Check /status or answer it in Paseo.'); return { callbackId: callback.id, text: 'Request was not confirmed.' }; }
    }
    if (!update.message || this.options.now() - update.message.date * 1000 > 300000) return;
    const text = update.message.text?.trim();
    if (!text) { await this.say('This bridge accepts text messages.'); return; }
    try { await this.command(text, update.update_id); }
    catch (error) {
      // Only display our own validation errors; SDK errors can include provider data.
      await this.say(error instanceof InputError ? error.message : 'The command could not be completed. Check the agent in Paseo before retrying.');
    }
  }
  private async command(text: string, updateId: number) {
    const [word] = text.split(/\s/, 1);
    const command = word.toLowerCase();
    const args = text.slice(word.length).trim();
    const { port } = this.options;
    const select = () => {
      if (!this.state.selectedAgent) throw new InputError('Select an agent first with /use <id>.');
      return this.state.selectedAgent;
    };
    if (command === '/start' || command === '/help') return this.say(help);
    if (command === '/agents') {
      const agents = await port.agents();
      return this.say(agents.map(a => `${a.title} [${a.status}]\n/use ${a.id}`).join('\n\n') || 'No agents found.');
    }
    if (command === '/workspaces') return this.say((await port.workspaces()).map(w => `${w.title}\n${w.id}`).join('\n\n') || 'No workspaces found.');
    if (command === '/use') {
      const agents = await port.agents();
      let agent;
      try { agent = resolveId(agents, args); } catch (e) { throw new InputError((e as Error).message); }
      this.state.selectedAgent = agent.id;
      if (!this.state.watchedAgents.includes(agent.id)) this.state.watchedAgents.push(agent.id);
      await this.say(`Selected ${agent.title} (${agent.id}).`);
      return this.pending(agent.id);
    }
    if (command === '/new') {
      if (!this.options.defaultProvider.includes('/')) throw new InputError('Set the default provider/model in the Telegram bridge settings in Paseo first.');
      const match = /^(\S+)\s+([\s\S]+)$/.exec(args);
      if (!match) throw new InputError('Use /new <workspace-id> <prompt>.');
      const workspaces = await port.workspaces();
      let workspace;
      try { workspace = resolveId(workspaces, match[1]); } catch (e) { throw new InputError((e as Error).message); }
      const id = await port.create(workspace.id, this.options.defaultProvider);
      this.state.selectedAgent = id;
      this.state.watchedAgents.push(id);
      await this.say(`Created and selected ${id} in ${workspace.title}.`);
      await port.send(id, match[2], `telegram:${this.state.botId}:${updateId}`);
      return;
    }
    if (command === '/status') {
      await this.say(`Selected: ${this.state.selectedAgent ?? 'none'}\nWatching: ${this.state.watchedAgents.join(', ') || 'none'}`);
      if (this.state.selectedAgent) await this.pending(this.state.selectedAgent, true);
      return;
    }
    if (command === '/stop') { const id = select(); await port.stop(id); return this.say(`Stop requested for ${id}.`); }
    if (command === '/unwatch') {
      let id;
      try { id = resolveId(this.state.watchedAgents.map(id => ({ id })), args || select()).id; } catch (e) { throw new InputError((e as Error).message); }
      this.state.watchedAgents = this.state.watchedAgents.filter(a => a !== id);
      if (this.state.selectedAgent === id) this.state.selectedAgent = null;
      for (const [key, value] of Object.entries(this.state.approvals)) if (value.agentId === id) delete this.state.approvals[key];
      return this.say(`Stopped watching ${id}.`);
    }
    if (text.startsWith('/') && command !== '/send') throw new InputError('Unknown command. Use /help, or /send <text> to send a slash command to the agent.');
    const prompt = command === '/send' ? args : text;
    if (!prompt) throw new InputError('Provide a message after /send.');
    await port.send(select(), prompt, `telegram:${this.state.botId}:${updateId}`);
    await this.say(`Sent to ${select()}.`);
  }
  async pending(agentId: string, repeat = false) {
    for (const request of await this.options.port.permissions(agentId)) await this.permission(agentId, request, repeat);
  }
  async permission(agentId: string, request: AgentPermissionRequest, repeat = false) {
    if (!this.state.watchedAgents.includes(agentId)) return;
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
      await this.say(`${title}\n${description}\nAnswer this request in Paseo. It requires structured input.`);
      return;
    }
    const actions = request.actions?.length
      ? request.actions.map(a => ({ label: a.label, behavior: a.behavior, selectedActionId: a.id }))
      : [{ label: 'Allow once', behavior: 'allow' as const }, { label: 'Deny', behavior: 'deny' as const }];
    const key = randomBytes(12).toString('hex');
    this.state.approvals[key] = { agentId, requestId: request.id, expires: this.options.now() + 15 * 60000, actions };
    // Always put the complete request before its buttons, even when it spans messages.
    if (description) await this.say(`${title}\n\n${description}`);
    await this.say(`${title}\nChoose a response. Buttons expire after 15 minutes.`, actions.map((action, index) => [{ text: action.label.slice(0, 60), callback_data: `p:${key}:${index}` }]));
  }
  private async answer(data: string): Promise<string> {
    const match = /^p:([a-f0-9]{24}):(\d+)$/.exec(data);
    const approval = match && this.state.approvals[match[1]];
    if (!match || !approval || approval.expires <= this.options.now()) {
      await this.say('This approval expired. Use /status for current requests.');
      return 'Expired request.';
    }
    const action = approval.actions[Number(match[2])];
    if (!action) return 'Invalid response.';
    const pending = await this.options.port.permissions(approval.agentId);
    if (!pending.some(p => p.id === approval.requestId)) {
      delete this.state.approvals[match[1]];
      await this.say('This request is no longer pending.');
      return 'Already resolved.';
    }
    // Consume before the RPC so a lost response cannot trigger a second approval.
    delete this.state.approvals[match[1]];
    await this.options.save();
    const response: AgentPermissionResponse = { behavior: action.behavior, ...(action.selectedActionId ? { selectedActionId: action.selectedActionId } : {}) };
    await this.options.port.respond(approval.agentId, approval.requestId, response);
    await this.say(`${action.label}: ${approval.requestId} (${approval.agentId}).`);
    return 'Response sent.';
  }
  async resolved(agentId: string, requestId: string) {
    for (const [key, value] of Object.entries(this.state.approvals)) if (value.agentId === agentId && value.requestId === requestId) delete this.state.approvals[key];
    await this.options.save();
  }
  async finished(agentId: string, title: string, timeline: readonly AgentTimelineItem[], outcome: PluginTurnOutcome) {
    if (!this.state.watchedAgents.includes(agentId)) return;
    const start = timeline.findLastIndex(item => item.type === 'user_message');
    const text = timeline.slice(start + 1).filter(item => item.type === 'assistant_message').map(item => item.text).join('\n\n');
    const status = outcome.kind === 'completed' ? '' : `\nTurn ${outcome.kind}.`;
    await this.say(`${title} (${agentId})${status}\n\n${text || 'No text reply. Open Paseo for details.'}`);
  }
}
class InputError extends Error {}
