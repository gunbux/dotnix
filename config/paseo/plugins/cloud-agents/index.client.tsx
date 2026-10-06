import type { PluginClientContext } from '@getpaseo/plugin/client';
import { codexSubmit } from './shared/rpc.ts';
import { ControlScreen } from './client/control-screen.tsx';
import { SettingsScreen } from './client/settings-screen.tsx';

export default function contribute(client: PluginClientContext) {
  client.addSurface('cloud', ControlScreen);
  client.addSidebarItem({ id: 'cloud', title: 'Cloud agents', icon: 'Cloud', surface: 'cloud' });
  client.addSettingsScreen({ id: 'settings', title: 'Cloud agents', icon: 'Cloud', Component: SettingsScreen });
  client.addCommandCenterItem({ id: 'cloud', title: 'Open cloud agents', icon: 'Cloud', context: 'global',
    keywords: ['claude', 'codex', 'remote', 'managed agents', 'tasks'], onSelect({ openSurface }) { openSurface('cloud'); } });
  client.addCommandCenterItem({ id: 'settings', title: 'Cloud agents settings', icon: 'Settings', context: 'global',
    keywords: ['claude', 'codex', 'api key'], onSelect({ openSettings }) { openSettings('settings'); } });
  client.addSlashCommand({ name: 'codex-cloud', description: 'Send a task to Codex Cloud from this workspace',
    argumentHint: '<task>', context: 'agent',
    async onSubmit({ args, workspace, rpc, openSurface }) {
      if (!args) throw new Error('Usage: /codex-cloud <task description>');
      await rpc(codexSubmit, { prompt: args, cwd: workspace.directory });
      openSurface('cloud');
    } });
  return () => {};
}
