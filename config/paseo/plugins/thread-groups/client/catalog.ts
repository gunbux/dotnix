import type { Group } from '../shared/groups';

type Page<T> = { entries: T[]; pageInfo: { hasMore: boolean; nextCursor: string | null } };
export async function allPages<T extends { id: string }>(fetch: (cursor?: string) => Promise<Page<T>>): Promise<T[]> {
  const entries = new Map<string, T>();
  const seen = new Set<string>();
  let cursor: string | undefined;
  do {
    const page = await fetch(cursor);
    for (const entry of page.entries) entries.set(entry.id, entry);
    if (!page.pageInfo.hasMore) break;
    const next = page.pageInfo.nextCursor;
    if (!next || seen.has(next)) throw new Error('The host returned an invalid pagination cursor. Refresh to retry.');
    seen.add(next);
    cursor = next;
  } while (true);
  return [...entries.values()];
}
export interface Thread {
  id: string; title: string; workspaceId: string; workspaceName: string;
  status?: string; archived?: boolean;
}
export function visibleThreads(threads: Thread[], groups: Group[], selected: string, search: string, workspace: string): Thread[] {
  const members = new Set(selected === 'ungrouped'
    ? groups.flatMap(g => g.agentIds) : groups.find(g => g.id === selected)?.agentIds ?? []);
  const needle = search.trim().toLowerCase();
  return threads.filter(t => (!workspace || t.workspaceId === workspace)
    && (!needle || `${t.title} ${t.workspaceName}`.toLowerCase().includes(needle))
    && (selected === 'all' || (selected === 'ungrouped' ? !members.has(t.id) : members.has(t.id))));
}
