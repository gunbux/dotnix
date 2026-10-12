import { mkdir, open, readFile, rename, rm } from 'node:fs/promises';
import { dirname } from 'node:path';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';

const action = z.object({ label: z.string(), behavior: z.enum(['allow', 'deny']), selectedActionId: z.string().optional() });
const outgoing = z.object({ text: z.string(), buttons: z.array(z.array(z.object({ text: z.string(), callback_data: z.string() }))).optional() });
const legacySchema = z.object({
  version: z.literal(1), owner: z.string(), botId: z.string(), offset: z.number().int().nonnegative(),
  selectedAgent: z.string().nullable(), watchedAgents: z.array(z.string()),
  approvals: z.record(z.string(), z.object({ agentId: z.string(), requestId: z.string(), expires: z.number(), actions: z.array(action) })),
  outbox: z.array(outgoing),
});
const chatSchema = z.object({ workspaceKey: z.string().optional(), title: z.string(), workspaceId: z.string().nullable(), selectedAgent: z.string().nullable(), watchedAgents: z.array(z.string()) });
export const stateSchema = z.object({
  version: z.literal(2), owner: z.string(), botId: z.string(), offset: z.number().int().nonnegative(),
  chats: z.record(z.string(), chatSchema),
  approvals: z.record(z.string(), z.object({ chatId: z.string(), agentId: z.string(), requestId: z.string(), expires: z.number(), actions: z.array(action) })),
  outbox: z.array(outgoing.extend({ chatId: z.string() })),
});
export type State = z.infer<typeof stateSchema>;
export type Chat = z.infer<typeof chatSchema>;
export function emptyChat(title: string): Chat {
  return { title, workspaceId: null, selectedAgent: null, watchedAgents: [] };
}
export function emptyState(owner: string, botId: string): State {
  return { version: 2, owner, botId, offset: 0, chats: {}, approvals: {}, outbox: [] };
}
export async function readState(file: string, owner: string, botId: string): Promise<State> {
  let raw: string;
  try { raw = await readFile(file, 'utf8'); }
  catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return emptyState(owner, botId);
    throw new Error('Cannot read Telegram bridge state.');
  }
  // Corrupt state must not silently reset the offset and replay commands.
  const json = JSON.parse(raw);
  const legacy = legacySchema.safeParse(json);
  const migrated = legacy.success ? {
    ...emptyState(legacy.data.owner, legacy.data.botId), offset: legacy.data.offset,
    // Global v1 selections may point outside the new chat workspace. Do not migrate them.
    // Pending deliveries remain private; obsolete approval buttons are removed.
    outbox: legacy.data.outbox.map(item => ({ chatId: legacy.data.owner, text: item.text })),
  } : json;
  const parsed = stateSchema.safeParse(migrated);
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

export function revokeChat(state: State, chatId: string): void {
  delete state.chats[chatId];
  state.outbox = state.outbox.filter(item => item.chatId !== chatId);
  for (const [key, approval] of Object.entries(state.approvals)) if (approval.chatId === chatId) delete state.approvals[key];
}

export function migrateChat(state: State, oldId: string, newId: string): boolean {
  if (!/^-\d+$/.test(oldId) || !/^-\d+$/.test(newId) || oldId === newId) return false;
  const old = state.chats[oldId];
  if (!old || state.chats[newId]) return false;
  old.workspaceKey ??= `${state.botId}/${oldId}`;
  state.chats[newId] = old;
  delete state.chats[oldId];
  for (const item of state.outbox) if (item.chatId === oldId) item.chatId = newId;
  for (const approval of Object.values(state.approvals)) if (approval.chatId === oldId) approval.chatId = newId;
  return true;
}
