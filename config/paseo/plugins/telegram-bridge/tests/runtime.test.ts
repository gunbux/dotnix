import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { deliverOne, readToken, startRuntime } from '../server/runtime.ts';
import { emptyChat, emptyState, readState, writeState } from '../server/state.ts';
import type { AgentPort } from '../server/bridge.ts';

test('outbox retains failed deliveries and removes successful messages in order', async () => {
  const state = emptyState('42', 'bot');
  state.outbox.push({ chatId: '-100', text: 'first' }, { chatId: '42', text: 'second' });
  const delivered: string[] = [];
  await assert.rejects(deliverOne(state, async () => { throw new Error('offline'); }, async () => {}), /offline/);
  assert.equal(state.outbox.length, 2);
  await deliverOne(state, async (chatId, item) => { assert.equal(chatId, '-100'); delivered.push(item.text); }, async () => {});
  assert.deepEqual(delivered, ['first']);
  assert.deepEqual(state.outbox, [{ chatId: '42', text: 'second' }]);
});

test('bot tokens must come from a private file and failures never expose the token', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'telegram-token-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const file = join(directory, 'token');
  const token = '123456:abcdefghijklmnopqrstuvwxyz';
  await writeFile(file, token + '\n', { mode: 0o600 });
  assert.equal(await readToken(file), token);
  await assert.rejects(readToken('relative-path'), /absolute/i);
  const publicFile = join(directory, 'public-token');
  await writeFile(publicFile, token, { mode: 0o644 });
  await assert.rejects(readToken(publicFile), error => /permissions/i.test(String(error)) && !String(error).includes(token));
});

const port: AgentPort = {
  agents: async () => [{ id: 'agent', title: 'Agent', status: 'idle' }], ensureWorkspace: async () => 'workspace',
  create: async () => 'new', send: async () => {}, stop: async () => {},
  permissions: async () => [], respond: async () => {},
};
async function setup(t: { after(fn: () => Promise<unknown>): void }) {
  const home = await mkdtemp(join(tmpdir(), 'telegram-runtime-'));
  t.after(() => rm(home, { recursive: true, force: true }));
  const tokenFile = join(home, 'token');
  await writeFile(tokenFile, '123456:abcdefghijklmnopqrstuvwxyz', { mode: 0o600 });
  return { home, config: { enabled: true, ownerId: '42', tokenFile, defaultProvider: 'codex/gpt-5.4' } };
}
const response = (result: unknown) => new Response(JSON.stringify({ ok: true, result }));
async function until(check: () => boolean, timeout = 6000) {
  const end = Date.now() + timeout;
  while (!check()) {
    if (Date.now() > end) throw new Error('Timed out waiting for runtime behavior');
    await new Promise(resolve => setTimeout(resolve, 10));
  }
}
function holdUntilAbort(signal: AbortSignal | null | undefined): Promise<Response> {
  return new Promise((_resolve, reject) => {
    if (signal?.aborted) reject(new Error('aborted'));
    else signal?.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
  });
}

test('runtime polls, checkpoints commands, delivers replies, and cancels long polling on shutdown', async t => {
  const { home, config } = await setup(t);
  const sent: string[] = [];
  const prompts: unknown[] = [];
  let polls = 0;
  let pollAborted = false;
  const fetcher: typeof fetch = async (url, init) => {
    const method = String(url).split('/').at(-1);
    const body = JSON.parse(String(init?.body));
    if (method === 'getMe') return response({ id: 123456, username: 'bridge_test' });
    if (method === 'getWebhookInfo') return response({ url: '' });
    if (method === 'sendMessage') { sent.push(body.text); return response({ message_id: sent.length }); }
    if (method === 'getUpdates') {
      if (++polls === 1) return response(['/use agent', 'hello'].map((text, i) => ({ update_id: i + 1, message: { message_id: i + 1, from: { id: 42 }, chat: { id: 42, type: 'private' }, date: Math.floor(Date.now() / 1000), text } })));
      init?.signal?.addEventListener('abort', () => { pollAborted = true; }, { once: true });
      return holdUntilAbort(init?.signal);
    }
    throw new Error(`Unexpected method ${method}`);
  };
  const runtime = await startRuntime(config, { ...port, send: async (...args) => { prompts.push(args); } }, home, new AbortController().signal, () => {}, fetcher);
  t.after(() => runtime.close());
  await until(() => prompts.length === 1);
  runtime.enqueue(bridge => bridge.finished('agent', 'Agent', [{ type: 'user_message', text: 'hello' }, { type: 'assistant_message', text: 'The answer' }], { kind: 'completed' }));
  await until(() => sent.some(text => text.includes('The answer')));
  assert.deepEqual(prompts, [['agent', 'hello', 'telegram:123456:2']]);
  await runtime.close();
  assert.equal(pollAborted, true);
  const state = await readState(join(home, 'plugin-data/telegram-bridge/state.json'), '42', '123456');
  assert.equal(state.offset, 3);
  assert.equal(state.chats['42'].selectedAgent, 'agent');
  assert.equal(state.outbox.length, 0);
});

test('runtime recovers pending permissions after restart and stops on polling conflicts', async t => {
  const { home, config } = await setup(t);
  const state = emptyState('42', '123456');
  state.chats['42'] = { ...emptyChat('Me'), workspaceId: 'workspace', watchedAgents: ['agent'] };
  state.chats['42'].selectedAgent = 'agent';
  await writeState(join(home, 'plugin-data/telegram-bridge/state.json'), state);
  const statuses: string[] = [];
  let polls = 0;
  const runtime = await startRuntime(config, { ...port, permissions: async () => [{ id: 'pending', name: 'shell', provider: 'codex', kind: 'tool' }] }, home, new AbortController().signal, s => statuses.push(s), async url => {
    const method = String(url).split('/').at(-1);
    if (method === 'getMe') return response({ id: 123456, username: 'bridge_test' });
    if (method === 'getWebhookInfo') return response({ url: '' });
    if (method === 'sendMessage') return response({ message_id: 1 });
    polls++;
    return new Response(JSON.stringify({ ok: false, error_code: 409 }), { status: 409 });
  });
  t.after(() => runtime.close());
  await until(() => statuses.some(s => s.includes('another program')));
  await runtime.close();
  assert.equal(polls, 1);
  const saved = await readState(join(home, 'plugin-data/telegram-bridge/state.json'), '42', '123456');
  assert.equal(Object.values(saved.approvals)[0].requestId, 'pending');
});

test('runtime retries rate-limited polling without dropping the saved offset', async t => {
  const { home, config } = await setup(t);
  const offsets: number[] = [];
  const state = emptyState('42', '123456');
  state.offset = 77;
  await writeState(join(home, 'plugin-data/telegram-bridge/state.json'), state);
  const runtime = await startRuntime(config, port, home, new AbortController().signal, () => {}, async (url, init) => {
    const method = String(url).split('/').at(-1);
    if (method === 'getMe') return response({ id: 123456, username: 'bridge_test' });
    if (method === 'getWebhookInfo') return response({ url: '' });
    offsets.push(JSON.parse(String(init?.body)).offset);
    if (offsets.length === 1) return new Response(JSON.stringify({ ok: false, error_code: 429, parameters: { retry_after: 1 } }), { status: 429 });
    return holdUntilAbort(init?.signal);
  });
  t.after(() => runtime.close());
  await until(() => offsets.length === 2);
  assert.deepEqual(offsets, [77, 77]);
});

test('a blocked group cannot stop deliveries to other chats', async () => {
  const state = emptyState('42', 'bot');
  state.chats['-100'] = emptyChat('Gone');
  state.outbox.push({ chatId: '-100', text: 'Group reply' }, { chatId: '42', text: 'Private reply' });
  const { TelegramError } = await import('../server/telegram.ts');
  await deliverOne(state, async () => { throw new TelegramError(403); }, async () => {});
  assert.equal(state.chats['-100'], undefined);
  assert.deepEqual(state.outbox, [{ chatId: '42', text: 'Private reply' }]);
});

test('send-time group migration retargets the outbox without stopping delivery', async () => {
  const state = emptyState('42', 'bot');
  state.chats['-100'] = { ...emptyChat('Trip'), workspaceId: 'workspace' };
  state.outbox.push({ chatId: '-100', text: 'Reply' });
  const { TelegramError } = await import('../server/telegram.ts');
  await deliverOne(state, async () => { throw new TelegramError(400, 0, -100123); }, async () => {});
  assert.equal(state.chats['-100123'].workspaceId, 'workspace');
  assert.equal(state.outbox[0].chatId, '-100123');
});
