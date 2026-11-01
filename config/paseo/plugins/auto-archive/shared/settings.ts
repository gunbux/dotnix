import { defineSettings } from '@getpaseo/plugin';
import { z } from 'zod';

export const DEFAULT_DAYS = 4;
export const MAX_DAYS = 365;
export const DEFAULT_QUICK_CHAT_LABEL = 'Quick chat, Glance';
export const DEFAULT_QUICK_CHAT_HOURS = 12;

export const settingsSchema = z.object({
  enabled: z.boolean().default(true),
  // Days since the workspace's last activity before it is archived.
  days: z.number().positive().max(MAX_DAYS).default(DEFAULT_DAYS),
  keepPinned: z.boolean().default(true),
  // Archiving the last workspace on a managed worktree removes the worktree.
  keepUncommitted: z.boolean().default(true),
  // Workspaces with any of these comma-separated labels (the Vicinae Paseo extension's
  // quick chats, glance's ask-about-screen chats) use the hour threshold below instead
  // of days. An empty label or 0 hours turns this off.
  quickChatLabel: z.string().default(DEFAULT_QUICK_CHAT_LABEL),
  quickChatHours: z.number().min(0).max(MAX_DAYS * 24).default(DEFAULT_QUICK_CHAT_HOURS),
});
export type Settings = z.infer<typeof settingsSchema>;

export const autoArchive = defineSettings({
  id: 'auto-archive', scope: 'host', version: 1, schema: settingsSchema,
});

/** The quick chat labels in a comma-separated setting. */
export const quickChatLabels = (setting: string) => setting.split(',').map(label => label.trim()).filter(Boolean);
