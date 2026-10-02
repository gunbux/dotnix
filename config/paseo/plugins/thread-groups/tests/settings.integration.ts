// Run only against the disposable verification daemon. This writes fake thread references.
import assert from 'node:assert/strict';
import { DaemonClient } from '@getpaseo/client/internal/daemon-client';

const url = process.argv[2];
if (url !== 'ws://127.0.0.1:16877/ws') throw new Error('Use the isolated verification daemon on port 16877.');
const client = new DaemonClient({ url, clientId: 'thread-groups-verification', clientType: 'cli', appVersion: '0.10.3' });
const rpc = (method: string, input: unknown) => client.invokePluginRpc('thread-groups', `settings.groups.${method}`, input);
type Ready = { status: 'ready'; revision: string; values: { groups: { id: string; name: string; agentIds: string[] }[] } };
await client.connect();
try {
  const initial = await rpc('read', {}) as Ready;
  assert.equal(initial.status, 'ready');
  const values = { groups: [{ id: 'integration', name: 'Persistence check', agentIds: ['fake-thread'] }] };
  const results = await Promise.all([
    rpc('write', { revision: initial.revision, values }),
    rpc('write', { revision: initial.revision, values: { groups: [] } }),
  ]) as { status: string }[];
  assert.deepEqual(results.map(r => r.status).sort(), ['conflict', 'saved']);
  const before = await rpc('read', {}) as Ready;
  const invalid = await rpc('write', { revision: before.revision, values: { groups: 'corrupt' } }) as { status: string };
  assert.equal(invalid.status, 'invalid');
  assert.deepEqual(await rpc('read', {}), before);
  const saved = await rpc('write', { revision: before.revision, values }) as { status: string };
  assert.equal(saved.status, 'saved');
  await client.reloadPlugin('thread-groups');
  const after = await rpc('read', {}) as Ready;
  assert.equal(after.status, 'ready');
  assert.deepEqual(after.values, values);
  const catalog = await client.getPluginCatalog();
  assert.ok(catalog.find(p => p.id === 'thread-groups')?.clientBundle);
  console.log('Settings: concurrent conflict, invalid-write recovery, reload persistence, and client bundle verified.');
} finally { await client.close(); }
