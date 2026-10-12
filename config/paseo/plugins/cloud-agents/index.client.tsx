import type { PluginClientContext, PluginSidebarItemProps } from '@getpaseo/plugin/client';
import { SidebarRow } from '@getpaseo/plugin/client/ui';
import { codexSubmit } from './shared/rpc.ts';
import { ControlScreen } from './client/control-screen.tsx';
import { SettingsScreen } from './client/settings-screen.tsx';

function CloudItem({ currentScreen, openScreen }: PluginSidebarItemProps) {
  return <SidebarRow icon="Cloud" active={currentScreen?.screenId === 'cloud'}
    onPress={() => openScreen({ screenId: 'cloud' })} />;
}

export default function contribute(client: PluginClientContext) {
  client.addScreen({ id: 'cloud', title: 'Cloud agents', Component: ControlScreen });
  client.addSidebarHeaderItem({ id: 'cloud', title: 'Cloud agents', Component: CloudItem });
  client.addSettingsScreen({ id: 'settings', title: 'Cloud agents', icon: 'Cloud', Component: SettingsScreen });
  client.addCommandCenterItem({ id: 'cloud', title: 'Open cloud agents', icon: 'Cloud', context: 'global',
    keywords: ['claude', 'codex', 'remote', 'managed agents', 'tasks'], onSelect({ openScreen }) { openScreen({ screenId: 'cloud' }); } });
  client.addCommandCenterItem({ id: 'settings', title: 'Cloud agents settings', icon: 'Settings', context: 'global',
    keywords: ['claude', 'codex', 'api key'], onSelect({ openSettings }) { openSettings('settings'); } });
  client.addSlashCommand({ name: 'codex-cloud', description: 'Send a task to Codex Cloud from this workspace',
    argumentHint: '<task>', context: 'agent',
    async onSubmit({ args, workspace, rpc, openScreen }) {
      if (!args) throw new Error('Usage: /codex-cloud <task description>');
      await rpc(codexSubmit, { prompt: args, cwd: workspace.directory });
      openScreen({ screenId: 'cloud' });
    } });
  return () => {};
}
