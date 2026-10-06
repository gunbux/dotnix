import { defineRpc } from '@getpaseo/plugin';
import { z } from 'zod';

const empty = z.object({});

export const claudeStatus = defineRpc({
  name: 'claude.status',
  input: empty,
  output: z.object({ configured: z.boolean(), source: z.enum(['env', 'file', 'none']), detail: z.string() }),
});

export const claudeSessionSchema = z.object({
  id: z.string(),
  title: z.string().nullable(),
  status: z.string(),
  agentName: z.string(),
  model: z.string(),
  environmentId: z.string(),
  updatedAt: z.string(),
  archived: z.boolean(),
  costUsd: z.number().nullable(),
});
export type ClaudeSession = z.infer<typeof claudeSessionSchema>;

export const claudeSessions = defineRpc({
  name: 'claude.sessions',
  input: z.object({ includeArchived: z.boolean().default(false) }),
  output: z.object({ sessions: z.array(claudeSessionSchema) }),
});

export const claudeCatalog = defineRpc({
  name: 'claude.catalog',
  input: empty,
  output: z.object({
    agents: z.array(z.object({ id: z.string(), name: z.string(), model: z.string() })),
    environments: z.array(z.object({ id: z.string(), name: z.string() })),
  }),
});

export const claudeSessionAction = defineRpc({
  name: 'claude.session-action',
  input: z.object({ sessionId: z.string().min(1), action: z.enum(['archive', 'interrupt']) }),
  output: z.object({ ok: z.literal(true) }),
});

export const codexTaskSchema = z.object({
  id: z.string(),
  url: z.string(),
  title: z.string(),
  status: z.string(),
  updated_at: z.string(),
  environment_id: z.string().nullable().optional(),
  environment_label: z.string().nullable().optional(),
  summary: z.object({
    files_changed: z.number(),
    lines_added: z.number(),
    lines_removed: z.number(),
  }).partial().optional(),
  is_review: z.boolean().optional(),
  attempt_total: z.number().nullable().optional(),
});
export type CodexTask = z.infer<typeof codexTaskSchema>;

export const codexTasks = defineRpc({
  name: 'codex.tasks',
  input: z.object({ environment: z.string().optional(), cursor: z.string().optional() }),
  output: z.object({ tasks: z.array(codexTaskSchema), cursor: z.string().nullable() }),
});

export const codexDiff = defineRpc({
  name: 'codex.diff',
  input: z.object({ taskId: z.string().min(1), attempt: z.number().int().min(1).optional() }),
  output: z.object({ diff: z.string() }),
});

export const codexApply = defineRpc({
  name: 'codex.apply',
  input: z.object({ taskId: z.string().min(1), cwd: z.string().min(1), attempt: z.number().int().min(1).optional() }),
  output: z.object({ ok: z.boolean(), message: z.string() }),
});

export const codexSubmit = defineRpc({
  name: 'codex.submit',
  input: z.object({
    prompt: z.string().trim().min(1).max(20000),
    cwd: z.string().min(1),
    environment: z.string().trim().optional(),
    branch: z.string().trim().optional(),
    attempts: z.number().int().min(1).max(4).default(1),
  }),
  output: z.object({ url: z.string() }),
});
