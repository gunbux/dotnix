import type { PluginHookContext, PluginServerContext } from '@getpaseo/plugin/server';
import { archiveStale, previewStale } from './shared/rpc';
import { autoArchive } from './shared/settings';
import { createArchiver, message, type Workspace } from './server/archiver';

type Paseo = PluginHookContext['paseo'];

const SWEEP_INTERVAL = 3600000;

async function listWorkspaces(paseo: Paseo): Promise<Workspace[]> {
  const workspaces: Workspace[] = [];
  let cursor: string | undefined;
  do {
    const page = await paseo.workspaces.list({ page: { limit: 200, cursor } });
    workspaces.push(...page.entries.map(w => ({
      id: w.id,
      title: w.title ?? w.name,
      status: w.status,
      labels: w.labels ?? [],
      pinnedAt: w.pinnedAt ?? null,
      archivingAt: w.archivingAt ?? null,
      activityAt: w.activityAt,
      statusEnteredAt: w.statusEnteredAt,
      managedWorktree: w.workspaceKind === 'worktree' || w.gitRuntime?.isPaseoOwnedWorktree === true,
      isDirty: w.gitRuntime?.isDirty ?? null,
    })));
    cursor = page.pageInfo.hasMore ? page.pageInfo.nextCursor ?? undefined : undefined;
  } while (cursor);
  return workspaces;
}

export default function contribute(server: PluginServerContext) {
  const settings = server.registerSettings(autoArchive);
  // There is no daemon session at startup; hooks and RPCs supply one that lasts
  // as long as this subprocess. The client asks for a sweep when it connects.
  let paseo: Paseo | null = null;
  const session = () => {
    if (!paseo) throw new Error('No daemon session yet.');
    return paseo;
  };
  const log = (text: string) => console.log(`[auto-archive] ${text}`);
  const archiver = createArchiver({
    settings: async () => {
      const state = await settings.read();
      if (state.status === 'ready') return state.values;
      log(`Settings are invalid: ${state.error}`);
      return null;
    },
    workspaces: () => listWorkspaces(session()),
    archive: async id => {
      const result = await session().workspaces.archive(id);
      if (result.error) throw new Error(result.error);
    },
    now: Date.now,
    log,
  });
  const sweep = () => {
    if (paseo) archiver.sweep().catch(error => log(`Sweep failed: ${message(error)}`));
  };
  const attach = (context: { paseo: Paseo }) => {
    const first = !paseo;
    paseo = context.paseo;
    if (first) sweep();
  };

  server.on('workspace.created', (_event, context) => attach(context));
  server.on('agent.turn_started', (_event, context) => attach(context));
  server.on('agent.turn_ended', (_event, context) => attach(context));

  server.handle(previewStale, async (_input, context) => {
    attach(context);
    return { candidates: await archiver.preview(), lastSweep: archiver.lastSweep() };
  });
  server.handle(archiveStale, async (_input, context) => {
    paseo = context.paseo;
    return archiver.sweep(true);
  });

  const timer = setInterval(sweep, SWEEP_INTERVAL);
  const unsubscribe = settings.subscribe(sweep);
  return () => {
    clearInterval(timer);
    unsubscribe();
  };
}
