import type { ProviderEvent, ProviderPersistence, ProviderToolCallDetail } from '@getpaseo/plugin/server/provider';
import type { MaEvent } from './claude-api.ts';

/** Per-session translation state. Mutated by `translate`. */
export interface TranslateState {
  sessionId: string;
  activeTurnId: string | null;
  interrupted: boolean;
  /** Text of locally sent prompts whose `user.message` echo has not arrived yet. */
  pendingEchoes: string[];
  tools: Map<string, { name: string; detail: ProviderToolCallDetail; input: Record<string, unknown> }>;
  permissions: Set<string>;
  newTurnId(): string;
}

export function createTranslateState(sessionId: string, newTurnId: () => string): TranslateState {
  return { sessionId, activeTurnId: null, interrupted: false, pendingEchoes: [], tools: new Map(), permissions: new Set(), newTurnId };
}

type Block = { type?: string; text?: string };
export function blocksText(content: unknown): string {
  if (!Array.isArray(content)) return '';
  return (content as Block[]).map(block => block?.type === 'text' && typeof block.text === 'string' ? block.text
    : block?.type === 'redacted' ? '[redacted]' : '').filter(Boolean).join('\n');
}

type JsonValue = ProviderPersistence['data'];

const str = (value: unknown): string | undefined => typeof value === 'string' ? value : undefined;
function json(value: unknown): JsonValue {
  return value === undefined ? null : JSON.parse(JSON.stringify(value)) as JsonValue;
}

/** Map a Managed Agents built-in or MCP tool call onto Paseo's richer tool detail where the shape is recognisable. */
export function toolDetail(name: string, input: Record<string, unknown>, output?: string): ProviderToolCallDetail {
  const tool = name.toLowerCase();
  const path = str(input.file_path) ?? str(input.path) ?? str(input.filePath);
  if (tool === 'bash' || tool === 'shell') {
    return { type: 'shell', command: str(input.command) ?? JSON.stringify(input), output };
  }
  if (tool === 'read' && path) return { type: 'read', filePath: path, content: output };
  if (tool === 'write' && path) return { type: 'write', filePath: path, content: str(input.content) };
  if ((tool === 'edit' || tool === 'str_replace') && path) {
    return { type: 'edit', filePath: path, oldString: str(input.old_string) ?? str(input.old_str), newString: str(input.new_string) ?? str(input.new_str) };
  }
  if (tool === 'glob' || tool === 'grep') {
    return { type: 'search', query: str(input.pattern) ?? str(input.query) ?? '', toolName: tool, content: output };
  }
  if (tool === 'web_search') return { type: 'search', query: str(input.query) ?? '', toolName: 'web_search', content: output };
  if (tool === 'web_fetch') return { type: 'fetch', url: str(input.url) ?? '', prompt: str(input.prompt), result: output };
  return { type: 'unknown', input: json(input), output: output === undefined ? null : output };
}

function withOutput(detail: ProviderToolCallDetail, output: string): ProviderToolCallDetail {
  switch (detail.type) {
    case 'shell': return { ...detail, output };
    case 'read': return { ...detail, content: output };
    case 'search': return { ...detail, content: output };
    case 'fetch': return { ...detail, result: output };
    case 'unknown': return { ...detail, output };
    default: return detail;
  }
}

/**
 * Translate one Managed Agents event into Paseo provider events.
 * `live` is false while replaying history: no turns or permissions are opened for past events.
 */
export function translate(event: MaEvent, state: TranslateState, live: boolean): ProviderEvent[] {
  const sessionId = state.sessionId;
  const out: ProviderEvent[] = [];
  const timestamp = event.processed_at ?? undefined;
  const item = (value: Extract<ProviderEvent, { type: 'timeline.item' }>['item']) =>
    out.push({ type: 'timeline.item', sessionId, item: value, ...(timestamp ? { timestamp } : {}) });
  const startTurn = () => {
    if (!live || state.activeTurnId) return;
    state.activeTurnId = state.newTurnId();
    state.interrupted = false;
    out.push({ type: 'session.turn', sessionId, turnId: state.activeTurnId, state: 'started' });
  };
  const endTurn = (result: 'completed' | 'failed' | 'canceled', message?: string) => {
    if (!state.activeTurnId) return;
    out.push({ type: 'session.turn', sessionId, turnId: state.activeTurnId, state: result, ...(message ? { error: { message } } : {}) });
    state.activeTurnId = null;
    state.interrupted = false;
    for (const permissionId of state.permissions) out.push({ type: 'session.permission_resolved', sessionId, permissionId });
    state.permissions.clear();
  };

  switch (event.type) {
    case 'user.message': {
      const text = blocksText(event.content);
      const echo = state.pendingEchoes.indexOf(text);
      if (echo !== -1) { state.pendingEchoes.splice(echo, 1); break; }
      item({ type: 'user_message', id: event.id, text, messageId: event.id });
      break;
    }
    case 'agent.message':
      startTurn();
      item({ type: 'assistant_message', id: event.id, text: blocksText(event.content), messageId: event.id });
      break;
    case 'agent.tool_use':
    case 'agent.mcp_tool_use':
    case 'agent.custom_tool_use': {
      startTurn();
      const name = event.type === 'agent.mcp_tool_use' ? `${str(event.mcp_server_name) ?? 'mcp'}/${str(event.name) ?? 'tool'}` : str(event.name) ?? 'tool';
      const input = (event.input && typeof event.input === 'object' ? event.input : {}) as Record<string, unknown>;
      const detail = toolDetail(event.type === 'agent.mcp_tool_use' ? 'mcp' : name, input);
      state.tools.set(event.id, { name, detail, input });
      item({ type: 'tool_call', id: event.id, callId: event.id, name, detail, status: 'running', error: null });
      if (live && event.evaluated_permission === 'ask') {
        state.permissions.add(event.id);
        out.push({ type: 'session.permission', sessionId, request: {
          id: event.id, name, kind: 'tool', title: `Allow ${name}?`, input: json(input) as Record<string, JsonValue>, detail,
          actions: [
            { id: 'allow', label: 'Allow', behavior: 'allow', variant: 'primary' },
            { id: 'deny', label: 'Deny', behavior: 'deny', variant: 'danger' },
          ],
        } });
      }
      break;
    }
    case 'agent.tool_result':
    case 'agent.mcp_tool_result': {
      const toolUseId = str(event.tool_use_id) ?? str(event.mcp_tool_use_id);
      const tool = toolUseId ? state.tools.get(toolUseId) : undefined;
      if (!toolUseId || !tool) break;
      const output = blocksText(event.content);
      const detail = withOutput(tool.detail, output);
      item(event.is_error
        ? { type: 'tool_call', id: toolUseId, callId: toolUseId, name: tool.name, detail, status: 'failed', error: output || 'Tool failed' }
        : { type: 'tool_call', id: toolUseId, callId: toolUseId, name: tool.name, detail, status: 'completed', error: null });
      break;
    }
    case 'user.tool_confirmation': {
      const toolUseId = str(event.tool_use_id);
      if (!toolUseId) break;
      if (state.permissions.delete(toolUseId)) out.push({ type: 'session.permission_resolved', sessionId, permissionId: toolUseId });
      const tool = state.tools.get(toolUseId);
      if (event.result === 'deny' && tool) {
        item({ type: 'tool_call', id: toolUseId, callId: toolUseId, name: tool.name, detail: tool.detail, status: 'canceled', error: null });
      }
      break;
    }
    case 'agent.thread_context_compacted':
      item({ type: 'compaction', id: event.id, status: 'completed', trigger: 'auto' });
      break;
    case 'session.status_running':
      startTurn();
      break;
    case 'session.status_idle': {
      const reason = (event.stop_reason ?? {}) as { type?: string };
      if (reason.type === 'requires_action') break;
      if (state.interrupted) { endTurn('canceled'); break; }
      if (!reason.type || reason.type === 'end_turn') { endTurn('completed'); break; }
      const details = (event.stop_details ?? null) as { explanation?: string | null } | null;
      const message = reason.type === 'budget_reached' ? 'Session budget reached'
        : reason.type === 'retries_exhausted' ? 'Model retries exhausted'
        : reason.type === 'refusal' ? `Refused${details?.explanation ? `: ${details.explanation}` : ''}` : `Stopped: ${reason.type}`;
      if (live) item({ type: 'error', id: event.id, message });
      endTurn('failed', message);
      break;
    }
    case 'session.status_terminated':
      item({ type: 'notification', id: event.id, level: 'error', message: 'The cloud session was terminated.' });
      endTurn('failed', 'Session terminated');
      break;
    case 'session.error': {
      const error = (event.error ?? {}) as { message?: string; type?: string; retry_status?: { type?: string } };
      const retrying = error.retry_status?.type === 'retrying';
      item({ type: 'notification', id: event.id, level: retrying ? 'warning' : 'error',
        message: `${error.message ?? error.type ?? 'Session error'}${retrying ? ' (retrying)' : ''}` });
      break;
    }
    case 'span.model_request_end': {
      if (!live) break;
      const usage = (event.model_usage ?? {}) as { input_tokens?: number; output_tokens?: number; cache_read_input_tokens?: number };
      out.push({ type: 'session.usage', sessionId, ...(state.activeTurnId ? { turnId: state.activeTurnId } : {}), usage: {
        inputTokens: usage.input_tokens, outputTokens: usage.output_tokens, cachedInputTokens: usage.cache_read_input_tokens,
      } });
      break;
    }
  }
  return out;
}
