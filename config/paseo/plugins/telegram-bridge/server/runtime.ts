import { readFile, stat } from 'node:fs/promises';
import { isAbsolute, join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { Bridge, type AgentPort } from './bridge.ts';
import { migrateChat, revokeChat, readState, writeState, type State } from './state.ts';
import { Telegram, TelegramError, type Outgoing } from './telegram.ts';
import type { Config } from '../shared/settings.ts';

export async function readToken(file: string): Promise<string> {
  if (!isAbsolute(file)) throw new Error('Set an absolute bot token file path.');
  let token: string;
  try {
    const info = await stat(file);
    if (!info.isFile() || info.size > 1024) throw new Error('Invalid token file.');
    if (process.platform !== 'win32' && (info.mode & 0o077) !== 0) throw new Error('Token file permissions must be 0600 or 0400.');
    token = (await readFile(file, 'utf8')).trim();
  } catch (error) {
    if (error instanceof Error && error.message.startsWith('Token file permissions')) throw error;
    throw new Error('Cannot read the bot token file.');
  }
  if (!/^\d+:[A-Za-z0-9_-]{20,}$/.test(token)) throw new Error('The bot token file has an invalid format.');
  return token;
}

export async function deliverOne(state: State, send: (owner: string, item: Outgoing) => Promise<unknown>, save: () => Promise<void>) {
  const item = state.outbox[0];
  if (!item) return;
  try { await send(item.chatId, item); }
  catch (error) {
    if (error instanceof TelegramError && error.code === 400 && Number.isSafeInteger(error.migrateToChatId)
      && migrateChat(state, item.chatId, String(error.migrateToChatId))) {
      await save();
      return;
    }
    if (!(error instanceof TelegramError) || error.code !== 403) throw error;
    // A removed/blocked bot affects this chat only, not every workspace.
    revokeChat(state, item.chatId);
    await save();
    return;
  }
  state.outbox.shift();
  await save();
}

export type Runtime = {
  enqueue(work: (bridge: Bridge) => Promise<void>): void;
  snapshot(): { bot: string; selectedAgent: string | null; queued: number };
  close(): Promise<void>;
};

export async function startRuntime(config: Config, port: AgentPort, home: string, parentSignal: AbortSignal,
  report: (status: string) => void, fetcher: typeof fetch = fetch): Promise<Runtime> {
  if (!config.ownerId) throw new Error('Set your Telegram numeric user ID.');
  const controller = new AbortController();
  const signal = AbortSignal.any([controller.signal, parentSignal]);
  const api = new Telegram(await readToken(config.tokenFile), signal, fetcher);
  const bot = await api.call<{ id: number; username: string }>('getMe', {});
  const webhook = await api.call<{ url: string }>('getWebhookInfo', {});
  if (webhook.url) throw new Error('This bot has a webhook. Use a dedicated bot or remove its webhook before enabling the bridge.');
  const file = join(home, 'plugin-data', 'telegram-bridge', 'state.json');
  const state = await readState(file, config.ownerId, String(bot.id));
  const save = async () => {
    try { await writeState(file, state); }
    catch { report('Stopped: could not save bridge state. Check disk space and file permissions, then reload the plugin.'); controller.abort(); throw new Error('Bridge state could not be saved.'); }
  };
  await save();
  const bridge = new Bridge({ state, port, save, now: Date.now, defaultProvider: config.defaultProvider, botUsername: bot.username });
  let serial = Promise.resolve();
  const queue = <T>(work: () => Promise<T>): Promise<T> => {
    const next = serial.then(() => { signal.throwIfAborted(); return work(); });
    serial = next.then(() => {}, () => {});
    return next;
  };
  const fatal = (status: string) => { if (!signal.aborted) report(status); controller.abort(); };
  const sleep = (ms: number) => delay(ms, undefined, { signal }).catch(() => {});
  let pauseUntil = 0;
  const retry = async (error: unknown): Promise<boolean> => {
    if (signal.aborted) return false;
    if (!(error instanceof TelegramError)) { fatal('Stopped: bridge operation failed. Reload the plugin and check its settings.'); return false; }
    if ([401, 403, 404, 409].includes(error.code)) {
      fatal(error.code === 409 ? 'Stopped: another program is polling this bot. Use a dedicated bot.'
        : `Stopped: Telegram rejected the request (${error.code}). Check the token and unblock/start the bot, then reload.`);
      return false;
    }
    if (error.code === 400) { fatal('Stopped: Telegram rejected a message. Check the bridge state before reloading.'); return false; }
    report(`Telegram unavailable (${error.code || 'network'}); retrying.`);
    pauseUntil = Date.now() + Math.max(3000, error.retryAfter * 1000);
    await sleep(pauseUntil - Date.now());
    return !signal.aborted;
  };
  const poll = async () => {
    while (!signal.aborted) {
      try {
        if (Date.now() < pauseUntil) { await sleep(pauseUntil - Date.now()); continue; }
        const updates = await api.updates(state.offset);
        for (const update of updates) {
          const answer = await queue(() => bridge.update(update));
          if (answer) {
            // Answering an old Telegram callback can fail even though Paseo accepted it.
            await api.call('answerCallbackQuery', { callback_query_id: answer.callbackId, text: answer.text }).catch(() => {});
          }
        }
        if (!signal.aborted) report('Connected');
      } catch (error) { if (!(await retry(error))) break; }
    }
  };
  const deliver = async () => {
    while (!signal.aborted) {
      try {
        if (Date.now() < pauseUntil) { await sleep(pauseUntil - Date.now()); continue; }
        await queue(async () => {
          if (state.outbox.length > 1000) throw new Error('Too many undelivered messages.');
          await deliverOne(state, (owner, item) => api.send(owner, item), save);
        });
        await sleep(1100);
      } catch (error) { if (!(await retry(error))) break; }
    }
  };
  // Hooks are best-effort, so recover approvals already pending when we start.
  for (const id of Object.values(state.chats).flatMap(chat => chat.watchedAgents)) {
    try { await bridge.pending(id, true); } catch { /* An archived/deleted agent may no longer be available. */ }
  }
  signal.throwIfAborted();
  report('Connected');
  const loops = [poll(), deliver()];
  return {
    enqueue(work) {
      if (signal.aborted) return;
      void queue(() => work(bridge)).catch(() => fatal('Stopped: could not record an agent event. Reload the plugin.'));
    },
    snapshot: () => ({ bot: bot.username, selectedAgent: state.chats[state.owner]?.selectedAgent ?? null, queued: state.outbox.length }),
    async close() { controller.abort(); await Promise.allSettled(loops); await serial; },
  };
}
