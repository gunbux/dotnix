import { defineRpc } from '@getpaseo/plugin';
import { z } from 'zod';

export const labelUnlabelled = defineRpc({
  name: 'workspaces.label-unlabelled',
  input: z.object({}),
  output: z.object({ queued: z.number() }),
});
