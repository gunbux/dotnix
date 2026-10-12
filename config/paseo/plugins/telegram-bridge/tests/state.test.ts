import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, stat, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { emptyChat, emptyState, readState, writeState } from '../server/state.ts';

test('state survives restart with private file permissions', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'telegram-state-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'data', 'state.json');
  const state = emptyState('42', 'bot');
  state.offset = 50;
  state.chats['42'] = { ...emptyChat('Me'), selectedAgent: 'agent' };
  state.outbox.push({ chatId: '42', text: 'Saved reply' });
  await writeState(path, state);
  assert.deepEqual(await readState(path, '42', 'bot'), state);
  assert.equal((await stat(path)).mode & 0o777, 0o600);
  assert.equal((await stat(join(directory, 'data'))).mode & 0o777, 0o700);
  assert.equal((await readState(path, '43', 'bot')).outbox.length, 0);
  assert.deepEqual((await readState(path, '42', 'other-bot')).chats, {});
});

test('corrupt state fails closed instead of replaying old updates', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'telegram-state-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'state.json');
  await writeFile(path, '{"offset":"bad"}');
  await assert.rejects(readState(path, '42', 'bot'), /Invalid/);
  assert.equal(await readFile(path, 'utf8'), '{"offset":"bad"}');
});


test('v1 migration preserves offset and private deliveries but drops global agent access', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'telegram-migrate-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const file = join(directory, 'state.json');
  await writeFile(file, JSON.stringify({ version: 1, owner: '42', botId: 'bot', offset: 50, selectedAgent: 'unrelated', watchedAgents: ['unrelated'], approvals: {}, outbox: [{ text: 'Old reply' }] }));
  const state = await readState(file, '42', 'bot');
  assert.equal(state.version, 2);
  assert.equal(state.offset, 50);
  assert.deepEqual(state.chats, {});
  assert.deepEqual(state.outbox, [{ chatId: '42', text: 'Old reply' }]);
});
