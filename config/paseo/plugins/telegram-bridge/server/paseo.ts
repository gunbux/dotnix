import type { PaseoApi } from '@getpaseo/client';
import type { AgentPort } from './bridge.ts';
import { localConnection, requestLocal } from './local.ts';

export function agentPort(paseo: PaseoApi, home: string, signal: AbortSignal): AgentPort {
  return {
    async agents() {
      const agents: Awaited<ReturnType<AgentPort['agents']>> = [];
      let cursor: string | undefined;
      do {
        const page = await paseo.agents.list({ page: { limit: 200, cursor } });
        agents.push(...page.entries.filter(e => !e.agent.archivedAt).map(({ agent }) => ({ id: agent.id, title: agent.title ?? agent.id, status: agent.status })));
        cursor = page.pageInfo.hasMore ? page.pageInfo.nextCursor ?? undefined : undefined;
      } while (cursor);
      return agents;
    },
    async workspaces() {
      const workspaces: Awaited<ReturnType<AgentPort['workspaces']>> = [];
      let cursor: string | undefined;
      do {
        const page = await paseo.workspaces.list({ page: { limit: 200, cursor } });
        workspaces.push(...page.entries.map(w => ({ id: w.id, title: w.title ?? w.name ?? w.id })));
        cursor = page.pageInfo.hasMore ? page.pageInfo.nextCursor ?? undefined : undefined;
      } while (cursor);
      return workspaces;
    },
    async create(workspace, provider) {
      return (await paseo.workspaces.ref(workspace).agents.create({ config: { provider } })).id;
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
