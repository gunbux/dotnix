import { useAgent, type PluginAgentPanelProps } from '@getpaseo/plugin/client';
import { useState } from 'react';
import { ScrollView, Text, View } from 'react-native';
import { addGroup, assignThread, type Groups } from '../shared/groups';
import { useGroups } from './use-groups';
import { Button, Field, Note, Row } from './ui';

type Draft = { doc: Groups; revision: string; ids: string[] };
export function AssignmentPanel(props: PluginAgentPanelProps) {
  return <AssignmentEditor key={`${props.host.id}:${props.agentId}`} {...props} />;
}

function AssignmentEditor({ theme, layout, agentId }: PluginAgentPanelProps) {
  const agent = useAgent(agentId, a => ({ title: a.title }));
  const { settings, save, reload, pending, error } = useGroups();
  const [draft, setDraft] = useState<Draft | null>(null);
  const [name, setName] = useState('');
  const root = { flex: 1, backgroundColor: theme.colors.surface0 };
  const content = { padding: layout.compact ? 16 : 24, gap: 16 };
  if (settings.status !== 'ready') return <ScrollView style={root} contentContainerStyle={content}>
    <Note theme={theme}>{settings.status === 'loading' ? 'Loading groups…' : settings.error}</Note>
    {settings.status !== 'loading' && <Button theme={theme} onPress={() => void reload()}>Reload groups</Button>}
  </ScrollView>;
  const current = draft ?? { doc: settings.values, revision: settings.revision,
    ids: settings.values.groups.filter(g => g.agentIds.includes(agentId)).map(g => g.id) };
  function toggle(id: string) {
    setDraft({ ...current, ids: current.ids.includes(id) ? current.ids.filter(g => g !== id) : [...current.ids, id] });
  }
  async function commit() {
    if (await save(() => {
      let doc = current.doc;
      let ids = current.ids;
      if (name.trim()) {
        const id = `group-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
        doc = addGroup(doc, id, name); ids = [...ids, id];
      }
      return assignThread(doc, agentId, ids);
    }, current.revision)) { setDraft(null); setName(''); }
  }
  return <ScrollView style={root} contentContainerStyle={content}>
    <Text style={{ color: theme.colors.foreground, fontSize: 22, fontWeight: '600' }}>Assign to groups</Text>
    <Note theme={theme}>{agent?.title || 'This thread'}</Note>
    <Note theme={theme}>Choose any number of feature groups. This won’t move the thread.</Note>
    {error && <View accessibilityRole="alert"><Note theme={theme}>{error}</Note>
      <Note theme={theme}>Cancel your edit and reload if another client changed these groups.</Note></View>}
    {!current.doc.groups.length && <Note theme={theme}>Create your first group below.</Note>}
    {current.doc.groups.map(g => <Button key={g.id} theme={theme} selected={current.ids.includes(g.id)} disabled={pending}
      onPress={() => toggle(g.id)}>{`${current.ids.includes(g.id) ? '✓ ' : ''}${g.name}`}</Button>)}
    <Field theme={theme} value={name} label="Create and assign a new group (optional)" disabled={pending}
      onChange={value => { if (!draft) setDraft(current); setName(value); }} />
    <Row>
      <Button theme={theme} selected disabled={pending || (!draft && !name.trim())} onPress={() => void commit()}>{pending ? 'Saving…' : 'Save groups'}</Button>
      <Button theme={theme} disabled={pending} onPress={() => { setDraft(null); setName(''); void reload(); }}>Cancel and reload</Button>
    </Row>
    {!draft && !name && !error && <Note theme={theme}>Membership is saved on this host and shared with its connected clients.</Note>}
  </ScrollView>;
}
