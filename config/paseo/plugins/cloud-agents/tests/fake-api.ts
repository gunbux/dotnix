import assert from 'node:assert/strict';
import { createServer, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import { MANAGED_AGENTS_BETA, type MaEvent } from '../server/claude-api.ts';

/** In-memory Managed Agents API: one agent that runs a tool needing approval, then replies. */
export async function fakeApi() {
  const events: MaEvent[] = [];
  const streams = new Set<ServerResponse>();
  let clock = Date.parse('2026-10-06T00:00:00Z');
  let status = 'idle';
  let failLists = 0;
  let archived = false;
  const push = (event: Omit<MaEvent, 'id' | 'processed_at'>) => {
    const full = { id: `sevt_${events.length + 1}`, processed_at: new Date(clock += 1000).toISOString(), ...event } as MaEvent;
    events.push(full);
    for (const res of streams) res.write(`event: message\ndata: ${JSON.stringify(full)}\n\n`);
  };
  const session = () => ({
    id: 'sesn_1', title: 'Cloud', status, archived_at: archived ? '2026-10-06T00:00:00Z' : null, created_at: '', updated_at: '', environment_id: 'env_1',
    agent: { id: 'agent_1', name: 'Coder', version: 1, model: { id: 'claude-opus-5-5' } }, metadata: { paseo_cwd: '/repo' },
  });
  const server = createServer(async (req, res) => {
    assert.equal(req.headers['x-api-key'], 'sk-test');
    assert.equal(req.headers['anthropic-beta'], MANAGED_AGENTS_BETA);
    const url = new URL(req.url!, 'http://x');
    let body = '';
    for await (const chunk of req) body += chunk;
    const json = (value: unknown) => { res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(value)); };
    if (req.method === 'GET' && url.pathname === '/v1/agents') {
      return json({ data: [{ id: 'agent_1', name: 'Coder', archived_at: null, model: { id: 'claude-opus-5-5' } }], next_page: null });
    }
    if (req.method === 'GET' && url.pathname === '/v1/environments') {
      return json({ data: [{ id: 'env_1', name: 'Default sandbox', archived_at: null }], next_page: null });
    }
    if (req.method === 'GET' && url.pathname === '/v1/sessions') return json({ data: [session()], next_page: null });
    if (req.method === 'POST' && url.pathname === '/v1/sessions/sesn_1/archive') { archived = true; return json(session()); }
    if (req.method === 'POST' && url.pathname === '/v1/sessions') return json(session());
    if (req.method === 'GET' && url.pathname === '/v1/sessions/sesn_1') return json(session());
    if (req.method === 'GET' && url.pathname === '/v1/sessions/sesn_1/events') {
      if (failLists > 0) { failLists--; res.writeHead(500, { 'content-type': 'application/json' }); return res.end('{"error":{"message":"boom"}}'); }
      const since = url.searchParams.get('created_at[gte]');
      return json({ data: events.filter(e => !since || String(e.processed_at) >= since), next_page: null });
    }
    if (req.method === 'GET' && url.pathname === '/v1/sessions/sesn_1/events/stream') {
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      res.write(': connected\n\n');
      streams.add(res);
      res.on('close', () => streams.delete(res));
      return;
    }
    if (req.method === 'POST' && url.pathname === '/v1/sessions/sesn_1/events') {
      json({ data: [] });
      for (const event of JSON.parse(body).events as MaEvent[]) {
        if (event.type === 'user.message') {
          push(event);
          status = 'running';
          push({ type: 'session.status_running' });
          push({ type: 'agent.tool_use', name: 'bash', input: { command: 'make test' }, evaluated_permission: 'ask' });
          push({ type: 'session.status_idle', stop_reason: { type: 'requires_action', event_ids: [events.at(-1)!.id] } });
        } else if (event.type === 'user.tool_confirmation') {
          push(event);
          push({ type: 'agent.tool_result', tool_use_id: event.tool_use_id, content: [{ type: 'text', text: 'ok' }] });
          push({ type: 'agent.message', content: [{ type: 'text', text: 'Tests pass.' }] });
          status = 'idle';
          push({ type: 'session.status_idle', stop_reason: { type: 'end_turn' } });
        }
      }
      return;
    }
    res.writeHead(404).end('{}');
  });
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
  const baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  return {
    baseUrl, events, push,
    isArchived: () => archived,
    failNextLists(n: number) { failLists = n; },
    dropStreams() { for (const res of streams) res.destroy(); streams.clear(); },
    streamCount: () => streams.size,
    close: () => new Promise<void>(resolve => { for (const res of streams) res.destroy(); server.close(() => resolve()); }),
  };
}

