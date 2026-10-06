import {
  negotiateProviderCapabilities,
  requireProviderCapabilities,
  type ProviderConnection,
  type ProviderContent,
  type ProviderEvent,
  type ProviderInput,
  type ProviderPersistence,
  type ProviderRegistration,
} from '@getpaseo/plugin/server/provider';
import { randomUUID } from 'node:crypto';
import { homedir } from 'node:os';
import type { ManagedAgentsApi, MaEvent } from './claude-api.ts';
import { blocksText, createTranslateState, translate, type TranslateState } from './translate.ts';

const CAPABILITIES = ['prompt.message', 'prompt.image', 'permission', 'session.persistence', 'session.archive', 'session.list'] as const;

export interface ProviderDeps {
  /** Resolve a client from current settings. Throws a user-facing error when unconfigured. */
  api(): Promise<ManagedAgentsApi>;
  defaults(): Promise<{ agentId: string; environmentId: string }>;
  /** Delay before reconnecting a dropped event stream. Overridable for tests. */
  retryDelayMs?: (attempt: number) => number;
}

interface LiveSession {
  remoteId: string;
  state: TranslateState;
  abort: AbortController;
  seen: Set<string>;
  since: string | undefined;
}

type Open = Extract<ProviderInput, { type: 'session.open' }>;
type Prompt = Extract<ProviderInput, { type: 'session.prompt' }>;

export function persistenceFor(remoteId: string): ProviderPersistence {
  return { version: 1, data: { sessionId: remoteId } };
}
export function remoteIdFrom(persistence: ProviderPersistence | undefined): string | null {
  const data = persistence?.data as { sessionId?: unknown } | null | undefined;
  return typeof data?.sessionId === 'string' && data.sessionId ? data.sessionId : null;
}

export function createClaudeCloudProvider(deps: ProviderDeps): ProviderRegistration {
  return {
    id: 'claude-cloud',
    label: 'Claude (cloud)',
    description: 'Claude Managed Agents sessions running in Anthropic-hosted sandboxes',
    icon: 'icon.svg',
    async connect(request) {
      if (!request.versions.includes(1)) throw new Error('Provider protocol version 1 is required');
      return createConnection(deps, negotiateProviderCapabilities(request.capabilities, CAPABILITIES));
    },
  };
}

function createConnection(deps: ProviderDeps, capabilities: readonly string[]): ProviderConnection {
  const listeners = new Set<(event: ProviderEvent) => void>();
  const sessions = new Map<string, LiveSession>();
  const opening = new Set<string>();
  let closed = false;
  const emit = (event: ProviderEvent) => {
    if (closed) return;
    for (const listener of listeners) listener(event);
  };
  const retryDelay = deps.retryDelayMs ?? (attempt => Math.min(30_000, 1000 * 2 ** attempt));

  function fail(input: ProviderInput, error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    if ('requestId' in input) emit({ type: 'request.failed', requestId: input.requestId, error: { message } });
    else if (input.type === 'session.prompt') {
      const live = sessions.get(input.sessionId);
      if (live?.state.activeTurnId) {
        emit({ type: 'session.turn', sessionId: input.sessionId, turnId: live.state.activeTurnId, state: 'failed', error: { message } });
        live.state.activeTurnId = null;
      }
    } else if ('sessionId' in input) {
      emit({ type: 'session.notice', sessionId: input.sessionId, notice: { id: randomUUID(), severity: 'error', title: message } });
    }
  }

  function handle(live: LiveSession, sessionId: string, event: MaEvent, isLive: boolean) {
    if (live.seen.has(event.id)) return;
    live.seen.add(event.id);
    if (event.processed_at && (!live.since || event.processed_at > live.since)) live.since = event.processed_at;
    for (const out of translate(event, live.state, isLive)) emit(out);
    if (event.type === 'session.status_terminated') {
      live.abort.abort();
      emit({ type: 'session.closed', sessionId, error: { message: 'The cloud session was terminated' } });
      sessions.delete(sessionId);
    }
  }

  /** Follow the SSE stream, backfilling from the list endpoint after every (re)connect so no event is lost. */
  async function follow(sessionId: string, live: LiveSession, api: ManagedAgentsApi) {
    let attempt = 0;
    while (!live.abort.signal.aborted && !closed) {
      let backfilling = true;
      const queued: MaEvent[] = [];
      // Each attempt owns its stream so a failed backfill never leaves a second stream running.
      const iteration = new AbortController();
      const stop = () => iteration.abort();
      live.abort.signal.addEventListener('abort', stop, { once: true });
      const stream = api.stream(live.remoteId, event => {
        if (iteration.signal.aborted) return;
        if (backfilling) queued.push(event); else handle(live, sessionId, event, true);
      }, iteration.signal);
      stream.catch(() => {}); // observed below; avoids an unhandled rejection while backfilling
      try {
        const missed = await api.listEvents(live.remoteId, live.since);
        for (const event of missed) handle(live, sessionId, event, true);
        backfilling = false;
        for (const event of queued.splice(0)) handle(live, sessionId, event, true);
        attempt = 0;
        await stream;
      } catch (error) {
        if (live.abort.signal.aborted || closed) return;
        if (attempt === 2) emit({ type: 'session.notice', sessionId, notice: {
          id: `stream-${live.remoteId}`, severity: 'warning', title: 'Reconnecting to the cloud session',
          description: error instanceof Error ? error.message : String(error),
        } });
      } finally {
        stop();
        live.abort.signal.removeEventListener('abort', stop);
      }
      if (live.abort.signal.aborted || closed) return;
      await new Promise(resolve => setTimeout(resolve, retryDelay(attempt++)));
    }
  }

  async function open(input: Open) {
    const api = await deps.api();
    const resumeId = remoteIdFrom(input.persistence);
    let session;
    if (resumeId) {
      session = await api.getSession(resumeId);
      if (session.status === 'terminated') throw new Error(`Cloud session ${resumeId} has terminated`);
    } else {
      const defaults = await deps.defaults();
      const agent = input.config.model || defaults.agentId;
      const environment = input.config.mode || defaults.environmentId;
      if (!agent) throw new Error('Choose a managed agent (model), or set a default agent in Cloud agents settings');
      if (!environment) throw new Error('Choose an environment (mode), or set a default environment in Cloud agents settings');
      session = await api.createSession({
        agent, environment_id: environment, ...(input.config.title ? { title: input.config.title } : {}),
        metadata: { source: 'paseo', paseo_cwd: input.config.cwd.slice(0, 500) },
      });
    }
    const remoteId = session.id;
    const title = session.title ?? input.config.title;
    const live: LiveSession = {
      remoteId, abort: new AbortController(), seen: new Set(), since: undefined,
      state: createTranslateState(input.sessionId, randomUUID),
    };
    sessions.set(input.sessionId, live);
    emit({
      type: 'session.opened', requestId: input.requestId, sessionId: input.sessionId, capabilities,
      restoration: 'core', persistence: persistenceFor(remoteId), cwd: input.config.cwd,
      ...(title ? { title } : {}), description: `${session.agent.name} · ${session.agent.model.id}`,
    });
    emit({ type: 'session.config', sessionId: input.sessionId, config: {
      model: session.agent.id, mode: session.environment_id,
      models: [{ id: session.agent.id, label: session.agent.name, description: session.agent.model.id }],
      modes: [{ id: session.environment_id, label: session.environment_id }],
      thinkingOptions: [], settings: [],
    } });

    const history = await api.listEvents(remoteId);
    const asks = new Map<string, MaEvent>();
    for (const event of history) {
      live.seen.add(event.id);
      if (event.processed_at && (!live.since || event.processed_at > live.since)) live.since = event.processed_at;
      if (event.evaluated_permission === 'ask') asks.set(event.id, event);
      if (typeof event.tool_use_id === 'string') asks.delete(event.tool_use_id);
      if (typeof event.mcp_tool_use_id === 'string') asks.delete(event.mcp_tool_use_id);
      const events = translate(event, live.state, false);
      if (input.history === 'replay') for (const out of events) emit(out);
    }
    // Resume mid-flight work: a running session gets a live turn, unanswered approvals become prompts again.
    if (session.status === 'running' || session.status === 'rescheduling' || asks.size) {
      for (const out of translate({ id: `resume:${randomUUID()}`, type: 'session.status_running' }, live.state, true)) emit(out);
      for (const event of asks.values()) {
        for (const out of translate(event, live.state, true)) if (out.type === 'session.permission') emit(out);
      }
    }
    emit({ type: 'session.ready', requestId: input.requestId, sessionId: input.sessionId });
    void follow(input.sessionId, live, api);
  }

  async function prompt(input: Prompt) {
    const live = requireLive(input.sessionId);
    const { prompt } = input;
    if (prompt.input.type !== 'message') {
      emit({ type: 'session.prompt_result', sessionId: input.sessionId, clientMessageId: prompt.clientMessageId,
        result: { type: 'failed', error: { message: 'Commands are not supported by Claude cloud sessions' } } });
      return;
    }
    const content = toBlocks(prompt.input.content);
    const text = blocksText(content);
    const turnId = live.state.activeTurnId ?? randomUUID();
    const startsTurn = !live.state.activeTurnId;
    live.state.activeTurnId = turnId;
    live.state.interrupted = false;
    live.state.pendingEchoes.push(text);
    emit({ type: 'timeline.item', sessionId: input.sessionId, item: {
      type: 'user_message', id: `user:${prompt.clientMessageId}`, text, clientMessageId: prompt.clientMessageId,
    } });
    emit({ type: 'session.prompt_result', sessionId: input.sessionId, clientMessageId: prompt.clientMessageId, result: { type: 'turn', turnId } });
    if (startsTurn) emit({ type: 'session.turn', sessionId: input.sessionId, turnId, state: 'started' });
    try {
      const api = await deps.api();
      await api.sendEvents(live.remoteId, [{ type: 'user.message', content }]);
    } catch (error) {
      const index = live.state.pendingEchoes.indexOf(text);
      if (index !== -1) live.state.pendingEchoes.splice(index, 1);
      throw error;
    }
  }

  function requireLive(sessionId: string): LiveSession {
    const live = sessions.get(sessionId);
    if (!live) throw new Error(`Unknown session: ${sessionId}`);
    return live;
  }

  async function dispatch(input: ProviderInput) {
    switch (input.type) {
      case 'catalog': {
        const api = await deps.api();
        const [agents, environments, defaults] = await Promise.all([api.listAgents(), api.listEnvironments(), deps.defaults()]);
        const models = agents.filter(a => !a.archived_at).map(a => ({
          id: a.id, label: a.name, description: a.model.id, isDefault: a.id === defaults.agentId,
        }));
        const modes = environments.filter(e => !e.archived_at).map(e => ({ id: e.id, label: e.name, description: e.id }));
        emit({ type: 'catalog', requestId: input.requestId, catalog: {
          models, modes, thinkingOptions: [],
          defaultModel: models.find(m => m.isDefault)?.id ?? models[0]?.id,
          defaultMode: modes.find(m => m.id === defaults.environmentId)?.id ?? modes[0]?.id,
        } });
        return;
      }
      case 'sessions': {
        const api = await deps.api();
        const limit = Math.max(1, Math.min(input.limit ?? 50, 100));
        const query = input.query?.trim().toLowerCase();
        const found = (await api.listSessions(false, query ? 100 : limit))
          .filter(s => s.status !== 'terminated')
          .filter(s => !query || `${s.title ?? ''} ${s.id} ${s.agent.name}`.toLowerCase().includes(query))
          .filter(s => !input.cwd || !s.metadata.paseo_cwd || s.metadata.paseo_cwd === input.cwd)
          .slice(0, limit);
        emit({ type: 'sessions', requestId: input.requestId, sessions: found.map(s => ({
          persistence: persistenceFor(s.id), cwd: s.metadata.paseo_cwd || input.cwd || homedir(),
          title: s.title ?? undefined, description: `${s.agent.name} · ${s.status}`, updatedAt: s.updated_at,
        })) });
        return;
      }
      case 'session.open':
        try { await open(input); }
        catch (error) {
          sessions.get(input.sessionId)?.abort.abort();
          sessions.delete(input.sessionId);
          throw error;
        }
        return;
      case 'session.prompt':
        await prompt(input);
        return;
      case 'session.interrupt': {
        const live = requireLive(input.sessionId);
        if (live.state.activeTurnId) {
          live.state.interrupted = true;
          await (await deps.api()).sendEvents(live.remoteId, [{ type: 'user.interrupt' }]);
        }
        emit({ type: 'request.completed', requestId: input.requestId });
        return;
      }
      case 'session.permission': {
        const live = requireLive(input.sessionId);
        const { response } = input;
        const events: unknown[] = [{
          type: 'user.tool_confirmation', tool_use_id: input.permissionId, result: response.behavior,
          ...(response.behavior === 'deny' && response.message ? { deny_message: response.message } : {}),
        }];
        if (response.behavior === 'deny' && response.interrupt) {
          live.state.interrupted = true;
          events.push({ type: 'user.interrupt' });
        }
        await (await deps.api()).sendEvents(live.remoteId, events);
        if (live.state.permissions.delete(input.permissionId)) {
          emit({ type: 'session.permission_resolved', sessionId: input.sessionId, permissionId: input.permissionId });
        }
        return;
      }
      case 'session.archive': {
        const remoteId = remoteIdFrom(input.persistence);
        if (remoteId) await (await deps.api()).archiveSession(remoteId);
        emit({ type: 'request.completed', requestId: input.requestId });
        return;
      }
      case 'session.close': {
        // Closing only detaches Paseo; the cloud session stays resumable until archived.
        sessions.get(input.sessionId)?.abort.abort();
        sessions.delete(input.sessionId);
        emit({ type: 'session.closed', sessionId: input.sessionId });
        emit({ type: 'request.completed', requestId: input.requestId });
        return;
      }
      default:
        throw new Error(`Unsupported provider input: ${input.type}`);
    }
  }

  return {
    version: 1,
    capabilities,
    async send(input) {
      if (closed) throw new Error('Provider connection is closed');
      requireProviderCapabilities(capabilities, input);
      if (input.type === 'session.open') {
        if (sessions.has(input.sessionId) || opening.has(input.sessionId)) throw new Error(`Session already exists: ${input.sessionId}`);
        opening.add(input.sessionId);
      } else if ('sessionId' in input && input.type !== 'session.close' && !sessions.has(input.sessionId)) {
        throw new Error(`Unknown session: ${input.sessionId}`);
      }
      queueMicrotask(() => {
        dispatch(input).catch(error => fail(input, error)).finally(() => {
          if (input.type === 'session.open') opening.delete(input.sessionId);
        });
      });
    },
    onEvent(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    async close() {
      if (closed) return;
      closed = true;
      for (const live of sessions.values()) live.abort.abort();
      sessions.clear();
      listeners.clear();
    },
  };
}

/** Convert Paseo prompt content to Managed Agents content blocks. Rich attachments become labelled text. */
export function toBlocks(content: readonly ProviderContent[]): Array<Record<string, unknown>> {
  const blocks: Array<Record<string, unknown>> = [];
  const text = (value: string) => { if (value.trim()) blocks.push({ type: 'text', text: value }); };
  for (const part of content) {
    switch (part.type) {
      case 'text': text('title' in part && part.title ? `${part.title}\n${part.text}` : part.text); break;
      case 'image': blocks.push({ type: 'image', source: { type: 'base64', media_type: part.mimeType, data: part.data } }); break;
      case 'github_pr':
      case 'forge_change_request':
        text(`Pull request #${part.number}: ${part.title}\n${part.url}${part.body ? `\n\n${part.body}` : ''}`); break;
      case 'github_issue':
      case 'forge_issue':
        text(`Issue #${part.number}: ${part.title}\n${part.url}${part.body ? `\n\n${part.body}` : ''}`); break;
      case 'review':
        text(`Review comments:\n${part.comments.map(c => `${c.filePath}:${c.lineNumber} ${c.body}`).join('\n')}`); break;
      case 'uploaded_file':
        text(`[Attached file ${part.fileName} is only on the local host and was not uploaded]`); break;
    }
  }
  return blocks.length ? blocks : [{ type: 'text', text: '(empty message)' }];
}
