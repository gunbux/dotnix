import assert from 'node:assert/strict';
import { tmpdir } from 'node:os';
import { test } from 'node:test';
import { codexCloud, processRunner, type Run } from '../server/codex.ts';

function fake(result: { code?: number; stdout?: string; stderr?: string }) {
  const calls: { args: string[]; cwd?: string }[] = [];
  const run: Run = async (args, { cwd }) => { calls.push({ args, cwd }); return { code: 0, stdout: '', stderr: '', ...result }; };
  return { calls, cli: codexCloud(run) };
}

test('list parses `codex cloud list --json` and forwards filters', async () => {
  const { calls, cli } = fake({ stdout: JSON.stringify({ tasks: [{
    id: 'task_e_1', url: 'https://chatgpt.com/codex/tasks/task_e_1', title: 'Fix', status: 'ready',
    updated_at: '2026-10-06T00:00:00Z', environment_id: 'env', environment_label: 'repo',
    summary: { files_changed: 1, lines_added: 2, lines_removed: 3 }, is_review: false, attempt_total: 2,
  }], cursor: null }) });
  const page = await cli.list({ environment: 'repo', cursor: 'c1' });
  assert.equal(page.tasks[0].id, 'task_e_1');
  assert.deepEqual(calls[0].args, ['cloud', 'list', '--json', '--limit', '20', '--env', 'repo', '--cursor', 'c1']);
});

test('submit runs from the workspace, guards dash-leading prompts, and returns the task URL', async () => {
  const { calls, cli } = fake({ stdout: 'https://chatgpt.com/codex/tasks/task_e_9\n' });
  const url = await cli.submit({ prompt: '--help me', cwd: tmpdir(), environment: 'repo', attempts: 2, branch: 'main' });
  assert.equal(url, 'https://chatgpt.com/codex/tasks/task_e_9');
  assert.deepEqual(calls[0], { cwd: tmpdir(), args: ['cloud', 'exec', '--env', 'repo', '--attempts', '2', '--branch', 'main', '--', '--help me'] });
});

test('submit and apply reject missing environments and non-directories before running codex', async () => {
  const { calls, cli } = fake({});
  await assert.rejects(cli.submit({ prompt: 'x', cwd: tmpdir(), environment: '', attempts: 1 }), /environment/);
  await assert.rejects(cli.apply({ taskId: 't', cwd: 'relative/path' }), /absolute/);
  await assert.rejects(cli.apply({ taskId: 't', cwd: '/definitely/missing/dir' }), /Not a directory/);
  assert.equal(calls.length, 0);
});

test('failures surface the tail of stderr', async () => {
  const { cli } = fake({ code: 1, stderr: 'noise\nError: Not signed in. Run `codex login`.' });
  await assert.rejects(cli.diff({ taskId: 't' }), /codex cloud diff failed: noise\nError: Not signed in/);
});

test('a missing binary is reported rather than thrown as an unhandled spawn error', async () => {
  const result = await processRunner('/nonexistent/codex')(['cloud', 'list'], { timeoutMs: 5000 });
  assert.notEqual(result.code, 0);
  assert.match(result.stderr, /ENOENT/);
});
