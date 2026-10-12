export type Button = { text: string; callback_data: string };
export type Outgoing = { text: string; buttons?: Button[][] };
export type Update = {
  update_id: number;
  message?: { message_id: number; date: number; from?: { id: number }; chat: { id: number; type: string }; text?: string };
  callback_query?: { id: string; from: { id: number }; data?: string; message?: { message_id: number; chat: { id: number; type: string } } };
};

export class TelegramError extends Error {
  code: number;
  retryAfter: number;
  constructor(code: number, retryAfter = 0) {
    super(`Telegram request failed (${code}).`);
    this.code = code;
    this.retryAfter = retryAfter;
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
    let data: { ok?: boolean; result?: T; error_code?: number; parameters?: { retry_after?: number } };
    try { data = await response.json() as typeof data; } catch { throw new TelegramError(response.status); }
    if (!response.ok || !data.ok) throw new TelegramError(data.error_code ?? response.status, data.parameters?.retry_after ?? 0);
    return data.result as T;
  }
  updates(offset: number) {
    return this.call<Update[]>('getUpdates', { offset, timeout: 25, limit: 100, allowed_updates: ['message', 'callback_query'] });
  }
  send(chatId: string, message: Outgoing) {
    return this.call('sendMessage', {
      chat_id: chatId, text: message.text, link_preview_options: { is_disabled: true },
      ...(message.buttons ? { reply_markup: { inline_keyboard: message.buttons } } : {}),
    });
  }
}
