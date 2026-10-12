import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, stat, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { emptyState, readState, writeState } from '../server/state.ts';

test('state survives restart with private file permissions', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'telegram-state-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'data', 'state.json');
  const state = emptyState('42', 'bot');
  state.offset = 50;
  state.selectedAgent = 'agent';
  state.outbox.push({ text: 'Saved reply' });
  await writeState(path, state);
  assert.deepEqual(await readState(path, '42', 'bot'), state);
  assert.equal((await stat(path)).mode & 0o777, 0o600);
  assert.equal((await stat(join(directory, 'data'))).mode & 0o777, 0o700);
  assert.equal((await readState(path, '43', 'bot')).outbox.length, 0);
  assert.equal((await readState(path, '42', 'other-bot')).selectedAgent, null);
});

test('corrupt state fails closed instead of replaying old updates', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'telegram-state-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'state.json');
  await writeFile(path, '{"offset":"bad"}');
  await assert.rejects(readState(path, '42', 'bot'), /Invalid/);
  assert.equal(await readFile(path, 'utf8'), '{"offset":"bad"}');
});
