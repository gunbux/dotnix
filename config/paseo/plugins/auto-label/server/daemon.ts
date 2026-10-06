import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import type { Label } from '../shared/topics';

// The 0.10.3 plugin SDK and CLI cannot read or assign workspace labels. Send the
// app's own session requests over an authenticated local connection instead.
async function request<T>(message: Record<string, unknown>, responseType: string): Promise<T> {
  const home = process.env.PASEO_HOME;
  if (!home) throw new Error('Paseo did not supply PASEO_HOME to the plugin.');
  const lock = JSON.parse(await readFile(join(home, 'paseo.pid'), 'utf8'));
  if (typeof lock.listen !== 'string' || !/:\d+$/.test(lock.listen)) throw new Error('Workspace labels require a TCP daemon listener.');
  const url = new URL(`ws://${lock.listen}/ws`);
  if (url.hostname === '0.0.0.0') url.hostname = '127.0.0.1';
  if (url.hostname === '[::]') url.hostname = '[::1]';
  const token = (await readFile(join(home, 'local-credential'), 'utf8')).trim();
  const requestId = randomUUID();
  return new Promise<T>((resolve, reject) => {
    const socket = new WebSocket(url.toString());
    let finished = false;
    const finish = (error: Error | null, payload?: T) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      socket.close();
      if (error) reject(error); else resolve(payload as T);
    };
    const timer = setTimeout(() => finish(new Error(`Timed out waiting for ${responseType}.`)), 30000);
    socket.addEventListener('open', () => socket.send(JSON.stringify({ type: 'hello', clientId: `auto-label-${requestId}`,
      clientType: 'cli', protocolVersion: 1, appVersion: '0.10.3', capabilities: {}, auth: { kind: 'localCredential', token } })));
    socket.addEventListener('error', () => finish(new Error('Could not connect to the daemon.')));
    socket.addEventListener('close', () => finish(new Error(`Daemon disconnected before ${responseType}.`)));
    socket.addEventListener('message', event => {
      try {
        const envelope = JSON.parse(String(event.data));
        if (envelope.type === 'hello.rejected') { finish(new Error('Daemon rejected the local plugin connection.')); return; }
        const reply = envelope.message;
        if (reply?.type === 'server_info' || reply?.payload?.status === 'server_info') {
          socket.send(JSON.stringify({ type: 'session', message: { ...message, requestId } }));
        }
        if (reply?.payload?.requestId !== requestId) return;
        if (reply.type === 'rpc_error') finish(new Error(reply.payload.error));
        if (reply.type === responseType) finish(null, reply.payload);
      } catch { finish(new Error(`Invalid daemon response while waiting for ${responseType}.`)); }
    });
  });
}

export async function listLabels(): Promise<Label[]> {
  const payload = await request<{ labels: Label[] }>({ type: 'workspace.label.list.request' }, 'workspace.label.list.response');
  return payload.labels;
}

export async function assignLabel(workspaceId: string, label: Label): Promise<void> {
  await request({ type: 'workspace.label.assignment.set.request', workspaceId, label, assigned: true },
    'workspace.label.assignment.set.response');
}
