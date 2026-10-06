import type { ProviderEvent } from '@getpaseo/plugin/server/provider';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ManagedAgentsApi } from '../server/claude-api.ts';
import { fakeApi } from './fake-api.ts';
import { createClaudeCloudProvider } from '../server/provider.ts';

async function until<T>(read: () => T | undefined, what: string, ms = 3000): Promise<T> {
  const deadline = Date.now() + ms;
  for (;;) {
    const value = read();
    if (value !== undefined && value !== false) return value;
    if (Date.now() > deadline) throw new Error(`Timed out waiting for ${what}`);
    await new Promise(resolve => setTimeout(resolve, 10));
  }
}

test('chat round trip with approval, stream reconnect, and resume with replay', async () => {
  const api = await fakeApi();
  const provider = createClaudeCloudProvider({
    api: async () => new ManagedAgentsApi(api.baseUrl, 'sk-test'),
    defaults: async () => ({ agentId: '', environmentId: '' }),
    retryDelayMs: () => 10,
  });
  const capabilities = ['prompt.message', 'permission', 'session.persistence', 'session.archive', 'session.list'];
  const connection = await provider.connect({ versions: [1], capabilities });
  const events: ProviderEvent[] = [];
  connection.onEvent(event => events.push(event));
  try {
    await connection.send({ type: 'session.open', requestId: 'open', sessionId: 'p1', history: 'skip',
      config: { cwd: '/repo', env: {}, mcpServers: {}, settings: {}, persist: true, model: 'agent_1', mode: 'env_1' } });
    const opened = await until(() => events.find(e => e.type === 'session.opened'), 'session.opened');
    assert.deepEqual(opened.type === 'session.opened' && opened.persistence, { version: 1, data: { sessionId: 'sesn_1' } });
    await until(() => events.some(e => e.type === 'session.ready') && api.streamCount() === 1, 'stream');

    await connection.send({ type: 'session.prompt', sessionId: 'p1', prompt: {
      clientMessageId: 'm1', delivery: 'auto', input: { type: 'message', content: [{ type: 'text', text: 'run tests' }] } } });
    const permission = await until(() => events.find(e => e.type === 'session.permission'), 'permission request');
    assert.ok(permission.type === 'session.permission');
    await connection.send({ type: 'session.permission', sessionId: 'p1', permissionId: permission.request.id, response: { behavior: 'allow' } });
    await until(() => events.find(e => e.type === 'session.turn' && e.state === 'completed'), 'turn completion');

    const items = events.flatMap(e => e.type === 'timeline.item' ? [e.item] : []);
    assert.equal(items.filter(i => i.type === 'user_message').length, 1, 'the server echo must not duplicate the prompt');
    assert.ok(items.some(i => i.type === 'user_message' && i.clientMessageId === 'm1'));
    assert.ok(items.some(i => i.type === 'assistant_message' && i.text === 'Tests pass.'));
    assert.deepEqual(events.filter(e => e.type === 'session.turn').map(e => e.type === 'session.turn' && e.state), ['started', 'completed']);
    assert.ok(events.some(e => e.type === 'session.prompt_result' && e.clientMessageId === 'm1' && e.result.type === 'turn'));

    // Events written while the stream is down are backfilled after reconnecting, exactly once.
    api.dropStreams();
    api.push({ type: 'agent.message', content: [{ type: 'text', text: 'while you were away' }] });
    await until(() => events.find(e => e.type === 'timeline.item' && e.item.type === 'assistant_message' && e.item.text === 'while you were away'), 'backfill');
    await until(() => api.streamCount() === 1, 'reconnect');
    await new Promise(resolve => setTimeout(resolve, 50));
    assert.equal(events.filter(e => e.type === 'timeline.item' && e.item.type === 'assistant_message' && e.item.text === 'while you were away').length, 1);

    // A failing backfill tears down its stream and retries; recovery leaves exactly one stream.
    api.failNextLists(3);
    api.dropStreams();
    api.push({ type: 'agent.message', content: [{ type: 'text', text: 'after a bad backfill' }] });
    await until(() => events.find(e => e.type === 'timeline.item' && e.item.type === 'assistant_message' && e.item.text === 'after a bad backfill'), 'recovery');
    await new Promise(resolve => setTimeout(resolve, 50));
    assert.equal(api.streamCount(), 1);
    assert.ok(events.some(e => e.type === 'session.notice' && /Reconnecting/.test(e.notice.title)));

    await connection.send({ type: 'session.close', requestId: 'close', sessionId: 'p1' });
    await until(() => events.find(e => e.type === 'request.completed' && e.requestId === 'close'), 'close');
    await until(() => api.streamCount() === 0, 'stream closed');

    // Reopen from persistence and replay history.
    const replayed: ProviderEvent[] = [];
    connection.onEvent(event => replayed.push(event));
    await connection.send({ type: 'session.open', requestId: 'reopen', sessionId: 'p2', history: 'replay',
      persistence: { version: 1, data: { sessionId: 'sesn_1' } },
      config: { cwd: '/repo', env: {}, mcpServers: {}, settings: {}, persist: true } });
    await until(() => replayed.find(e => e.type === 'session.ready'), 'reopen ready');
    const texts = replayed.flatMap(e => e.type === 'timeline.item' && 'text' in e.item ? [e.item.text] : []);
    assert.deepEqual(texts, ['run tests', 'Tests pass.', 'while you were away', 'after a bad backfill']);
    assert.ok(!replayed.some(e => e.type === 'session.turn' || e.type === 'session.permission'));
  } finally {
    await connection.close();
    await api.close();
  }
});

test('opening without an agent or environment fails the request with guidance', async () => {
  const provider = createClaudeCloudProvider({
    api: async () => new ManagedAgentsApi('http://127.0.0.1:9', 'sk'),
    defaults: async () => ({ agentId: '', environmentId: '' }),
  });
  const connection = await provider.connect({ versions: [1], capabilities: ['prompt.message'] });
  const events: ProviderEvent[] = [];
  connection.onEvent(event => events.push(event));
  await connection.send({ type: 'session.open', requestId: 'r', sessionId: 's', history: 'skip',
    config: { cwd: '/', env: {}, mcpServers: {}, settings: {}, persist: false } });
  const failed = await until(() => events.find(e => e.type === 'request.failed'), 'failure');
  assert.ok(failed.type === 'request.failed' && /managed agent/.test(failed.error.message));
  await connection.close();
});
