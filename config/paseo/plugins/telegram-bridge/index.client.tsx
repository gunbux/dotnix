import type { PluginClientContext } from '@getpaseo/plugin/client';
import { SettingsScreen } from './client/settings-screen.tsx';

export default function contribute(client: PluginClientContext) {
  client.addSettingsScreen({ id: 'settings', title: 'Telegram bridge', icon: 'Send', Component: SettingsScreen });
  client.addCommandCenterItem({
    id: 'settings', title: 'Telegram bridge settings', icon: 'Send', context: 'global',
    keywords: ['telegram', 'bot', 'bridge'], onSelect({ openSettings }) { openSettings('settings'); },
  });
  return () => {};
}
