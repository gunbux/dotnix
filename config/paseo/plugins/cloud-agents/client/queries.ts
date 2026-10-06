import { usePaseo, useRpc } from '@getpaseo/plugin/client';
import { useQuery } from '@tanstack/react-query';
import { claudeSessions, claudeStatus, codexTasks } from '../shared/rpc.ts';

export function useClaudeStatus() {
  const status = useRpc(claudeStatus);
  return useQuery({ queryKey: ['cloud-agents', 'claude-status'], queryFn: () => status({}) });
}

export function useClaudeSessions(enabled: boolean, includeArchived: boolean) {
  const list = useRpc(claudeSessions);
  return useQuery({
    queryKey: ['cloud-agents', 'claude-sessions', includeArchived], enabled, refetchInterval: 15_000,
    queryFn: () => list({ includeArchived }),
  });
}

export function useCodexTasks(environment: string) {
  const list = useRpc(codexTasks);
  return useQuery({
    queryKey: ['cloud-agents', 'codex-tasks', environment], refetchInterval: 20_000,
    queryFn: () => list(environment ? { environment } : {}),
  });
}

export type WorkspaceOption = { id: string; label: string; directory: string };
export function useWorkspaces(hostId: string) {
  const paseo = usePaseo();
  return useQuery({
    queryKey: ['cloud-agents', hostId, 'workspaces'],
    queryFn: async (): Promise<WorkspaceOption[]> => {
      const result = await paseo.workspaces.list({ page: { limit: 100 } });
      return result.entries.map(w => ({ id: w.id, label: `${w.projectDisplayName} / ${w.title || w.name}`, directory: w.workspaceDirectory }));
    },
  });
}
