import { execFile } from 'node:child_process';
import { tmpdir } from 'node:os';
import { promisify } from 'node:util';
import type { Settings } from '../shared/settings';
import { SYSTEM_PROMPT } from '../shared/topics';

const exec = promisify(execFile);
const LABEL_SCHEMA = JSON.stringify({
  type: 'object', properties: { label: { type: 'string' } }, required: ['label'], additionalProperties: false,
});

// Headless Claude Code reuses the user's existing login, so no API key is stored.
// Tools, MCP servers, hooks, skills, and session history are all disabled.
export async function classify(prompt: string, model: Settings['model']): Promise<string> {
  const run = exec(process.env.PASEO_AUTO_LABEL_CLAUDE || 'claude', ['-p', '--model', model, '--tools', '',
    '--strict-mcp-config', '--setting-sources', '', '--disable-slash-commands', '--no-session-persistence',
    '--output-format', 'json', '--json-schema', LABEL_SCHEMA, '--system-prompt', SYSTEM_PROMPT, prompt],
  { cwd: tmpdir(), timeout: 120000, maxBuffer: 4194304 });
  run.child.stdin?.end();
  const { stdout } = await run.catch(error => {
    throw new Error(`Claude classification failed: ${(error.stderr || error.message || '').trim().slice(0, 500)}`);
  });
  const result = JSON.parse(stdout);
  const label = result.structured_output?.label;
  if (result.is_error || typeof label !== 'string') throw new Error(`Claude returned no label: ${String(result.result).slice(0, 500)}`);
  return label;
}
