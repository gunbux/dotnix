import test from 'node:test';
import assert from 'node:assert/strict';
import { localUrl, requestLocal } from '../server/local.ts';

test('startup connections always target loopback, including wildcard listeners', () => {
  assert.equal(localUrl('0.0.0.0:6767'), 'ws://127.0.0.1:6767/ws');
  assert.equal(localUrl('[::]:6767'), 'ws://[::1]:6767/ws');
  assert.equal(localUrl('192.168.1.2:7000'), 'ws://127.0.0.1:7000/ws');
  assert.throws(() => localUrl('unix:///tmp/socket'), /TCP/);
  assert.throws(() => localUrl('evil.test:6767'), /TCP/);
});

class Socket extends EventTarget {
  sent: Record<string, unknown>[] = [];
  closed = false;
  send(text: string) {
    const data = JSON.parse(text);
    this.sent.push(data);
    if (data.type === 'hello') queueMicrotask(() => this.reply({ type: 'session', message: { type: 'status', payload: { status: 'server_info', protocolVersion: 1, serverId: 'test', version: '0.11.2' } } }));
    else queueMicrotask(() => this.reply({ type: 'session', message: { type: 'plugin.rpc.invoke.response', payload: { requestId: data.message.requestId, output: { ready: true } } } }));
  }
  reply(data: unknown) { this.dispatchEvent(new MessageEvent('message', { data: JSON.stringify(data) })); }
  close() { this.closed = true; }
}
test('bootstrap authenticates then correlates exactly one RPC and closes the connection', async () => {
  const socket = new Socket();
  const result = requestLocal({ url: 'ws://127.0.0.1:6767/ws', token: 'local-secret' }, { type: 'plugin.rpc.invoke.request', pluginId: 'telegram-bridge', method: 'bridge.status', input: {} }, 'plugin.rpc.invoke.response', new AbortController().signal, () => {
    queueMicrotask(() => socket.dispatchEvent(new Event('open')));
    return socket;
  });
  assert.deepEqual(await result, { output: { ready: true }, requestId: (socket.sent[1].message as { requestId: string }).requestId });
  assert.equal(socket.sent[0].type, 'hello');
  assert.deepEqual(socket.sent[0].auth, { kind: 'localCredential', token: 'local-secret' });
  assert.equal(socket.closed, true);
});
