import { readFile } from 'node:fs/promises';

export const MANAGED_AGENTS_BETA = 'managed-agents-2026-04-01';

/** Raw Managed Agents session event. Only the fields this plugin reads are typed. */
export interface MaEvent {
  id: string;
  type: string;
  processed_at?: string | null;
  [key: string]: unknown;
}
export interface MaSession {
  id: string;
  title: string | null;
  status: 'rescheduling' | 'running' | 'idle' | 'terminated';
  archived_at: string | null;
  created_at: string;
  updated_at: string;
  environment_id: string;
  agent: { id: string; name: string; version: number; model: { id: string } };
  metadata: Record<string, string>;
  usage?: { list_cost?: { amount?: string | number } | null };
}
export interface MaAgent { id: string; name: string; archived_at: string | null; model: { id: string } }
export interface MaEnvironment { id: string; name: string; archived_at: string | null }
interface Page<T> { data: T[]; next_page: string | null }

export type KeySource = { key: string; source: 'env' | 'file' } | { key: null; source: 'none'; detail: string };

/** Prefer ANTHROPIC_API_KEY in the daemon environment, then the configured secret file. */
export async function resolveApiKey(apiKeyFile: string, env = process.env): Promise<KeySource> {
  const fromEnv = env.ANTHROPIC_API_KEY?.trim();
  if (fromEnv) return { key: fromEnv, source: 'env' };
  if (!apiKeyFile) return { key: null, source: 'none', detail: 'ANTHROPIC_API_KEY is unset and no key file is configured' };
  try {
    const key = (await readFile(apiKeyFile, 'utf8')).trim();
    if (key) return { key, source: 'file' };
    return { key: null, source: 'none', detail: `${apiKeyFile} is empty` };
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    return { key: null, source: 'none', detail: `Cannot read ${apiKeyFile}${code ? ` (${code})` : ''}` };
  }
}

export class ManagedAgentsApi {
  private readonly baseUrl: string;
  private readonly apiKey: string;
  constructor(baseUrl: string, apiKey: string) {
    this.baseUrl = baseUrl;
    this.apiKey = apiKey;
  }

  private headers(extra: Record<string, string> = {}): Record<string, string> {
    return {
      'x-api-key': this.apiKey,
      'anthropic-version': '2023-06-01',
      'anthropic-beta': MANAGED_AGENTS_BETA,
      ...extra,
    };
  }

  private url(path: string, query: Record<string, string | number | boolean | undefined> = {}): string {
    const url = new URL(path, this.baseUrl.endsWith('/') ? this.baseUrl : `${this.baseUrl}/`);
    for (const [key, value] of Object.entries(query)) if (value !== undefined) url.searchParams.set(key, String(value));
    return url.toString();
  }

  async request<T>(method: string, path: string, options: { query?: Record<string, string | number | boolean | undefined>; body?: unknown; signal?: AbortSignal } = {}): Promise<T> {
    const response = await fetch(this.url(path, options.query), {
      method,
      headers: this.headers(options.body === undefined ? {} : { 'content-type': 'application/json' }),
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      signal: options.signal,
    });
    const text = await response.text();
    if (!response.ok) throw new Error(`Anthropic API ${method} ${path} → ${response.status}: ${apiErrorMessage(text)}`);
    return (text ? JSON.parse(text) : {}) as T;
  }

  private async all<T>(path: string, query: Record<string, string | number | boolean | undefined>, max = 500): Promise<T[]> {
    const items: T[] = [];
    let page: string | undefined;
    const seen = new Set<string>();
    do {
      const result: Page<T> = await this.request('GET', path, { query: { ...query, limit: 100, page } });
      items.push(...result.data);
      page = result.next_page ?? undefined;
      if (page && seen.has(page)) throw new Error(`Repeated page cursor from ${path}`);
      if (page) seen.add(page);
    } while (page && items.length < max);
    return items;
  }

  listAgents() { return this.all<MaAgent>('v1/agents', {}); }
  listEnvironments() { return this.all<MaEnvironment>('v1/environments', {}); }
  listSessions(includeArchived: boolean, max = 100) {
    return this.all<MaSession>('v1/sessions', { include_archived: includeArchived, order: 'desc' }, max);
  }
  getSession(id: string) { return this.request<MaSession>('GET', `v1/sessions/${encodeURIComponent(id)}`); }
  createSession(body: { agent: string; environment_id: string; title?: string; metadata?: Record<string, string> }) {
    return this.request<MaSession>('POST', 'v1/sessions', { body });
  }
  archiveSession(id: string) { return this.request<unknown>('POST', `v1/sessions/${encodeURIComponent(id)}/archive`, { body: {} }); }
  sendEvents(id: string, events: unknown[]) {
    return this.request<unknown>('POST', `v1/sessions/${encodeURIComponent(id)}/events`, { body: { events } });
  }
  /** Every persisted event in order, optionally only those processed at or after `since`. Callers dedupe by id. */
  listEvents(id: string, since?: string) {
    return this.all<MaEvent>(`v1/sessions/${encodeURIComponent(id)}/events`, { order: 'asc', 'created_at[gte]': since }, 5000);
  }

  /** Consume the SSE stream until it ends or `signal` aborts. Resolves when the server closes the stream. */
  async stream(id: string, onEvent: (event: MaEvent) => void, signal: AbortSignal): Promise<void> {
    const response = await fetch(this.url(`v1/sessions/${encodeURIComponent(id)}/events/stream`), {
      headers: this.headers({ accept: 'text/event-stream' }), signal,
    });
    if (!response.ok || !response.body) {
      throw new Error(`Anthropic API stream → ${response.status}: ${apiErrorMessage(await response.text())}`);
    }
    const parser = sseParser(onEvent);
    const decoder = new TextDecoder();
    for await (const chunk of response.body as unknown as AsyncIterable<Uint8Array>) parser(decoder.decode(chunk, { stream: true }));
    parser(decoder.decode() + '\n\n');
  }
}

function apiErrorMessage(text: string): string {
  try {
    const parsed = JSON.parse(text) as { error?: { message?: string } };
    if (parsed.error?.message) return parsed.error.message;
  } catch { /* not JSON */ }
  return text.slice(0, 500) || 'no response body';
}

/** Incremental text/event-stream parser that yields each JSON `data:` payload with an id and type. */
export function sseParser(onEvent: (event: MaEvent) => void): (chunk: string) => void {
  let buffer = '';
  return chunk => {
    buffer += chunk.replace(/\r\n?/g, '\n');
    let end: number;
    while ((end = buffer.indexOf('\n\n')) !== -1) {
      const block = buffer.slice(0, end);
      buffer = buffer.slice(end + 2);
      const data = block.split('\n').filter(line => line.startsWith('data:')).map(line => line.slice(5).replace(/^ /, '')).join('\n');
      if (!data) continue;
      try {
        const event = JSON.parse(data) as MaEvent;
        if (event && typeof event.type === 'string' && typeof event.id === 'string') onEvent(event);
      } catch { /* ignore keep-alives and malformed frames */ }
    }
  };
}
