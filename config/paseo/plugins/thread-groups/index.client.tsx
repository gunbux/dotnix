import type { PluginClientContext } from '@getpaseo/plugin/client';
import { GroupsScreen } from './client/groups-screen';
import { AssignmentPanel } from './client/assignment-panel';

export default function contribute(client: PluginClientContext) {
  client.addSurface('groups', GroupsScreen);
  client.addSidebarItem({ id: 'groups', title: 'Thread groups', icon: 'FolderOpen', surface: 'groups' });
  client.addWorkspacePanel({ id: 'assign', title: 'Assign to groups', icon: 'FolderPlus', context: 'agent', Component: AssignmentPanel });
  client.addCommandCenterItem({ id: 'groups', title: 'Open thread groups', icon: 'FolderOpen', context: 'global',
    keywords: ['feature', 'folder', 'threads'], onSelect({ openSurface }) { openSurface('groups'); } });
  client.addCommandCenterItem({ id: 'assign', title: 'Assign thread to groups', icon: 'FolderPlus', context: 'agent',
    keywords: ['feature', 'folder'], onSelect({ openPanel }) { openPanel('assign'); } });
  client.addSlashCommand({ name: 'thread-groups', description: 'Assign this thread to feature groups', argumentHint: '', context: 'agent',
    onSubmit({ openPanel }) { openPanel('assign'); } });
  return () => {};
}
