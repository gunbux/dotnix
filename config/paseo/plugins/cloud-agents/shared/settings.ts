import { defineSettings } from '@getpaseo/plugin';
import { z } from 'zod';

export const configSchema = z.object({
  claude: z.object({
    // A path, never the key itself: settings are readable by every connected client.
    apiKeyFile: z.string().trim().max(400).default('/run/secrets/anthropic_api_key'),
    baseUrl: z.string().trim().url().default('https://api.anthropic.com'),
    defaultAgentId: z.string().trim().max(200).default(''),
    defaultEnvironmentId: z.string().trim().max(200).default(''),
  }).prefault({}),
  codex: z.object({
    binary: z.string().trim().min(1).max(400).default('codex'),
    defaultEnvironment: z.string().trim().max(200).default(''),
  }).prefault({}),
});
export type Config = z.infer<typeof configSchema>;

export const cloudConfig = defineSettings({
  id: 'config', scope: 'host', version: 1, schema: configSchema,
});
