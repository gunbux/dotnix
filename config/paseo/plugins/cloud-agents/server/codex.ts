import { execFile } from 'node:child_process';
import { stat } from 'node:fs/promises';
import { isAbsolute } from 'node:path';
import { z } from 'zod';
import { codexTaskSchema, type CodexTask } from '../shared/rpc.ts';

export type Run = (args: string[], options: { cwd?: string; timeoutMs: number }) =>
  Promise<{ code: number; stdout: string; stderr: string }>;

export function processRunner(binary: string): Run {
  return (args, { cwd, timeoutMs }) => new Promise(resolve => {
    execFile(binary, args, {
      cwd, timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024,
      env: { ...process.env, NO_COLOR: '1' },
    }, (error, stdout, stderr) => {
      const code = error ? (typeof error.code === 'number' ? error.code : 1) : 0;
      const spawnError = error && typeof error.code === 'string' ? `${binary}: ${error.message}` : '';
      resolve({ code, stdout: String(stdout), stderr: spawnError || String(stderr) });
    });
  });
}

const listSchema = z.object({ tasks: z.array(codexTaskSchema), cursor: z.string().nullable().optional() });

function failure(what: string, result: { stdout: string; stderr: string }): Error {
  const detail = (result.stderr || result.stdout).trim().split('\n').slice(-6).join('\n');
  return new Error(`${what} failed${detail ? `: ${detail}` : ''}`);
}

async function requireDirectory(cwd: string): Promise<void> {
  if (!isAbsolute(cwd)) throw new Error('Working directory must be an absolute path');
  const info = await stat(cwd).catch(() => null);
  if (!info?.isDirectory()) throw new Error(`Not a directory on this host: ${cwd}`);
}

export function codexCloud(run: Run) {
  return {
    async list(input: { environment?: string; cursor?: string }): Promise<{ tasks: CodexTask[]; cursor: string | null }> {
      const args = ['cloud', 'list', '--json', '--limit', '20'];
      if (input.environment) args.push('--env', input.environment);
      if (input.cursor) args.push('--cursor', input.cursor);
      const result = await run(args, { timeoutMs: 60_000 });
      if (result.code !== 0) throw failure('codex cloud list', result);
      const parsed = listSchema.parse(JSON.parse(result.stdout));
      return { tasks: parsed.tasks, cursor: parsed.cursor ?? null };
    },
    async diff(input: { taskId: string; attempt?: number }): Promise<string> {
      const args = ['cloud', 'diff', input.taskId];
      if (input.attempt) args.push('--attempt', String(input.attempt));
      const result = await run(args, { timeoutMs: 60_000 });
      if (result.code !== 0) throw failure('codex cloud diff', result);
      return result.stdout;
    },
    async apply(input: { taskId: string; cwd: string; attempt?: number }): Promise<{ ok: boolean; message: string }> {
      await requireDirectory(input.cwd);
      const args = ['cloud', 'apply', input.taskId];
      if (input.attempt) args.push('--attempt', String(input.attempt));
      const result = await run(args, { cwd: input.cwd, timeoutMs: 180_000 });
      const message = (result.stdout + result.stderr).trim();
      return { ok: result.code === 0, message: message || (result.code === 0 ? 'Applied.' : 'Apply failed.') };
    },
    async submit(input: { prompt: string; cwd: string; environment: string; branch?: string; attempts: number }): Promise<string> {
      await requireDirectory(input.cwd);
      if (!input.environment) throw new Error('Choose a Codex Cloud environment (id or label) or set a default in settings');
      const args = ['cloud', 'exec', '--env', input.environment, '--attempts', String(input.attempts)];
      if (input.branch) args.push('--branch', input.branch);
      // `--` keeps prompts that start with a dash from being parsed as flags.
      args.push('--', input.prompt);
      const result = await run(args, { cwd: input.cwd, timeoutMs: 120_000 });
      if (result.code !== 0) throw failure('codex cloud exec', result);
      const url = result.stdout.trim().split('\n').filter(Boolean).at(-1) ?? '';
      if (!/^https?:\/\//.test(url)) throw new Error(`Unexpected codex cloud exec output: ${result.stdout.trim()}`);
      return url;
    },
  };
}
