import { defineRpc } from '@getpaseo/plugin';
import { z } from 'zod';

export const bridgeStatus = defineRpc({
  name: 'bridge.status', input: z.object({}),
  output: z.object({ status: z.string(), bot: z.string().nullable(), selectedAgent: z.string().nullable(), queued: z.number() }),
});
