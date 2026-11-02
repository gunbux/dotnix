import { defineRpc } from '@getpaseo/plugin';
import { z } from 'zod';

const candidate = z.object({ id: z.string(), title: z.string(), idleDays: z.number() });
export type Candidate = z.infer<typeof candidate>;

export const previewStale = defineRpc({
  name: 'workspaces.auto-archive.preview',
  input: z.object({}),
  output: z.object({
    candidates: z.array(candidate),
    lastSweep: z.object({ at: z.string(), archived: z.number(), failed: z.number() }).nullable(),
  }),
});

export const archiveStale = defineRpc({
  name: 'workspaces.auto-archive.run',
  input: z.object({}),
  output: z.object({ archived: z.array(candidate), failed: z.number() }),
});
