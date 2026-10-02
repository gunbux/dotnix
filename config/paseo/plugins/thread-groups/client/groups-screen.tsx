import type { PluginSurfaceProps } from '@getpaseo/plugin/client';
import { useState } from 'react';
import { ScrollView, Text, View } from 'react-native';
import { addGroup, deleteGroup, renameGroup, setMembers, type Groups } from '../shared/groups';
import { visibleThreads } from './catalog';
import { useCatalog } from './use-catalog';
import { useGroups } from './use-groups';
import { Button, Field, Note, Row } from './ui';

type Edit = { kind: 'members' | 'rename' | 'delete'; groupId: string; doc: Groups; revision: string; members: string[]; name: string };

export function GroupsScreen(props: PluginSurfaceProps) {
  return <GroupsEditor key={props.host.id} {...props} />;
}

function GroupsEditor({ theme, layout, host, navigation }: PluginSurfaceProps) {
  const { settings, save, reload, pending, error } = useGroups();
  const catalog = useCatalog(host.id);
  const [selected, setSelected] = useState('all');
  const [search, setSearch] = useState('');
  const [workspace, setWorkspace] = useState('');
  const [name, setName] = useState('');
  const [edit, setEdit] = useState<Edit | null>(null);
  const root = { flex: 1, backgroundColor: theme.colors.surface0 };
  const content = { padding: layout.compact ? 16 : 24, gap: 16 };
  if (settings.status !== 'ready') return <ScrollView style={root} contentContainerStyle={content}>
    <Note theme={theme}>{settings.status === 'loading' ? 'Loading groups…' : settings.error}</Note>
    {settings.status !== 'loading' && <Button theme={theme} onPress={() => void reload()}>Reload groups</Button>}
  </ScrollView>;

  const doc = settings.values;
  const group = doc.groups.find(g => g.id === selected);
  const view = group ? selected : selected === 'ungrouped' ? 'ungrouped' : 'all';
  const threads = catalog.data?.threads ?? [];
  const visible = visibleThreads(threads, doc.groups, edit?.kind === 'members' ? 'all' : view, search, workspace);
  const missing = (group?.agentIds ?? []).filter(id => !threads.some(t => t.id === id));

  function begin(kind: Edit['kind']) {
    if (!group) return;
    setEdit({ kind, groupId: group.id, doc, revision: settings.status === 'ready' ? settings.revision : '',
      members: [...group.agentIds], name: group.name });
  }
  async function create() {
    if (settings.status !== 'ready') return;
    const id = `group-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
    if (await save(() => addGroup(settings.values, id, name), settings.revision)) {
      setName(''); setSelected(id); void catalog.refetch();
    }
  }
  async function commit() {
    if (!edit) return;
    const success = await save(() => edit.kind === 'members' ? setMembers(edit.doc, edit.groupId, edit.members)
      : edit.kind === 'rename' ? renameGroup(edit.doc, edit.groupId, edit.name) : deleteGroup(edit.doc, edit.groupId), edit.revision);
    if (success) { if (edit.kind === 'delete') setSelected('all'); setEdit(null); void catalog.refetch(); }
  }
  return <ScrollView style={root} contentContainerStyle={content}>
    <Text style={{ fontSize: 24, fontWeight: '600', color: theme.colors.foreground }}>Thread groups</Text>
    <Note theme={theme}>Organize features across workspaces on {host.label}. Threads stay in their original workspace.</Note>
    {error && <View accessibilityRole="alert" style={{ gap: 8 }}>
      <Note theme={theme}>{error}</Note>
      <Note theme={theme}>If another client changed the groups, cancel this edit, reload, and try again.</Note>
      <Button theme={theme} disabled={pending} onPress={() => void reload()}>Reload groups</Button>
    </View>}
    <Row>
      <Button theme={theme} selected={view === 'all'} disabled={pending || Boolean(edit)} onPress={() => setSelected('all')}>All threads</Button>
      <Button theme={theme} selected={view === 'ungrouped'} disabled={pending || Boolean(edit)} onPress={() => setSelected('ungrouped')}>Ungrouped</Button>
      {doc.groups.map(g => <Button key={g.id} theme={theme} selected={view === g.id} disabled={pending || Boolean(edit)}
        onPress={() => setSelected(g.id)}>{`${g.name} (${g.agentIds.length})`}</Button>)}
    </Row>
    {!edit && <View style={{ gap: 8 }}>
      <Field theme={theme} value={name} onChange={setName} label="New group name" disabled={pending} />
      <Row><Button theme={theme} disabled={pending || !name.trim()} onPress={() => void create()}>Create group</Button></Row>
    </View>}
    {group && !edit && <Row>
      <Button theme={theme} disabled={pending || catalog.isPending || catalog.isError} onPress={() => begin('members')}>Add or remove threads</Button>
      <Button theme={theme} disabled={pending} onPress={() => begin('rename')}>Rename group</Button>
      <Button theme={theme} disabled={pending} onPress={() => begin('delete')}>Delete group</Button>
    </Row>}
    {edit && <View style={{ gap: 10 }}>
      <Text style={{ color: theme.colors.foreground, fontSize: 18, fontWeight: '600' }}>
        {edit.kind === 'members' ? `Choose threads for ${edit.name}` : edit.kind === 'rename' ? 'Rename group' : `Delete ${edit.name}?`}
      </Text>
      {edit.kind === 'rename' && <Field theme={theme} value={edit.name} disabled={pending} label="Group name" onChange={name => setEdit({ ...edit, name })} />}
      {edit.kind === 'delete' && <Note theme={theme}>Only this group will be removed. Its threads and other groups will remain.</Note>}
      <Row>
        <Button theme={theme} selected={edit.kind !== 'delete'} disabled={pending} danger={edit.kind === 'delete'} onPress={() => void commit()}>
          {pending ? 'Saving…' : edit.kind === 'delete' ? 'Confirm delete group' : 'Save changes'}
        </Button>
        <Button theme={theme} disabled={pending} onPress={() => { setEdit(null); void reload(); }}>Cancel</Button>
      </Row>
    </View>}
    {(!edit || edit.kind === 'members') && <>
      <Field theme={theme} value={search} onChange={setSearch} label="Search threads or workspaces" />
      <ScrollView horizontal contentContainerStyle={{ gap: 8 }}>
        <Button theme={theme} selected={!workspace} onPress={() => setWorkspace('')}>All workspaces</Button>
        {catalog.data?.workspaces.map(([id, title]) => <Button key={id} theme={theme} selected={workspace === id} onPress={() => setWorkspace(id)}>{title}</Button>)}
      </ScrollView>
      {catalog.isPending && <Note theme={theme}>Loading threads…</Note>}
      {catalog.isError && <View style={{ gap: 8 }}><Note theme={theme}>Could not load threads: {catalog.error.message}</Note>
        <Button theme={theme} onPress={() => void catalog.refetch()}>Retry</Button></View>}
      {!navigation && <Note theme={theme}>Update your Paseo client to open threads from this screen.</Note>}
      {!catalog.isPending && !catalog.isError && !visible.length && <Note theme={theme}>
        {view === 'ungrouped' ? 'No ungrouped threads match these filters.' : group ? 'No threads match. Use Add or remove threads to fill this group.' : 'No threads match these filters.'}
      </Note>}
      {visible.map(thread => <View key={thread.id} style={{ padding: 14, borderRadius: 10, gap: 6,
        borderWidth: 1, borderColor: theme.colors.border, backgroundColor: theme.colors.surface1 }}>
        <Text style={{ color: theme.colors.foreground, fontWeight: '600' }}>{thread.title}</Text>
        <Note theme={theme}>{thread.workspaceName} · {thread.archived ? 'archived' : thread.status}</Note>
        <Row>{edit?.kind === 'members'
          ? <Button theme={theme} selected={edit.members.includes(thread.id)} disabled={pending} onPress={() => setEdit({ ...edit,
            members: edit.members.includes(thread.id) ? edit.members.filter(id => id !== thread.id) : [...edit.members, thread.id] })}>
            {edit.members.includes(thread.id) ? 'Selected' : 'Add to group'}
          </Button>
          : <Button theme={theme} disabled={!navigation} onPress={() => navigation?.openAgent({ agentId: thread.id })}>Open thread</Button>}
        </Row>
      </View>)}
      {!catalog.isPending && !catalog.isError && missing.length > 0 && <Note theme={theme}>
        {`${missing.length} saved thread reference(s) are unavailable on this host. Their membership is preserved.`}
      </Note>}
    </>}
  </ScrollView>;
}
