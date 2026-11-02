import type { PluginClientContext } from '@getpaseo/plugin/client';
import { SettingsScreen } from './client/settings-screen';
import { labelUnlabelled } from './shared/rpc';

export default function contribute(client: PluginClientContext) {
  client.addSettingsScreen({ id: 'settings', title: 'Auto label', icon: 'Tags', Component: SettingsScreen });
  client.addCommandCenterItem({ id: 'label-unlabelled', title: 'Label unlabelled workspaces', icon: 'Tags', context: 'global',
    keywords: ['label', 'topic', 'classify'], async onSelect({ rpc }) { await rpc(labelUnlabelled, {}); } });
  client.addCommandCenterItem({ id: 'settings', title: 'Auto label settings', icon: 'Tags', context: 'global',
    keywords: ['label', 'topic'], onSelect({ openSettings }) { openSettings('settings'); } });
  return () => {};
}
