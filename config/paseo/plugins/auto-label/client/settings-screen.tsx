import { type PluginSurfaceProps, useRpc, useSettings } from '@getpaseo/plugin/client';
import { SettingsAction, SettingsCard, SettingsInput, SettingsSection, SettingsSelect, SettingsSwitch } from '@getpaseo/plugin/client/ui';
import { useState } from 'react';
import { Text, View } from 'react-native';
import { labelUnlabelled } from '../shared/rpc';
import { autoLabel, MODELS, type Settings } from '../shared/settings';
import { FALLBACK_LABEL, normalizeLabel } from '../shared/topics';

const parseTopics = (text: string) => [...new Set(text.split(',').map(normalizeLabel).filter(Boolean))];

export function SettingsScreen({ theme }: PluginSurfaceProps) {
  const settings = useSettings(autoLabel);
  const labelAll = useRpc(labelUnlabelled);
  const [topicsDraft, setTopicsDraft] = useState<string | null>(null);
  const [status, setStatus] = useState<{ text: string; error: boolean } | null>(null);

  if (settings.status === 'loading') return <Text style={{ color: theme.colors.foregroundMuted }}>Loading…</Text>;
  if (settings.status !== 'ready') {
    return <SettingsSection title="Auto label">
      <SettingsCard>
        <SettingsAction label="Settings could not be read" hint={settings.error} actionLabel="Reset"
          onPress={() => void settings.reset()} />
      </SettingsCard>
    </SettingsSection>;
  }
  const { values, revision } = settings;
  const save = (patch: Partial<Settings>) => void settings.save({ ...values, ...patch }, revision);
  const topics = topicsDraft === null ? values.topics : parseTopics(topicsDraft);

  return <View style={{ gap: 16 }}>
    <SettingsSection title="Auto label">
      <SettingsCard>
        <SettingsSwitch label="Label new workspaces" hint="Adds one workspace label to sidebar workspaces that have none."
          value={values.enabled} onValueChange={enabled => save({ enabled })} />
        <SettingsSelect label="Model" hint="Runs headless Claude Code with your existing login." value={values.model}
          options={MODELS.map(model => ({ label: model, value: model }))} onValueChange={model => save({ model })} />
        <SettingsSwitch label="Allow new labels" hint={`When off, workspaces that fit no label get ${FALLBACK_LABEL}.`}
          value={values.allowNew} onValueChange={allowNew => save({ allowNew })} />
      </SettingsCard>
    </SettingsSection>
    <SettingsSection title="Labels">
      <SettingsCard>
        <SettingsInput label="Preferred labels" hint="Comma-separated. Existing workspace labels are always reused too."
          initialValue={values.topics.join(', ')} onChangeText={setTopicsDraft} />
        <SettingsAction label="Save labels" hint={topics.join(', ')} actionLabel="Save"
          disabled={topicsDraft === null || settings.saving}
          onPress={() => settings.save({ ...values, topics }, revision).then(ok => ok && setTopicsDraft(null))} />
      </SettingsCard>
    </SettingsSection>
    <SettingsSection title="Existing workspaces">
      <SettingsCard>
        <SettingsAction label="Label unlabelled workspaces" hint={status?.text} error={status?.error ? status.text : null}
          actionLabel="Run" onPress={() => labelAll({})
            .then(({ queued }) => setStatus({ text: `Queued ${queued} workspaces. Labels appear as each finishes.`, error: false }))
            .catch(error => setStatus({ text: error instanceof Error ? error.message : String(error), error: true }))} />
      </SettingsCard>
    </SettingsSection>
    {settings.saveError ? <Text style={{ color: theme.colors.statusDanger }}>{settings.saveError}</Text> : null}
  </View>;
}
