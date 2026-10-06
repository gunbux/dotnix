import type { PluginServerContext } from '@getpaseo/plugin/server';
import { configSchema, cloudConfig, type Config } from './shared/settings.ts';
import {
  claudeCatalog, claudeSessionAction, claudeSessions, claudeStatus, codexApply, codexDiff, codexSubmit, codexTasks,
} from './shared/rpc.ts';
import { ManagedAgentsApi, resolveApiKey } from './server/claude-api.ts';
import { codexCloud, processRunner } from './server/codex.ts';
import { createClaudeCloudProvider } from './server/provider.ts';

export default function contribute(server: PluginServerContext) {
  const settings = server.registerSettings(cloudConfig);
  async function config(): Promise<Config> {
    const state = await settings.read();
    if (state.status === 'ready') return state.values;
    // Fall back to defaults so a broken settings document never exposes partial values.
    return configSchema.parse({});
  }
  async function api(): Promise<ManagedAgentsApi> {
    const { claude } = await config();
    const key = await resolveApiKey(claude.apiKeyFile);
    if (key.source === 'none') throw new Error(`Claude cloud is not configured: ${key.detail}`);
    return new ManagedAgentsApi(claude.baseUrl, key.key);
  }
  const codex = async () => codexCloud(processRunner((await config()).codex.binary));

  server.registerProvider(createClaudeCloudProvider({
    api,
    async defaults() {
      const { claude } = await config();
      return { agentId: claude.defaultAgentId, environmentId: claude.defaultEnvironmentId };
    },
  }));

  server.handle(claudeStatus, async () => {
    const key = await resolveApiKey((await config()).claude.apiKeyFile);
    return key.source === 'none'
      ? { configured: false, source: key.source, detail: key.detail }
      : { configured: true, source: key.source, detail: key.source === 'env' ? 'Using ANTHROPIC_API_KEY' : 'Using the configured key file' };
  });
  server.handle(claudeCatalog, async () => {
    const client = await api();
    const [agents, environments] = await Promise.all([client.listAgents(), client.listEnvironments()]);
    return {
      agents: agents.filter(a => !a.archived_at).map(a => ({ id: a.id, name: a.name, model: a.model.id })),
      environments: environments.filter(e => !e.archived_at).map(e => ({ id: e.id, name: e.name })),
    };
  });
  server.handle(claudeSessions, async ({ includeArchived }) => {
    const sessions = await (await api()).listSessions(includeArchived, 100);
    return { sessions: sessions.map(s => {
      const cost = Number(s.usage?.list_cost?.amount);
      return {
        id: s.id, title: s.title, status: s.status, agentName: s.agent.name, model: s.agent.model.id,
        environmentId: s.environment_id, updatedAt: s.updated_at, archived: Boolean(s.archived_at),
        costUsd: Number.isFinite(cost) ? cost : null,
      };
    }) };
  });
  server.handle(claudeSessionAction, async ({ sessionId, action }) => {
    const client = await api();
    if (action === 'archive') await client.archiveSession(sessionId);
    else await client.sendEvents(sessionId, [{ type: 'user.interrupt' }]);
    return { ok: true as const };
  });

  server.handle(codexTasks, async input => (await codex()).list(input));
  server.handle(codexDiff, async input => ({ diff: await (await codex()).diff(input) }));
  server.handle(codexApply, async input => (await codex()).apply(input));
  server.handle(codexSubmit, async input => {
    const environment = input.environment || (await config()).codex.defaultEnvironment;
    return { url: await (await codex()).submit({ ...input, environment }) };
  });
  return () => {};
}
