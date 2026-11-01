import type { PluginHookContext, PluginServerContext } from '@getpaseo/plugin/server';
import { autoLabel } from './shared/settings';
import { labelUnlabelled } from './shared/rpc';
import type { Workspace } from './shared/topics';
import { classify } from './server/claude';
import { assignLabel, listLabels } from './server/daemon';
import { createLabeler, message } from './server/labeler';

type Paseo = PluginHookContext['paseo'];

async function listWorkspaces(paseo: Paseo): Promise<Workspace[]> {
  const workspaces: Workspace[] = [];
  let cursor: string | undefined;
  do {
    const page = await paseo.workspaces.list({ page: { limit: 200, cursor } });
    workspaces.push(...page.entries.map(w => ({ id: w.id, title: w.title ?? w.name ?? null, cwd: w.workspaceDirectory,
      labels: w.labels ?? [] })));
    cursor = page.pageInfo.hasMore ? page.pageInfo.nextCursor ?? undefined : undefined;
  } while (cursor);
  return workspaces;
}

/** The first prompt of the workspace's oldest thread. */
async function firstMessage(paseo: Paseo, workspaceId: string): Promise<string | null> {
  const { entries } = await paseo.agents.list({ page: { limit: 200 } });
  const oldest = entries.map(e => e.agent).filter(a => a.workspaceId === workspaceId)
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt))[0];
  if (!oldest) return null;
  try {
    const page = await paseo.agents.ref(oldest.id).timeline.refetch({ direction: 'after', limit: 10 });
    for (const { item } of page.entries) if (item.type === 'user_message' && item.text.trim()) return item.text;
  } catch { /* Fall back to the title when history is unavailable. */ }
  return null;
}

export default function contribute(server: PluginServerContext) {
  const settings = server.registerSettings(autoLabel);
  // There is no daemon session at startup; hooks and RPCs supply it.
  let paseo: Paseo | null = null;
  const session = () => {
    if (!paseo) throw new Error('No daemon session yet.');
    return paseo;
  };
  const log = (text: string) => console.log(`[auto-label] ${text}`);
  const labeler = createLabeler({
    settings: async () => {
      const state = await settings.read();
      if (state.status === 'ready') return state.values;
      log(`Settings are invalid: ${state.error}`);
      return null;
    },
    workspaces: () => listWorkspaces(session()),
    catalog: listLabels,
    firstMessage: id => firstMessage(session(), id),
    classify,
    assign: assignLabel,
    log,
  });

  let backfilled = false;
  const attach = (context: { paseo: Paseo }) => {
    paseo = context.paseo;
    if (backfilled) return;
    backfilled = true;
    labeler.backfill().then(count => count && log(`Queued ${count} unlabelled workspaces.`), error => {
      backfilled = false;
      log(`Backfill failed: ${message(error)}`);
    });
  };
  const label = (workspaceId: string | null) => {
    if (!workspaceId) return;
    labeler.label(workspaceId).catch(error => log(`Could not label ${workspaceId}: ${message(error)}`));
  };

  server.on('workspace.created', (_event, context) => attach(context));
  // Label as soon as a workspace has a prompt. One with no title or history yet is
  // retried when the turn ends.
  server.on('agent.turn_started', (event, context) => {
    attach(context);
    label(event.agent.workspaceId);
  });
  server.on('agent.turn_ended', (event, context) => {
    attach(context);
    label(event.agent.workspaceId);
  });

  server.handle(labelUnlabelled, async (_input, context) => {
    paseo = context.paseo;
    backfilled = true;
    return { queued: await labeler.backfill() };
  });
  return () => {};
}
