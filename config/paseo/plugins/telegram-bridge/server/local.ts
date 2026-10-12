import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { isIP } from 'node:net';

export function localUrl(listen: string): string {
  const match = /^(\[[^\]]+\]|[^:]+):(\d+)$/.exec(listen);
  const host = match?.[1].replace(/^\[|\]$/g, '');
  const port = Number(match?.[2]);
  if (!host || (!isIP(host) && host !== 'localhost') || port < 1 || port > 65535) throw new Error('Telegram bridge startup requires a local TCP listener.');
  return `ws://${isIP(host) === 6 ? '[::1]' : '127.0.0.1'}:${port}/ws`;
}
export async function localConnection(home: string) {
  try {
    const lock = JSON.parse(await readFile(join(home, 'paseo.pid'), 'utf8'));
    const url = localUrl(lock.listen);
    const token = (await readFile(join(home, 'local-credential'), 'utf8')).trim();
    if (!token) throw new Error('Missing credential');
    return { url, token };
  } catch { throw new Error('Cannot read the local Paseo TCP endpoint or credential.'); }
}
type Socket = Pick<WebSocket, 'addEventListener' | 'removeEventListener' | 'send' | 'close'>;

// Paseo 0.11.2 does not expose a startup session or cancellation in PaseoApi.
// Use its authenticated session protocol only to bootstrap our RPC and cancel.
export function requestLocal<T = Record<string, unknown>>(
  connection: { url: string; token: string }, message: Record<string, unknown>, responseType: string,
  signal: AbortSignal, makeSocket: (url: string) => Socket = url => new WebSocket(url),
): Promise<T> {
  signal.throwIfAborted();
  return new Promise((resolve, reject) => {
    const socket = makeSocket(connection.url);
    const requestId = randomUUID();
    let done = false;
    let sent = false;
    const finish = (error: Error | null, value?: T) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      signal.removeEventListener('abort', abort);
      socket.close();
      if (error) reject(error); else resolve(value as T);
    };
    const abort = () => finish(new Error('Local request canceled.'));
    const timer = setTimeout(() => finish(new Error('Local Paseo request timed out.')), 15000);
    signal.addEventListener('abort', abort, { once: true });
    socket.addEventListener('open', () => {
      socket.send(JSON.stringify({ type: 'hello', clientId: `telegram-bridge-${requestId}`, clientType: 'cli',
        protocolVersion: 1, appVersion: '0.11.2', capabilities: {}, auth: { kind: 'localCredential', token: connection.token } }));
    });
    socket.addEventListener('error', () => finish(new Error('Local Paseo connection failed.')));
    socket.addEventListener('close', () => finish(new Error('Local Paseo connection closed.')));
    socket.addEventListener('message', event => {
      if (done) return;
      try {
        const envelope = JSON.parse(String((event as MessageEvent).data));
        if (envelope.type === 'hello.rejected') return finish(new Error('Paseo rejected the local credential.'));
        const reply = envelope.message;
        if (reply?.type === 'status' && reply.payload?.status === 'server_info' && !sent) {
          sent = true;
          socket.send(JSON.stringify({ type: 'session', message: { ...message, requestId } }));
        }
        if (reply?.payload?.requestId !== requestId) return;
        if (reply.type === 'rpc_error' || reply.payload.error) return finish(new Error('Paseo rejected the bridge request.'));
        if (reply.type === responseType) finish(null, reply.payload);
      } catch { finish(new Error('Invalid local Paseo response.')); }
    });
  });
}
