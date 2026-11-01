import type { Candidate } from '../shared/rpc.ts';
import { quickChatLabels, type Settings } from '../shared/settings.ts';

export type Workspace = {
  id: string;
  title: string;
  status: string;
  labels: string[];
  pinnedAt: string | null;
  archivingAt: string | null;
  activityAt: string | null;
  statusEnteredAt: string | null;
  // Archiving a managed worktree's last workspace removes the worktree from disk.
  managedWorktree: boolean;
  isDirty: boolean | null;
};

export type ArchiverDeps = {
  settings(): Promise<Settings | null>;
  workspaces(): Promise<Workspace[]>;
  archive(workspaceId: string): Promise<void>;
  now(): number;
  log(message: string): void;
};

const DAY = 86400000;

/** Idle days before a workspace is archived; quick chats use their own, usually shorter, limit. */
export function threshold(workspace: Workspace, settings: Settings): number {
  const quickChat = settings.quickChatHours > 0
    && quickChatLabels(settings.quickChatLabel).some(label => workspace.labels.includes(label));
  return quickChat ? settings.quickChatHours / 24 : settings.days;
}

/** Workspaces idle for longer than the configured threshold, most idle first. */
export function stale(workspaces: Workspace[], settings: Settings, now: number): Candidate[] {
  const candidates: Candidate[] = [];
  for (const w of workspaces) {
    if (w.archivingAt || w.status === 'running') continue;
    if (settings.keepPinned && w.pinnedAt) continue;
    if (settings.keepUncommitted && w.managedWorktree && w.isDirty !== false) continue;
    // A workspace with no recorded activity is left alone rather than guessed at.
    const last = Date.parse(w.activityAt ?? w.statusEnteredAt ?? '');
    if (Number.isNaN(last)) continue;
    const idleDays = (now - last) / DAY;
    if (idleDays >= threshold(w, settings)) candidates.push({ id: w.id, title: w.title, idleDays });
  }
  return candidates.sort((a, b) => b.idleDays - a.idleDays);
}

export function createArchiver(deps: ArchiverDeps) {
  // Concurrent triggers share one sweep so a workspace is never archived twice.
  let running: Promise<{ archived: Candidate[]; failed: number }> | null = null;
  let lastSweep: { at: string; archived: number; failed: number } | null = null;

  async function preview(): Promise<Candidate[]> {
    const settings = await deps.settings();
    return settings ? stale(await deps.workspaces(), settings, deps.now()) : [];
  }

  async function run(manual: boolean) {
    const settings = await deps.settings();
    // A manual run archives even when the automatic sweep is switched off.
    if (!settings || (!settings.enabled && !manual)) return { archived: [], failed: 0 };
    const archived: Candidate[] = [];
    let failed = 0;
    for (const candidate of stale(await deps.workspaces(), settings, deps.now())) {
      try {
        await deps.archive(candidate.id);
        archived.push(candidate);
        deps.log(`Archived ${candidate.id} (${candidate.title}) after ${candidate.idleDays.toFixed(1)} idle days.`);
      } catch (error) {
        failed++;
        deps.log(`Could not archive ${candidate.id} (${candidate.title}): ${message(error)}`);
      }
    }
    lastSweep = { at: new Date(deps.now()).toISOString(), archived: archived.length, failed };
    return { archived, failed };
  }

  function sweep(manual = false) {
    running ??= run(manual).finally(() => { running = null; });
    return running;
  }

  return { preview, sweep, lastSweep: () => lastSweep };
}

export const message = (error: unknown) => error instanceof Error ? error.message : String(error);
