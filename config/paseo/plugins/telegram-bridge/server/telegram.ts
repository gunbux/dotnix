export type Button = { text: string; callback_data: string };
export type Outgoing = { text: string; buttons?: Button[][] };
type TelegramChat = { id: number; type: string; title?: string; first_name?: string };
export type Update = {
  update_id: number;
  my_chat_member?: { chat: TelegramChat; new_chat_member: { status: string } };
  message?: { message_id: number; date: number; from?: { id: number; is_bot?: boolean }; sender_chat?: { id: number }; chat: TelegramChat; migrate_to_chat_id?: number; migrate_from_chat_id?: number; text?: string };
  callback_query?: { id: string; from: { id: number; is_bot?: boolean }; data?: string; message?: { message_id: number; chat: TelegramChat; sender_chat?: { id: number } } };
};

export class TelegramError extends Error {
  code: number;
  retryAfter: number;
  migrateToChatId?: number;
  constructor(code: number, retryAfter = 0, migrateToChatId?: number) {
    super(`Telegram request failed (${code}).`);
    this.code = code;
    this.retryAfter = retryAfter;
    this.migrateToChatId = migrateToChatId;
  }
}

export function splitText(text: string): string[] {
  const chunks: string[] = [];
  while (text.length > 4000) {
    let end = 4000;
    if (/[\uD800-\uDBFF]/.test(text[end - 1])) end--;
    chunks.push(text.slice(0, end));
    text = text.slice(end);
  }
  if (text) chunks.push(text);
  return chunks;
}

export class Telegram {
  private token: string;
  private signal: AbortSignal;
  private fetcher: typeof fetch;
  constructor(token: string, signal: AbortSignal, fetcher: typeof fetch = fetch) {
    this.token = token;
    this.signal = signal;
    this.fetcher = fetcher;
  }
  async call<T>(method: string, body: Record<string, unknown>): Promise<T> {
    let response: Response;
    try {
      response = await this.fetcher(`https://api.telegram.org/bot${this.token}/${method}`, {
        method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
        signal: AbortSignal.any([this.signal, AbortSignal.timeout(method === 'getUpdates' ? 35000 : 15000)]),
      });
    } catch {
      // Fetch errors may contain the full URL, including the bot token.
      throw new TelegramError(0);
    }
    let data: { ok?: boolean; result?: T; error_code?: number; parameters?: { retry_after?: number; migrate_to_chat_id?: number } };
    try { data = await response.json() as typeof data; } catch { throw new TelegramError(response.status); }
    if (!response.ok || !data.ok) throw new TelegramError(data.error_code ?? response.status, data.parameters?.retry_after ?? 0, data.parameters?.migrate_to_chat_id);
    return data.result as T;
  }
  updates(offset: number) {
    return this.call<Update[]>('getUpdates', { offset, timeout: 25, limit: 100, allowed_updates: ['message', 'callback_query', 'my_chat_member'] });
  }
  send(chatId: string, message: Outgoing) {
    return this.call('sendMessage', {
      chat_id: chatId, text: message.text, link_preview_options: { is_disabled: true },
      ...(message.buttons ? { reply_markup: { inline_keyboard: message.buttons } } : {}),
    });
  }
}
