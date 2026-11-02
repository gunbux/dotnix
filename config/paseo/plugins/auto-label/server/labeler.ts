import type { Settings } from '../shared/settings.ts';
import { buildPrompt, chooseLabel, colorFor, vocabulary, type Label, type Workspace } from '../shared/topics.ts';

export type LabelerDeps = {
  settings(): Promise<Settings | null>;
  workspaces(): Promise<Workspace[]>;
  catalog(): Promise<Label[]>;
  firstMessage(workspaceId: string): Promise<string | null>;
  classify(prompt: string, model: Settings['model']): Promise<string>;
  assign(workspaceId: string, label: Label): Promise<void>;
  log(message: string): void;
};

export function createLabeler(deps: LabelerDeps) {
  // One classification at a time keeps CLI processes and label writes serialized.
  let queue: Promise<unknown> = Promise.resolve();
  const pending = new Set<string>();
  const find = async (id: string) => (await deps.workspaces()).find(w => w.id === id);

  async function run(workspaceId: string): Promise<string | null> {
    const settings = await deps.settings();
    if (!settings?.enabled) return null;
    const workspace = await find(workspaceId);
    // Any existing label, including one set by hand, means the workspace is sorted.
    if (!workspace || workspace.labels.length) return null;
    const first = await deps.firstMessage(workspaceId);
    // Empty workspaces are retried when their first turn starts or ends.
    if (!first && !workspace.title) return null;
    const catalog = await deps.catalog();
    const topics = vocabulary(settings.topics, catalog);
    const answer = await deps.classify(buildPrompt(workspace, first, topics, settings.allowNew), settings.model);
    const name = chooseLabel(answer, topics, settings.allowNew);
    // A label applied by hand while classifying wins.
    const current = await find(workspaceId);
    if (!current || current.labels.length) return null;
    await deps.assign(workspaceId, { name, color: colorFor(name, catalog) });
    deps.log(`Labelled ${workspaceId} (${workspace.title ?? 'untitled'}) as ${name}.`);
    return name;
  }

  function label(workspaceId: string): Promise<string | null> {
    if (pending.has(workspaceId)) return Promise.resolve(null);
    pending.add(workspaceId);
    const task = queue.then(() => run(workspaceId));
    queue = task.catch(() => {}).finally(() => pending.delete(workspaceId));
    return task;
  }

  async function backfill(): Promise<number> {
    const settings = await deps.settings();
    if (!settings?.enabled) return 0;
    const unlabelled = (await deps.workspaces()).filter(w => !w.labels.length);
    for (const workspace of unlabelled) {
      label(workspace.id).catch(error => deps.log(`Could not label ${workspace.id}: ${message(error)}`));
    }
    return unlabelled.length;
  }

  return { label, backfill };
}

export const message = (error: unknown) => error instanceof Error ? error.message : String(error);
