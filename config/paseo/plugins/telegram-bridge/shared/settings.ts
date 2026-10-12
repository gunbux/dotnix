import { defineSettings } from '@getpaseo/plugin';
import { z } from 'zod';

export const configSchema = z.object({
  enabled: z.boolean().default(false),
  ownerId: z.string().regex(/^(?:[1-9]\d{0,15})?$/, 'Enter a positive numeric Telegram user ID.').default(''),
  tokenFile: z.string().default(''),
  defaultProvider: z.string().default(''),
});
export type Config = z.infer<typeof configSchema>;
export const bridgeSettings = defineSettings({ id: 'telegram-bridge', scope: 'host', version: 1, schema: configSchema });
