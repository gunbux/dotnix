import { usePaseo } from '@getpaseo/plugin/client';
import { useQuery } from '@tanstack/react-query';
import { allPages, type Thread } from './catalog';

export function useCatalog(hostId: string) {
  const paseo = usePaseo();
  return useQuery({
    queryKey: ['thread-groups', hostId, 'catalog'],
    refetchInterval: 10000,
    queryFn: async () => {
      const [agents, workspaces] = await Promise.all([
        allPages(async cursor => {
          const result = await paseo.agents.list({ filter: { includeArchived: true }, page: { limit: 100, cursor } });
          return { ...result, entries: result.entries.map(entry => entry.agent) };
        }),
        allPages(cursor => paseo.workspaces.list({ page: { limit: 100, cursor } })),
      ]);
      const names = new Map(workspaces.map(w => [w.id, `${w.projectDisplayName} / ${w.title || w.name}`]));
      const threads: Thread[] = agents.map(agent => ({
        id: agent.id,
        title: agent.title || 'Untitled thread',
        workspaceId: agent.workspaceId || '',
        workspaceName: names.get(agent.workspaceId || '') || agent.cwd,
        status: agent.status,
        archived: Boolean(agent.archivedAt),
      }));
      return { threads, workspaces: [...names.entries()] };
    },
  });
}
