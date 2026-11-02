import { defineSettings } from '@getpaseo/plugin';
import { z } from 'zod';

export const DEFAULT_TOPICS = ['Nix', 'Paseo', 'Travel', 'Finance', 'Misc'];
export const MODELS = ['haiku', 'sonnet'] as const;

export const settingsSchema = z.object({
  enabled: z.boolean().default(true),
  // Labels the classifier should prefer, alongside every existing workspace label.
  topics: z.array(z.string()).default(DEFAULT_TOPICS),
  allowNew: z.boolean().default(true),
  model: z.enum(MODELS).default('haiku'),
});
export type Settings = z.infer<typeof settingsSchema>;

export const autoLabel = defineSettings({
  id: 'auto-label', scope: 'host', version: 1, schema: settingsSchema,
});
