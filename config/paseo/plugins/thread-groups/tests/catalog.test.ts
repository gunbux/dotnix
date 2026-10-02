import assert from 'node:assert/strict';
import { test } from 'node:test';
import { allPages, visibleThreads } from '../client/catalog.ts';

test('loads every catalog page and deduplicates entries', async () => {
  const calls: (string | undefined)[] = [];
  const entries = await allPages(async cursor => {
    calls.push(cursor);
    return cursor === undefined
      ? { entries: [{ id: 'a' }], pageInfo: { hasMore: true, nextCursor: 'next' } }
      : { entries: [{ id: 'a' }, { id: 'b' }], pageInfo: { hasMore: false, nextCursor: null } };
  });
  assert.deepEqual(entries, [{ id: 'a' }, { id: 'b' }]);
  assert.deepEqual(calls, [undefined, 'next']);
});
test('rejects a repeated pagination cursor rather than silently dropping threads', async () => {
  await assert.rejects(allPages(async () => ({ entries: [], pageInfo: { hasMore: true, nextCursor: 'same' } })), /cursor/);
});
test('ungrouped and workspace search operate across the full catalog', () => {
  const threads = [
    { id: 'a', title: 'Plan', workspaceId: 'w1', workspaceName: 'Login' },
    { id: 'b', title: 'Implement', workspaceId: 'w2', workspaceName: 'Worktree' },
    { id: 'c', title: 'Review', workspaceId: 'w1', workspaceName: 'Login' },
  ];
  const groups = [{ id: 'g', name: 'Auth', agentIds: ['a'] }];
  assert.deepEqual(visibleThreads(threads, groups, 'ungrouped', '', '').map(t => t.id), ['b', 'c']);
  assert.deepEqual(visibleThreads(threads, groups, 'all', 'login', 'w1').map(t => t.id), ['a', 'c']);
});
