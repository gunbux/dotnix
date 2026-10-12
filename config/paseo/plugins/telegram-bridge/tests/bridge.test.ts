import test from 'node:test';
import assert from 'node:assert/strict';
import { Bridge, type AgentPort } from '../server/bridge.ts';
import { emptyState } from '../server/state.ts';

const permission = { id: 'request-1', provider: 'codex', kind: 'tool' as const, name: 'shell', description: 'Run git status', input: { command: 'git status' } };
function fixture() {
  const calls: unknown[] = [];
  const state = emptyState('42', 'bot-1');
  let pending = [permission];
  const port: AgentPort = {
    agents: async () => [{ id: 'agent-one', title: 'One', status: 'idle' }, { id: 'agent-two', title: 'Two', status: 'running' }],
    workspaces: async () => [{ id: 'workspace-one', title: 'Project' }],
    create: async (workspace, provider) => { calls.push(['create', workspace, provider]); return 'agent-new'; },
    send: async (id, text, key) => { calls.push(['send', id, text, key]); },
    stop: async id => { calls.push(['stop', id]); },
    permissions: async () => pending,
    respond: async (id, requestId, response) => { calls.push(['respond', id, requestId, response]); pending = []; },
  };
  const bridge = new Bridge({ state, port, save: async () => {}, now: () => 1000000, defaultProvider: 'codex/gpt-5.4' });
  const message = (text: string, update_id = 1, from = 42, type = 'private') => ({ update_id, message: { message_id: update_id, date: 1000, from: { id: from }, chat: { id: 42, type }, text } });
  const click = (data: string, update_id = 10, from = 42) => ({ update_id, callback_query: { id: `cb-${update_id}`, from: { id: from }, data, message: { message_id: 1, chat: { id: 42, type: 'private' } } } });
  return { bridge, state, calls, message, click, clearPending: () => { pending = []; } };
}

test('unauthorized users and groups cannot select agents, send prompts, or receive data', async () => {
  const f = fixture();
  await f.bridge.update(f.message('/use agent-one', 1, 99));
  await f.bridge.update(f.message('/agents', 2, 42, 'group'));
  assert.equal(f.state.selectedAgent, null);
  assert.deepEqual(f.calls, []);
  assert.equal(f.state.outbox.length, 0);
});

test('selection routes prompts and duplicate updates do not run twice', async () => {
  const f = fixture();
  await f.bridge.update(f.message('/use agent-one'));
  await f.bridge.update(f.message('Please inspect this', 2));
  await f.bridge.update(f.message('Please inspect this', 2));
  assert.deepEqual(f.calls, [['send', 'agent-one', 'Please inspect this', 'telegram:bot-1:2']]);
  assert.equal(f.state.offset, 3);
});

test('ambiguous IDs do not select an arbitrary agent', async () => {
  const f = fixture();
  await f.bridge.update(f.message('/use agent-'));
  assert.equal(f.state.selectedAgent, null);
  assert.match(f.state.outbox.at(-1)!.text, /ambiguous/i);
});

test('new agents are bound before sending their initial prompt', async () => {
  const f = fixture();
  await f.bridge.update(f.message('/new workspace-one Review the code'));
  assert.equal(f.state.selectedAgent, 'agent-new');
  assert.ok(f.state.watchedAgents.includes('agent-new'));
  assert.deepEqual(f.calls, [['create', 'workspace-one', 'codex/gpt-5.4'], ['send', 'agent-new', 'Review the code', 'telegram:bot-1:1']]);
});

test('only the owner can answer a bound permission and repeat clicks cannot approve again', async () => {
  const f = fixture();
  await f.bridge.update(f.message('/use agent-one'));
  const button = f.state.outbox.find(x => x.buttons)?.buttons?.[0]?.[0];
  assert.ok(button);
  await f.bridge.update(f.click(button.callback_data, 2, 99));
  assert.deepEqual(f.calls, []);
  await f.bridge.update(f.click(button.callback_data, 3));
  await f.bridge.update(f.click(button.callback_data, 4));
  assert.deepEqual(f.calls, [['respond', 'agent-one', 'request-1', { behavior: 'allow' }]]);
});

test('requests resolved in Paseo cannot be approved using stale buttons', async () => {
  const f = fixture();
  await f.bridge.update(f.message('/use agent-one'));
  const button = f.state.outbox.find(x => x.buttons)!.buttons![0][0];
  f.clearPending();
  await f.bridge.update(f.click(button.callback_data));
  assert.deepEqual(f.calls, []);
  assert.match(f.state.outbox.at(-1)!.text, /no longer pending/i);
});

test('replies stay associated with watched agents when selection changes', async () => {
  const f = fixture();
  await f.bridge.update(f.message('/use agent-one'));
  await f.bridge.update(f.message('/use agent-two', 2));
  f.state.outbox.length = 0;
  await f.bridge.finished('agent-one', 'One', [{ type: 'user_message', text: 'old' }, { type: 'assistant_message', text: 'old reply' }, { type: 'user_message', text: 'new' }, { type: 'reasoning', text: 'private thought' }, { type: 'assistant_message', text: 'New reply' }], { kind: 'completed' });
  await f.bridge.finished('not-watched', 'Other', [{ type: 'assistant_message', text: 'Unrelated' }], { kind: 'completed' });
  assert.equal(f.state.outbox.length, 1);
  assert.match(f.state.outbox[0].text, /One.*agent-one[\s\S]*New reply/);
  assert.doesNotMatch(f.state.outbox[0].text, /old reply|private thought|Unrelated/);
});

test('question requests are not converted into generic allow buttons', async () => {
  const f = fixture();
  f.state.watchedAgents.push('agent-one');
  await f.bridge.permission('agent-one', { ...permission, id: 'question', kind: 'question' });
  assert.equal(f.state.outbox.some(x => x.buttons), false);
  assert.match(f.state.outbox.at(-1)!.text, /Paseo/);
});

test('old messages are discarded instead of executing commands after downtime', async () => {
  const f = fixture();
  f.state.selectedAgent = 'agent-one';
  const old = f.message('/stop');
  old.message.date = 1;
  await f.bridge.update(old);
  assert.deepEqual(f.calls, []);
});

test('a failed checkpoint prevents prompt execution', async () => {
  const f = fixture();
  f.state.selectedAgent = 'agent-one';
  const bridge = new Bridge({ state: f.state, port: { send: async () => { throw new Error('must not run'); } } as unknown as AgentPort, save: async () => { throw new Error('disk full'); }, now: () => 1000000, defaultProvider: 'codex/gpt-5.4' });
  await assert.rejects(bridge.update(f.message('hello')), /disk full/);
});

test('expired approval buttons never answer permissions', async () => {
  const f = fixture();
  await f.bridge.update(f.message('/use agent-one'));
  const button = f.state.outbox.find(x => x.buttons)!.buttons![0][0];
  Object.values(f.state.approvals)[0].expires = 999999;
  await f.bridge.update(f.click(button.callback_data));
  assert.deepEqual(f.calls, []);
  assert.match(f.state.outbox.at(-1)!.text, /expired/i);
});

test('provider-specific denial preserves the selected action ID', async () => {
  const f = fixture();
  f.state.watchedAgents.push('agent-one');
  await f.bridge.permission('agent-one', { ...permission, actions: [{ id: 'reject-plan', label: 'Reject plan', behavior: 'deny' }] });
  const button = f.state.outbox.find(x => x.buttons)!.buttons![0][0];
  await f.bridge.update(f.click(button.callback_data));
  assert.deepEqual(f.calls, [['respond', 'agent-one', 'request-1', { behavior: 'deny', selectedActionId: 'reject-plan' }]]);
});

test('stopping targets the selected agent and unwatch revokes its pending buttons', async () => {
  const f = fixture();
  await f.bridge.update(f.message('/use agent-one'));
  const button = f.state.outbox.find(x => x.buttons)!.buttons![0][0];
  await f.bridge.update(f.message('/stop', 2));
  await f.bridge.update(f.message('/unwatch', 3));
  await f.bridge.update(f.click(button.callback_data));
  assert.deepEqual(f.calls, [['stop', 'agent-one']]);
  assert.equal(f.state.selectedAgent, null);
  assert.deepEqual(f.state.watchedAgents, []);
});
