// Run only against a disposable verification daemon with this plugin installed. It rewrites the
// plugin's settings to point at an in-process fake API and a fake codex binary.
import assert from 'node:assert/strict';
import { chmod, mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DaemonClient } from '@getpaseo/client/internal/daemon-client';
import { fakeApi } from './fake-api.ts';

const url = process.argv[2];
if (url !== 'ws://127.0.0.1:16877/ws') throw new Error('Use the isolated verification daemon on port 16877.');
const client = new DaemonClient({ url, clientId: 'cloud-agents-verification', clientType: 'cli', appVersion: '0.10.3' });
const rpc = (method: string, input: unknown) => client.invokePluginRpc('cloud-agents', method, input);
const api = await fakeApi();
const dir = await mkdtemp(join(tmpdir(), 'cloud-agents-'));
const keyFile = join(dir, 'anthropic_api_key');
const codex = join(dir, 'codex');
await writeFile(keyFile, 'sk-test\n', { mode: 0o600 });
await writeFile(codex, `#!/bin/sh
case "$1 $2" in
  "cloud list") echo '{"tasks":[{"id":"task_e_1","url":"https://chatgpt.com/codex/tasks/task_e_1","title":"Fix login","status":"ready","updated_at":"2026-10-06T00:00:00Z","environment_id":"env","environment_label":"dotnix","summary":{"files_changed":1,"lines_added":3,"lines_removed":1},"is_review":false,"attempt_total":1}],"cursor":null}' ;;
  "cloud diff") printf 'diff --git a/x b/x\\n+hello\\n' ;;
  "cloud exec") echo "https://chatgpt.com/codex/tasks/task_e_2 from $PWD" | cut -d' ' -f1 ;;
  *) echo "unexpected $*" >&2; exit 2 ;;
esac
`);
await chmod(codex, 0o755);

await client.connect();
try {
  const read = await rpc('settings.config.read', {}) as { revision: string };
  const saved = await rpc('settings.config.write', { revision: read.revision, values: {
    claude: { apiKeyFile: keyFile, baseUrl: api.baseUrl, defaultAgentId: '', defaultEnvironmentId: '' },
    codex: { binary: codex, defaultEnvironment: 'dotnix' },
  } }) as { status: string };
  assert.equal(saved.status, 'saved');

  // Control plane RPCs.
  const status = await rpc('claude.status', {}) as { configured: boolean; source: string };
  // ANTHROPIC_API_KEY in the daemon's environment would take precedence; this daemon has none.
  assert.deepEqual([status.configured, status.source], [true, 'file']);
  const catalog = await rpc('claude.catalog', {}) as { agents: { id: string }[]; environments: { id: string }[] };
  assert.deepEqual([catalog.agents[0].id, catalog.environments[0].id], ['agent_1', 'env_1']);
  const tasks = await rpc('codex.tasks', {}) as { tasks: { id: string }[] };
  assert.equal(tasks.tasks[0].id, 'task_e_1');
  assert.match((await rpc('codex.diff', { taskId: 'task_e_1' }) as { diff: string }).diff, /\+hello/);
  assert.deepEqual(await rpc('codex.submit', { prompt: 'Add tests', cwd: dir }), { url: 'https://chatgpt.com/codex/tasks/task_e_2' });
  await assert.rejects(rpc('codex.submit', { prompt: 'x', cwd: 'relative' }), /absolute/);

  // Chat through the daemon: the provider appears, opens a cloud session, asks for approval, and replies.
  const agent = await client.createAgent({ provider: 'claude-cloud', cwd: dir, model: 'agent_1', modeId: 'env_1', title: 'Cloud verification' });
  await client.sendAgentMessage(agent.id, 'run tests');
  const waiting = await client.waitForFinish(agent.id, 20_000);
  assert.equal(waiting.status, 'permission', `expected a permission prompt, got ${waiting.status}: ${waiting.error}`);
  const permission = waiting.final?.pendingPermissions[0];
  assert.ok(permission, 'pending permission is visible to clients');
  await client.respondToPermission(agent.id, permission.id, { behavior: 'allow' });
  // waitForFinish reports the latest snapshot, so let the resolution land before waiting again.
  await client.waitForAgentUpsert(agent.id, snapshot => snapshot.pendingPermissions.length === 0, 20_000);
  const done = await client.waitForFinish(agent.id, 20_000);
  assert.equal(done.status, 'idle', `expected idle, got ${done.status}: ${done.error}`);
  assert.equal(done.lastMessage, 'Tests pass.');

  const sessions = await rpc('claude.sessions', { includeArchived: true }) as { sessions: { id: string }[] };
  assert.equal(sessions.sessions[0].id, 'sesn_1');
  await rpc('claude.session-action', { sessionId: 'sesn_1', action: 'archive' });
  assert.ok(api.isArchived());
  console.log('Daemon: settings, Claude status/catalog/sessions/archive, Codex list/diff/submit, and a Claude cloud chat with approval verified.');
} finally {
  await client.close();
  await api.close();
}
