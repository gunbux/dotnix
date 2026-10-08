import type { PluginClientContext } from '@getpaseo/plugin/client';
import { SettingsScreen } from './client/settings-screen';
import { archiveStale, previewStale } from './shared/rpc';

export default function contribute(client: PluginClientContext) {
  // Hands the daemon side a session so its hourly sweep can start without waiting for a turn.
  client.rpc(previewStale, {}).catch(() => {});
  client.addSettingsScreen({ id: 'settings', title: 'Auto archive', icon: 'Archive', Component: SettingsScreen });
  client.addCommandCenterItem({ id: 'archive-idle', title: 'Archive idle workspaces now', icon: 'Archive', context: 'global',
    keywords: ['archive', 'idle', 'stale', 'cleanup'], async onSelect({ rpc }) { await rpc(archiveStale, {}); } });
  client.addCommandCenterItem({ id: 'settings', title: 'Auto archive settings', icon: 'Archive', context: 'global',
    keywords: ['archive', 'idle'], onSelect({ openSettings }) { openSettings('settings'); } });
  return () => {};
}
