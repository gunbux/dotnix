import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createArchiver, stale, type Workspace } from '../server/archiver.ts';
import type { Settings } from '../shared/settings.ts';

const NOW = Date.parse('2026-10-09T12:00:00Z');
const daysAgo = (days: number) => new Date(NOW - days * 86400000).toISOString();
const settings: Settings = {
  enabled: true, days: 4, keepPinned: true, keepUncommitted: true, quickChatLabel: 'Quick chat', quickChatHours: 12,
};
const workspace = (patch: Partial<Workspace>): Workspace => ({
  id: 'w', title: 'W', status: 'done', labels: [], pinnedAt: null, archivingAt: null, activityAt: daysAgo(5),
  statusEnteredAt: null, managedWorktree: false, isDirty: null, ...patch,
});

test('selects workspaces idle past the threshold, most idle first', () => {
  const result = stale([
    workspace({ id: 'fresh', activityAt: daysAgo(3.9) }),
    workspace({ id: 'old', activityAt: daysAgo(5) }),
    workspace({ id: 'older', activityAt: daysAgo(10) }),
  ], settings, NOW);
  assert.deepEqual(result.map(c => c.id), ['older', 'old']);
});

test('keeps running, archiving, pinned, and unknown-activity workspaces', () => {
  const result = stale([
    workspace({ id: 'running', status: 'running' }),
    workspace({ id: 'archiving', archivingAt: daysAgo(0) }),
    workspace({ id: 'pinned', pinnedAt: daysAgo(30) }),
    workspace({ id: 'unknown', activityAt: null }),
    workspace({ id: 'fallback', activityAt: null, statusEnteredAt: daysAgo(6) }),
  ], settings, NOW);
  assert.deepEqual(result.map(c => c.id), ['fallback']);
  assert.deepEqual(stale([workspace({ id: 'pinned', pinnedAt: daysAgo(30) })], { ...settings, keepPinned: false }, NOW)
    .map(c => c.id), ['pinned']);
});

test('keeps managed worktrees unless known clean', () => {
  const list = [
    workspace({ id: 'dirty', managedWorktree: true, isDirty: true }),
    workspace({ id: 'unknown', managedWorktree: true, isDirty: null }),
    workspace({ id: 'clean', managedWorktree: true, isDirty: false }),
    workspace({ id: 'local-dirty', managedWorktree: false, isDirty: true }),
  ];
  assert.deepEqual(stale(list, settings, NOW).map(c => c.id).sort(), ['clean', 'local-dirty']);
  assert.equal(stale(list, { ...settings, keepUncommitted: false }, NOW).length, 4);
});

test('archives quick chats after their hour threshold', () => {
  const list = [
    workspace({ id: 'chat-old', labels: ['Quick chat'], activityAt: daysAgo(13 / 24) }),
    workspace({ id: 'chat-new', labels: ['Quick chat'], activityAt: daysAgo(11 / 24) }),
    workspace({ id: 'chat-pinned', labels: ['Quick chat'], activityAt: daysAgo(1), pinnedAt: daysAgo(1) }),
    workspace({ id: 'other', labels: ['Nix'], activityAt: daysAgo(1) }),
  ];
  assert.deepEqual(stale(list, settings, NOW).map(c => c.id), ['chat-old']);
  assert.deepEqual(stale(list, { ...settings, quickChatHours: 0 }, NOW).map(c => c.id), []);
  assert.deepEqual(stale(list, { ...settings, quickChatLabel: '' }, NOW).map(c => c.id), []);
});

test('sweep archives candidates, records failures, and honours enabled for automatic runs', async () => {
  const archived: string[] = [];
  let current = settings;
  const archiver = createArchiver({
    settings: async () => current,
    workspaces: async () => [workspace({ id: 'a' }), workspace({ id: 'b' })],
    archive: async id => { if (id === 'b') throw new Error('boom'); archived.push(id); },
    now: () => NOW,
    log: () => {},
  });
  const result = await archiver.sweep();
  assert.deepEqual(result.archived.map(c => c.id), ['a']);
  assert.equal(result.failed, 1);
  assert.deepEqual(archiver.lastSweep(), { at: new Date(NOW).toISOString(), archived: 1, failed: 1 });

  current = { ...settings, enabled: false };
  assert.equal((await archiver.sweep()).archived.length, 0);
  assert.equal((await archiver.sweep(true)).archived.length, 1);
});

test('concurrent sweeps share one run', async () => {
  let calls = 0;
  const archiver = createArchiver({
    settings: async () => settings,
    workspaces: async () => [workspace({ id: 'a' })],
    archive: async () => { calls++; },
    now: () => NOW,
    log: () => {},
  });
  await Promise.all([archiver.sweep(), archiver.sweep(true)]);
  assert.equal(calls, 1);
});
