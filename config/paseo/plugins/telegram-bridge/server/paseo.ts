import { mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import type { PaseoApi } from '@getpaseo/client';
import type { AgentPort } from './bridge.ts';
import { localConnection, requestLocal } from './local.ts';

export function agentPort(paseo: PaseoApi, home: string, signal: AbortSignal): AgentPort {
  return {
    async agents(workspace) {
      const agents: Awaited<ReturnType<AgentPort['agents']>> = [];
      let cursor: string | undefined;
      do {
        const page = await paseo.agents.list({ page: { limit: 200, cursor } });
        agents.push(...page.entries.filter(e => !e.agent.archivedAt && e.agent.workspaceId === workspace).map(({ agent }) => ({ id: agent.id, title: agent.title ?? agent.id, status: agent.status })));
        cursor = page.pageInfo.hasMore ? page.pageInfo.nextCursor ?? undefined : undefined;
      } while (cursor);
      return agents;
    },
    async ensureWorkspace(key, title, existing) {
      if (!/^[A-Za-z0-9_-]+\/-?\d+$/.test(key)) throw new Error('Invalid Telegram chat identity.');
      const directory = join(home, 'telegram-workspaces', ...key.split('/'));
      if (existing) {
        const snapshot = await paseo.workspaces.ref(existing).refresh();
        if (snapshot?.workspaceDirectory === directory && !snapshot.archivingAt) return existing;
      }
      await mkdir(directory, { recursive: true, mode: 0o700 });
      // Open is directory-idempotent, including recovery after a lost state write.
      const workspace = await paseo.workspaces.open(directory);
      await workspace.setTitle(`Telegram: ${title}`);
      return workspace.id;
    },
    async create(workspace, provider) {
      return (await paseo.workspaces.ref(workspace).agents.create({ config: { provider, mcpServers: { trek: { type: 'http', url: 'https://trek.chunyu.sh/mcp' } } } })).id;
    },
    async send(agent, text, key) { await paseo.agents.ref(agent).send(text, { messageId: key }); },
    async stop(agentId) {
      await requestLocal(await localConnection(home), { type: 'cancel_agent_request', agentId }, 'cancel_agent_response', signal);
    },
    async permissions(agentId) {
      const agent = paseo.agents.ref(agentId);
      const refreshed = await agent.refresh();
      if (!refreshed) throw new Error('Agent no longer exists.');
      return agent.pendingPermissions ?? [];
    },
    async respond(agentId, requestId, response) { await paseo.agents.ref(agentId).respondToPermission({ requestId, response }); },
  };
}
