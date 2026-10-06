import { openExternalUrl, useRpc, type PluginSurfaceProps } from '@getpaseo/plugin/client';
import { useState } from 'react';
import { ScrollView, Text, TextInput, View } from 'react-native';
import { claudeSessionAction, codexApply, codexDiff, codexSubmit, type ClaudeSession, type CodexTask } from '../shared/rpc.ts';
import { useClaudeSessions, useClaudeStatus, useCodexTasks, useWorkspaces, type WorkspaceOption } from './queries.ts';
import { Alert, Button, Card, errorText, Field, Heading, Mono, Note, Row, type Theme } from './ui.tsx';

const DIFF_PREVIEW_LINES = 400;

export function ControlScreen(props: PluginSurfaceProps) {
  return <Control key={props.host.id} {...props} />;
}

function Control({ theme, layout, host }: PluginSurfaceProps) {
  const [tab, setTab] = useState<'claude' | 'codex'>('claude');
  return <ScrollView style={{ flex: 1, backgroundColor: theme.colors.surface0 }}
    contentContainerStyle={{ padding: layout.compact ? 16 : 24, gap: 16 }}>
    <Text style={{ fontSize: 24, fontWeight: '600', color: theme.colors.foreground }}>Cloud agents</Text>
    <Note theme={theme}>Remote Claude and Codex work driven from {host.label}.</Note>
    <Row>
      <Button theme={theme} selected={tab === 'claude'} onPress={() => setTab('claude')}>Claude</Button>
      <Button theme={theme} selected={tab === 'codex'} onPress={() => setTab('codex')}>Codex Cloud</Button>
    </Row>
    {tab === 'claude' ? <ClaudeTab theme={theme} /> : <CodexTab theme={theme} hostId={host.id} />}
  </ScrollView>;
}

function relative(iso: string): string {
  const seconds = Math.round((Date.now() - Date.parse(iso)) / 1000);
  if (!Number.isFinite(seconds)) return iso;
  if (seconds < 60) return 'just now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
}

function ClaudeTab({ theme }: { theme: Theme }) {
  const status = useClaudeStatus();
  const [archived, setArchived] = useState(false);
  const sessions = useClaudeSessions(Boolean(status.data?.configured), archived);
  if (status.isLoading) return <Note theme={theme}>Checking Claude configuration…</Note>;
  if (status.error) return <Alert theme={theme}>{errorText(status.error)}</Alert>;
  if (!status.data?.configured) return <Card theme={theme}>
    <Heading theme={theme}>Connect Claude Managed Agents</Heading>
    <Note theme={theme}>{status.data?.detail}</Note>
    <Note theme={theme}>Give the daemon an Anthropic API key through ANTHROPIC_API_KEY or the key file named under
      Settings → Plugins → Cloud agents, then reload.</Note>
    <Button theme={theme} onPress={() => void status.refetch()}>Check again</Button>
  </Card>;
  return <View style={{ gap: 12 }}>
    <Card theme={theme}>
      <Heading theme={theme}>Chat</Heading>
      <Note theme={theme}>Start a new agent in any workspace and choose the Claude (cloud) provider. Its model list holds your
        managed agents and its mode list holds your environments. Existing cloud sessions appear in the provider's import list.</Note>
    </Card>
    <Row>
      <Heading theme={theme}>Sessions</Heading>
      <Button theme={theme} selected={archived} onPress={() => setArchived(!archived)}>{archived ? '✓ Showing archived' : 'Show archived'}</Button>
      <Button theme={theme} disabled={sessions.isFetching} onPress={() => void sessions.refetch()}>Refresh</Button>
    </Row>
    {sessions.error && <Alert theme={theme}>{errorText(sessions.error)}</Alert>}
    {sessions.isLoading && <Note theme={theme}>Loading sessions…</Note>}
    {sessions.data && !sessions.data.sessions.length && <Note theme={theme}>No sessions yet.</Note>}
    {sessions.data?.sessions.map(s => <ClaudeSessionCard key={s.id} theme={theme} session={s} onChange={() => void sessions.refetch()} />)}
  </View>;
}

function ClaudeSessionCard({ theme, session, onChange }: { theme: Theme; session: ClaudeSession; onChange(): void }) {
  const act = useRpc(claudeSessionAction);
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function run(action: 'archive' | 'interrupt') {
    setBusy(true); setError(null);
    try { await act({ sessionId: session.id, action }); onChange(); }
    catch (err) { setError(errorText(err)); }
    finally { setBusy(false); setConfirm(false); }
  }
  const cost = session.costUsd === null ? '' : ` · $${session.costUsd.toFixed(2)}`;
  return <Card theme={theme}>
    <Text style={{ color: theme.colors.foreground, fontWeight: '600' }}>{session.title || 'Untitled session'}</Text>
    <Note theme={theme}>{`${session.status}${session.archived ? ' (archived)' : ''} · ${session.agentName} · ${session.model} · ${relative(session.updatedAt)}${cost}`}</Note>
    <Mono theme={theme}>{session.id}</Mono>
    {error && <Alert theme={theme}>{error}</Alert>}
    <Row>
      {session.status === 'running' && <Button theme={theme} disabled={busy} onPress={() => void run('interrupt')}>Interrupt</Button>}
      {!session.archived && (confirm
        ? <><Button theme={theme} danger disabled={busy} onPress={() => void run('archive')}>Confirm archive</Button>
          <Button theme={theme} disabled={busy} onPress={() => setConfirm(false)}>Keep</Button></>
        : <Button theme={theme} disabled={busy} onPress={() => setConfirm(true)}>Archive</Button>)}
    </Row>
  </Card>;
}

function CodexTab({ theme, hostId }: { theme: Theme; hostId: string }) {
  const [filter, setFilter] = useState('');
  const [applied, setApplied] = useState('');
  const tasks = useCodexTasks(applied);
  const workspaces = useWorkspaces(hostId);
  const [target, setTarget] = useState<WorkspaceOption | null>(null);
  return <View style={{ gap: 12 }}>
    <WorkspacePicker theme={theme} options={workspaces.data ?? []} loading={workspaces.isLoading}
      error={workspaces.error ? errorText(workspaces.error) : null} value={target} onChange={setTarget} />
    <SubmitCard theme={theme} target={target} onSubmitted={() => void tasks.refetch()} />
    <Heading theme={theme}>Tasks</Heading>
    <Row>
      <View style={{ flexGrow: 1, minWidth: 200 }}><Field theme={theme} value={filter} onChange={setFilter} label="Filter by environment id or label" /></View>
      <Button theme={theme} onPress={() => setApplied(filter.trim())}>Filter</Button>
      <Button theme={theme} disabled={tasks.isFetching} onPress={() => void tasks.refetch()}>Refresh</Button>
    </Row>
    {tasks.error && <Alert theme={theme}>{errorText(tasks.error)}</Alert>}
    {tasks.isLoading && <Note theme={theme}>Loading Codex Cloud tasks…</Note>}
    {tasks.data && !tasks.data.tasks.length && <Note theme={theme}>No tasks found.</Note>}
    {tasks.data?.tasks.map(t => <CodexTaskCard key={t.id} theme={theme} task={t} target={target} />)}
  </View>;
}

function WorkspacePicker({ theme, options, loading, error, value, onChange }: {
  theme: Theme; options: WorkspaceOption[]; loading: boolean; error: string | null;
  value: WorkspaceOption | null; onChange(value: WorkspaceOption): void;
}) {
  const [open, setOpen] = useState(false);
  return <Card theme={theme}>
    <Heading theme={theme}>Local workspace</Heading>
    <Note theme={theme}>New tasks use this checkout's branch; Apply writes the diff into it.</Note>
    <Row>
      <Text style={{ color: theme.colors.foreground }}>{value ? value.label : 'None selected'}</Text>
      <Button theme={theme} onPress={() => setOpen(!open)}>{open ? 'Close' : 'Choose'}</Button>
    </Row>
    {value && <Mono theme={theme}>{value.directory}</Mono>}
    {error && <Alert theme={theme}>{error}</Alert>}
    {open && (loading ? <Note theme={theme}>Loading workspaces…</Note> : options.map(o =>
      <Button key={o.id} theme={theme} selected={o.id === value?.id} onPress={() => { onChange(o); setOpen(false); }}>{o.label}</Button>))}
  </Card>;
}

function SubmitCard({ theme, target, onSubmitted }: { theme: Theme; target: WorkspaceOption | null; onSubmitted(): void }) {
  const submit = useRpc(codexSubmit);
  const [prompt, setPrompt] = useState('');
  const [environment, setEnvironment] = useState('');
  const [branch, setBranch] = useState('');
  const [attempts, setAttempts] = useState(1);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{ url?: string; error?: string } | null>(null);
  async function send() {
    if (!target) return;
    setBusy(true); setResult(null);
    try {
      const { url } = await submit({ prompt, cwd: target.directory, attempts,
        ...(environment.trim() ? { environment: environment.trim() } : {}), ...(branch.trim() ? { branch: branch.trim() } : {}) });
      setResult({ url }); setPrompt(''); onSubmitted();
    } catch (err) { setResult({ error: errorText(err) }); }
    finally { setBusy(false); }
  }
  return <Card theme={theme}>
    <Heading theme={theme}>New Codex Cloud task</Heading>
    <TextInput accessibilityLabel="Task prompt" placeholder="Describe the task" placeholderTextColor={theme.colors.foregroundMuted}
      value={prompt} onChangeText={setPrompt} multiline editable={!busy}
      style={{ minHeight: 96, borderWidth: 1, borderColor: theme.colors.border, borderRadius: 8, padding: 12,
        color: theme.colors.foreground, backgroundColor: theme.colors.surface0, textAlignVertical: 'top' }} />
    <Field theme={theme} value={environment} onChange={setEnvironment} label="Environment (blank uses the default)" disabled={busy} />
    <Field theme={theme} value={branch} onChange={setBranch} label="Branch (blank uses the checkout's branch)" disabled={busy} />
    <Row>
      <Note theme={theme}>Attempts</Note>
      {[1, 2, 3, 4].map(n => <Button key={n} theme={theme} selected={attempts === n} disabled={busy} onPress={() => setAttempts(n)}>{String(n)}</Button>)}
    </Row>
    {!target && <Note theme={theme}>Choose a local workspace first.</Note>}
    <Button theme={theme} selected disabled={busy || !target || !prompt.trim()} onPress={() => void send()}>{busy ? 'Submitting…' : 'Submit task'}</Button>
    {result?.error && <Alert theme={theme}>{result.error}</Alert>}
    {result?.url && <Row>
      <Note theme={theme}>Submitted.</Note>
      <Button theme={theme} onPress={() => void openExternalUrl(result.url!)}>Open in browser</Button>
    </Row>}
  </Card>;
}

function CodexTaskCard({ theme, task, target }: { theme: Theme; task: CodexTask; target: WorkspaceOption | null }) {
  const fetchDiff = useRpc(codexDiff);
  const apply = useRpc(codexApply);
  const [attempt, setAttempt] = useState(1);
  const [diff, setDiff] = useState<string | null>(null);
  const [full, setFull] = useState(false);
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);
  const attempts = task.attempt_total ?? 1;
  const ready = task.status === 'ready';
  async function toggleDiff() {
    if (diff !== null) { setDiff(null); return; }
    setBusy(true); setMessage(null);
    try { setDiff((await fetchDiff({ taskId: task.id, attempt })).diff); }
    catch (err) { setMessage({ ok: false, text: errorText(err) }); }
    finally { setBusy(false); }
  }
  async function runApply() {
    if (!target) return;
    setBusy(true); setMessage(null);
    try { const r = await apply({ taskId: task.id, cwd: target.directory, attempt }); setMessage({ ok: r.ok, text: r.message }); }
    catch (err) { setMessage({ ok: false, text: errorText(err) }); }
    finally { setBusy(false); setConfirm(false); }
  }
  const s = task.summary;
  const stats = s && s.files_changed ? ` · +${s.lines_added ?? 0} −${s.lines_removed ?? 0} in ${s.files_changed} files` : '';
  const lines = diff?.split('\n') ?? [];
  return <Card theme={theme}>
    <Text style={{ color: theme.colors.foreground, fontWeight: '600' }}>{task.title}</Text>
    <Note theme={theme}>{`${task.status} · ${task.environment_label || task.environment_id || 'no environment'} · ${relative(task.updated_at)}${stats}`}</Note>
    {attempts > 1 && <Row>
      <Note theme={theme}>Attempt</Note>
      {Array.from({ length: attempts }, (_, i) => i + 1).map(n =>
        <Button key={n} theme={theme} selected={attempt === n} disabled={busy} onPress={() => { setAttempt(n); setDiff(null); }}>{String(n)}</Button>)}
    </Row>}
    <Row>
      <Button theme={theme} onPress={() => void openExternalUrl(task.url)}>Open</Button>
      {ready && <Button theme={theme} disabled={busy} onPress={() => void toggleDiff()}>{diff === null ? 'View diff' : 'Hide diff'}</Button>}
      {ready && (confirm
        ? <><Button theme={theme} danger disabled={busy} onPress={() => void runApply()}>{`Apply to ${target?.label}`}</Button>
          <Button theme={theme} disabled={busy} onPress={() => setConfirm(false)}>Cancel</Button></>
        : <Button theme={theme} disabled={busy || !target} onPress={() => setConfirm(true)}>Apply locally</Button>)}
    </Row>
    {ready && !target && <Note theme={theme}>Choose a local workspace to apply this task.</Note>}
    {message && (message.ok ? <Note theme={theme}>{message.text}</Note> : <Alert theme={theme}>{message.text}</Alert>)}
    {diff !== null && <View style={{ gap: 8 }}>
      <ScrollView horizontal><Mono theme={theme}>{(full ? lines : lines.slice(0, DIFF_PREVIEW_LINES)).join('\n') || '(empty diff)'}</Mono></ScrollView>
      {lines.length > DIFF_PREVIEW_LINES && !full &&
        <Button theme={theme} onPress={() => setFull(true)}>{`Show all ${lines.length} lines`}</Button>}
    </View>}
  </Card>;
}
