import { useSettings, type PluginSurfaceProps } from '@getpaseo/plugin/client';
import { SettingsAction, SettingsCard, SettingsInput, SettingsRow, SettingsSection } from '@getpaseo/plugin/client/ui';
import { useState } from 'react';
import { Text, View } from 'react-native';
import { cloudConfig, configSchema, type Config } from '../shared/settings.ts';
import { useClaudeStatus } from './queries.ts';

export function SettingsScreen(props: PluginSurfaceProps) {
  const settings = useSettings(cloudConfig);
  if (settings.status === 'loading') return <Text style={{ color: props.theme.colors.foregroundMuted }}>Loading…</Text>;
  if (settings.status !== 'ready') return <View style={{ gap: 8 }}>
    <Text style={{ color: props.theme.colors.statusDanger }}>{settings.error}</Text>
    <SettingsCard><SettingsAction label="Settings" actionLabel="Reset to defaults" onPress={() => void settings.reset()} /></SettingsCard>
  </View>;
  return <Editor key={settings.revision} {...props} values={settings.values} revision={settings.revision}
    saving={settings.saving} saveError={settings.saveError} save={settings.save} />;
}

function Editor({ theme, values, revision, saving, saveError, save }: PluginSurfaceProps & {
  values: Config; revision: string; saving: boolean; saveError: string | null;
  save(values: Config, revision: string): Promise<boolean>;
}) {
  const [draft, setDraft] = useState(values);
  const [invalid, setInvalid] = useState<string | null>(null);
  const status = useClaudeStatus();
  const set = <S extends keyof Config>(section: S, key: keyof Config[S]) => (text: string) =>
    setDraft(current => ({ ...current, [section]: { ...current[section], [key]: text } }));
  function commit() {
    const parsed = configSchema.safeParse(draft);
    if (!parsed.success) { setInvalid(parsed.error.issues.map(i => `${i.path.join('.')}: ${i.message}`).join('\n')); return; }
    setInvalid(null);
    void save(parsed.data, revision).then(() => status.refetch());
  }
  return <View style={{ gap: 16 }}>
    <SettingsSection title="Claude Managed Agents">
      <SettingsCard>
        <SettingsRow label="API key" hint={status.data?.detail ?? (status.error ? String(status.error) : 'Checking…')}>
          <Text style={{ color: status.data?.configured ? theme.colors.statusSuccess : theme.colors.statusWarning }}>
            {status.data ? (status.data.configured ? 'Configured' : 'Missing') : '…'}</Text>
        </SettingsRow>
        <SettingsInput label="API key file" hint="Read by the daemon when ANTHROPIC_API_KEY is unset. Store a path, never the key."
          initialValue={values.claude.apiKeyFile} onChangeText={set('claude', 'apiKeyFile')} />
        <SettingsInput label="API base URL" initialValue={values.claude.baseUrl} onChangeText={set('claude', 'baseUrl')} />
        <SettingsInput label="Default agent ID" placeholder="agent_…" initialValue={values.claude.defaultAgentId}
          onChangeText={set('claude', 'defaultAgentId')} />
        <SettingsInput label="Default environment ID" placeholder="env_…" initialValue={values.claude.defaultEnvironmentId}
          onChangeText={set('claude', 'defaultEnvironmentId')} />
      </SettingsCard>
    </SettingsSection>
    <SettingsSection title="Codex Cloud">
      <SettingsCard>
        <SettingsInput label="codex binary" hint="Must be logged in with `codex login` as the daemon's user."
          initialValue={values.codex.binary} onChangeText={set('codex', 'binary')} />
        <SettingsInput label="Default environment" hint="Environment ID or label used by /codex-cloud."
          initialValue={values.codex.defaultEnvironment} onChangeText={set('codex', 'defaultEnvironment')} />
      </SettingsCard>
    </SettingsSection>
    {(invalid || saveError) && <Text accessibilityRole="alert" style={{ color: theme.colors.statusDanger }}>{invalid || saveError}</Text>}
    <SettingsCard>
      <SettingsAction label="Save settings" actionLabel={saving ? 'Saving…' : 'Save'} disabled={saving} onPress={commit} />
    </SettingsCard>
  </View>;
}
