import { mkdir, open, readFile, rename, rm } from 'node:fs/promises';
import { dirname } from 'node:path';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';

const action = z.object({ label: z.string(), behavior: z.enum(['allow', 'deny']), selectedActionId: z.string().optional() });
export const stateSchema = z.object({
  version: z.literal(1), owner: z.string(), botId: z.string(), offset: z.number().int().nonnegative(),
  selectedAgent: z.string().nullable(), watchedAgents: z.array(z.string()),
  approvals: z.record(z.string(), z.object({ agentId: z.string(), requestId: z.string(), expires: z.number(), actions: z.array(action) })),
  outbox: z.array(z.object({ text: z.string(), buttons: z.array(z.array(z.object({ text: z.string(), callback_data: z.string() }))).optional() })),
});
export type State = z.infer<typeof stateSchema>;
export function emptyState(owner: string, botId: string): State {
  return { version: 1, owner, botId, offset: 0, selectedAgent: null, watchedAgents: [], approvals: {}, outbox: [] };
}
export async function readState(file: string, owner: string, botId: string): Promise<State> {
  let raw: string;
  try { raw = await readFile(file, 'utf8'); }
  catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return emptyState(owner, botId);
    throw new Error('Cannot read Telegram bridge state.');
  }
  // Corrupt state must not silently reset the offset and replay commands.
  const parsed = stateSchema.safeParse(JSON.parse(raw));
  if (!parsed.success) throw new Error('Invalid Telegram bridge state. Restore or remove state.json while the bridge is disabled.');
  return parsed.data.owner === owner && parsed.data.botId === botId ? parsed.data : emptyState(owner, botId);
}
export async function writeState(file: string, state: State): Promise<void> {
  await mkdir(dirname(file), { recursive: true, mode: 0o700 });
  const temporary = `${file}.${randomUUID()}.tmp`;
  try {
    const handle = await open(temporary, 'wx', 0o600);
    try {
      await handle.writeFile(JSON.stringify(state));
      await handle.sync();
    } finally { await handle.close(); }
    await rename(temporary, file);
    if (process.platform !== 'win32') {
      const directory = await open(dirname(file), 'r');
      try { await directory.sync(); } finally { await directory.close(); }
    }
  } finally { await rm(temporary, { force: true }); }
}
