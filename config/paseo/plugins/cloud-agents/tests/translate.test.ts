import assert from 'node:assert/strict';
import { test } from 'node:test';
import { sseParser, type MaEvent } from '../server/claude-api.ts';
import { toBlocks } from '../server/provider.ts';
import { createTranslateState, translate } from '../server/translate.ts';

const ids = () => { let n = 0; return () => `turn-${++n}`; };
const at = '2026-10-06T00:00:00Z';

test('a live run opens one turn, streams messages and tool calls, and completes on end_turn', () => {
  const state = createTranslateState('s', ids());
  const all = [
    { id: 'e1', type: 'session.status_running', processed_at: at },
    { id: 'e2', type: 'agent.tool_use', name: 'bash', input: { command: 'ls' }, evaluated_permission: 'allow', processed_at: at },
    { id: 'e3', type: 'agent.tool_result', tool_use_id: 'e2', content: [{ type: 'text', text: 'README.md' }], processed_at: at },
    { id: 'e4', type: 'agent.message', content: [{ type: 'text', text: 'Done.' }], processed_at: at },
    { id: 'e5', type: 'session.status_idle', stop_reason: { type: 'end_turn' }, processed_at: at },
  ].flatMap(e => translate(e as MaEvent, state, true));
  assert.deepEqual(all.filter(e => e.type === 'session.turn').map(e => e.type === 'session.turn' && e.state), ['started', 'completed']);
  const tool = all.filter(e => e.type === 'timeline.item' && e.item.type === 'tool_call').at(-1);
  assert.ok(tool?.type === 'timeline.item' && tool.item.type === 'tool_call');
  assert.equal(tool.item.status, 'completed');
  assert.deepEqual(tool.item.detail, { type: 'shell', command: 'ls', output: 'README.md' });
  assert.ok(all.some(e => e.type === 'timeline.item' && e.item.type === 'assistant_message' && e.item.text === 'Done.'));
  assert.equal(state.activeTurnId, null);
});

test('ask permissions become Paseo permission requests and stay open across requires_action', () => {
  const state = createTranslateState('s', ids());
  const ask = translate({ id: 't1', type: 'agent.tool_use', name: 'write', input: { file_path: '/a', content: 'x' }, evaluated_permission: 'ask' }, state, true);
  const request = ask.find(e => e.type === 'session.permission');
  assert.ok(request?.type === 'session.permission');
  assert.equal(request.request.id, 't1');
  assert.deepEqual(request.request.detail, { type: 'write', filePath: '/a', content: 'x' });
  const idle = translate({ id: 'i', type: 'session.status_idle', stop_reason: { type: 'requires_action', event_ids: ['t1'] } }, state, true);
  assert.deepEqual(idle, []);
  assert.ok(state.activeTurnId);
  const denied = translate({ id: 'c', type: 'user.tool_confirmation', tool_use_id: 't1', result: 'deny' }, state, true);
  assert.deepEqual(denied.map(e => e.type), ['session.permission_resolved', 'timeline.item']);
});

test('history replay renders rows without opening turns or permission prompts', () => {
  const state = createTranslateState('s', ids());
  const out = [
    { id: 'u', type: 'user.message', content: [{ type: 'text', text: 'hi' }] },
    { id: 't', type: 'agent.tool_use', name: 'read', input: { file_path: '/x' }, evaluated_permission: 'ask' },
    { id: 'm', type: 'agent.message', content: [{ type: 'text', text: 'hello' }] },
    { id: 'i', type: 'session.status_idle', stop_reason: { type: 'end_turn' } },
  ].flatMap(e => translate(e as MaEvent, state, false));
  assert.deepEqual(out.map(e => e.type === 'timeline.item' ? e.item.type : e.type), ['user_message', 'tool_call', 'assistant_message']);
});

test('local prompt echoes are suppressed once; messages from other clients still render', () => {
  const state = createTranslateState('s', ids());
  state.pendingEchoes.push('hi');
  assert.deepEqual(translate({ id: 'u1', type: 'user.message', content: [{ type: 'text', text: 'hi' }] }, state, true), []);
  assert.equal(translate({ id: 'u2', type: 'user.message', content: [{ type: 'text', text: 'hi' }] }, state, true).length, 1);
});

test('interrupts cancel and refusals fail the active turn', () => {
  const state = createTranslateState('s', ids());
  translate({ id: 'r', type: 'session.status_running' }, state, true);
  state.interrupted = true;
  const cancel = translate({ id: 'i', type: 'session.status_idle', stop_reason: { type: 'end_turn' } }, state, true);
  assert.ok(cancel.some(e => e.type === 'session.turn' && e.state === 'canceled'));
  translate({ id: 'r2', type: 'session.status_running' }, state, true);
  const refusal = translate({ id: 'i2', type: 'session.status_idle', stop_reason: { type: 'refusal' }, stop_details: { type: 'refusal', explanation: 'nope', category: null } }, state, true);
  const turn = refusal.find(e => e.type === 'session.turn');
  assert.ok(turn?.type === 'session.turn' && turn.state === 'failed' && turn.error?.message === 'Refused: nope');
});

test('SSE parser handles split frames, CRLF, comments and multi-line data', () => {
  const seen: string[] = [];
  const feed = sseParser(e => seen.push(e.id));
  feed(': keep-alive\r\n\r\nevent: message\r\ndata: {"id":"a",');
  feed('"type":"agent.message"}\r\n\r\ndata: {"id":"b",\ndata: "type":"x"}\n\ndata: not json\n\n');
  assert.deepEqual(seen, ['a', 'b']);
});

test('prompt content keeps text and images and labels attachments', () => {
  const blocks = toBlocks([
    { type: 'text', text: 'Fix it' },
    { type: 'image', data: 'AAAA', mimeType: 'image/png' },
    { type: 'github_issue', mimeType: 'application/github-issue', number: 4, title: 'Bug', url: 'https://x/4' },
    { type: 'uploaded_file', id: 'f', fileName: 'a.log', mimeType: 'text/plain', size: 1, path: '/tmp/a.log' },
  ]);
  assert.equal(blocks.length, 4);
  assert.deepEqual(blocks[1], { type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'AAAA' } });
  assert.match(String(blocks[2].text), /Issue #4: Bug/);
  assert.match(String(blocks[3].text), /not uploaded/);
});
