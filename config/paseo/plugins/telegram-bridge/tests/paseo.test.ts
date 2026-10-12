import test from 'node:test';
import assert from 'node:assert/strict';
import type { PaseoApi } from '@getpaseo/client';
import { agentPort } from '../server/paseo.ts';

test('agent adapter filters every page to the requested workspace and excludes archived agents', async () => {
  const api = { agents: { list: async ({ page }: { page: { cursor?: string } }) => page.cursor ? {
    entries: [{ agent: { id: 'mine', workspaceId: 'ws', title: 'Mine', status: 'idle' } }], pageInfo: { hasMore: false },
  } : {
    entries: [{ agent: { id: 'private', workspaceId: 'other', title: 'Private' } }, { agent: { id: 'old', workspaceId: 'ws', archivedAt: 'yesterday' } }],
    pageInfo: { hasMore: true, nextCursor: 'next' },
  } } } as unknown as PaseoApi;
  assert.deepEqual(await agentPort(api, '/tmp/unused', new AbortController().signal).agents('ws'), [{ id: 'mine', title: 'Mine', status: 'idle' }]);
});

test('new agents receive TREK MCP in their chat workspace without embedding credentials', async () => {
  const calls: unknown[] = [];
  const api = { workspaces: { ref: (id: string) => ({ agents: { create: async (options: unknown) => {
    calls.push({ id, options }); return { id: 'new-agent' };
  } } }) } } as unknown as PaseoApi;
  assert.equal(await agentPort(api, '/tmp/unused', new AbortController().signal).create('chat-workspace', 'codex/gpt-6.1-sol'), 'new-agent');
  assert.deepEqual(calls, [{ id: 'chat-workspace', options: { config: { provider: 'codex/gpt-6.1-sol', mcpServers: { trek: { type: 'http', url: 'https://trek.chunyu.sh/mcp' } } } } }]);
});
