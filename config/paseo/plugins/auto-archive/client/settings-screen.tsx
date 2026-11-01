import { type PluginSurfaceProps, useRpc, useSettings } from '@getpaseo/plugin/client';
import { SettingsAction, SettingsCard, SettingsInput, SettingsSection, SettingsSwitch } from '@getpaseo/plugin/client/ui';
import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { Text, View } from 'react-native';
import { archiveStale, previewStale } from '../shared/rpc';
import { autoArchive, MAX_DAYS, type Settings } from '../shared/settings';

const parseDays = (text: string) => {
  const days = Number(text.trim());
  return Number.isFinite(days) && days > 0 && days <= MAX_DAYS ? days : null;
};
const parseHours = (text: string) => {
  const hours = Number(text.trim());
  return Number.isFinite(hours) && hours >= 0 && hours <= MAX_DAYS * 24 ? hours : null;
};
const plural = (count: number, word: string) => `${count} ${word}${count === 1 ? '' : 's'}`;
const describe = (days: number) => days < 1 ? plural(Math.round(days * 24), 'hour') : plural(Math.round(days * 10) / 10, 'day');

export function SettingsScreen({ theme }: PluginSurfaceProps) {
  const settings = useSettings(autoArchive);
  const preview = useRpc(previewStale);
  const archive = useRpc(archiveStale);
  const [daysDraft, setDaysDraft] = useState<string | null>(null);
  const [chatDraft, setChatDraft] = useState<{ label: string; hours: string } | null>(null);
  const [status, setStatus] = useState<{ text: string; error: boolean } | null>(null);
  const ready = settings.status === 'ready';
  const candidates = useQuery({
    queryKey: ['auto-archive', 'preview', ready ? settings.revision : null],
    queryFn: () => preview({}),
    enabled: ready,
  });

  if (settings.status === 'loading') return <Text style={{ color: theme.colors.foregroundMuted }}>Loading…</Text>;
  if (settings.status !== 'ready') {
    return <SettingsSection title="Auto archive">
      <SettingsCard>
        <SettingsAction label="Settings could not be read" hint={settings.error} actionLabel="Reset"
          onPress={() => void settings.reset()} />
      </SettingsCard>
    </SettingsSection>;
  }
  const { values, revision } = settings;
  const save = (patch: Partial<Settings>) => void settings.save({ ...values, ...patch }, revision);
  const days = daysDraft === null ? values.days : parseDays(daysDraft);
  const chatHours = chatDraft === null ? values.quickChatHours : parseHours(chatDraft.hours);
  const chat = chatDraft ?? { label: values.quickChatLabel, hours: String(values.quickChatHours) };
  const stale = candidates.data?.candidates ?? [];
  const last = candidates.data?.lastSweep;
  const staleHint = candidates.isLoading ? 'Checking…'
    : candidates.error ? undefined
    : stale.length ? stale.slice(0, 8).map(c => `${c.title} (${describe(c.idleDays)})`).join('\n')
      + (stale.length > 8 ? `\n…and ${stale.length - 8} more` : '')
    : 'Nothing is idle long enough to archive.';

  return <View style={{ gap: 16 }}>
    <SettingsSection title="Auto archive">
      <SettingsCard>
        <SettingsSwitch label="Archive idle workspaces" hint={`Checks hourly and archives workspaces with no activity for ${describe(values.days)}.`}
          value={values.enabled} onValueChange={enabled => save({ enabled })} />
        <SettingsInput label="Idle days" hint={`Days without activity before archiving. Decimals allowed, up to ${MAX_DAYS}.`}
          initialValue={String(values.days)} onChangeText={setDaysDraft} placeholder="4" />
        <SettingsAction label="Save idle days" hint={days === null ? undefined : describe(days)}
          error={days === null ? `Enter a number above 0 and at most ${MAX_DAYS}.` : null} actionLabel="Save"
          disabled={daysDraft === null || days === null || settings.saving}
          onPress={() => days !== null && settings.save({ ...values, days }, revision).then(ok => ok && setDaysDraft(null))} />
      </SettingsCard>
    </SettingsSection>
    <SettingsSection title="Quick chats">
      <SettingsCard>
        <SettingsInput label="Quick chat labels"
          hint="Workspaces with any of these comma-separated labels, such as the Vicinae extension's quick chats and glance's chats, use the hours below. Leave empty to turn off."
          initialValue={values.quickChatLabel} onChangeText={label => setChatDraft({ ...chat, label })} placeholder="Quick chat, Glance" />
        <SettingsInput label="Quick chat hours" hint="Hours without activity before a quick chat is archived. 0 uses idle days."
          initialValue={String(values.quickChatHours)} onChangeText={hours => setChatDraft({ ...chat, hours })} placeholder="12" />
        <SettingsAction label="Save quick chat settings"
          hint={chatHours === null || !chat.label.trim() || chatHours === 0 ? undefined : `Archived after ${describe(chatHours / 24)}`}
          error={chatHours === null ? `Enter hours from 0 to ${MAX_DAYS * 24}.` : null} actionLabel="Save"
          disabled={chatDraft === null || chatHours === null || settings.saving}
          onPress={() => chatHours !== null && settings.save({ ...values, quickChatLabel: chat.label.trim(), quickChatHours: chatHours }, revision)
            .then(ok => ok && setChatDraft(null))} />
      </SettingsCard>
    </SettingsSection>
    <SettingsSection title="Keep">
      <SettingsCard>
        <SettingsSwitch label="Pinned workspaces" hint="Never archive a pinned workspace."
          value={values.keepPinned} onValueChange={keepPinned => save({ keepPinned })} />
        <SettingsSwitch label="Worktrees with uncommitted changes"
          hint="Archiving removes a managed worktree, so keep any that are dirty or whose state is unknown."
          value={values.keepUncommitted} onValueChange={keepUncommitted => save({ keepUncommitted })} />
      </SettingsCard>
    </SettingsSection>
    <SettingsSection title="Idle now">
      <SettingsCard>
        <SettingsAction label={`${plural(stale.length, 'workspace')} would be archived`} hint={staleHint}
          error={candidates.error ? (candidates.error as Error).message : status?.error ? status.text : null}
          actionLabel="Archive now" disabled={!stale.length || candidates.isFetching}
          onPress={() => archive({})
            .then(({ archived, failed }) => setStatus({
              text: `Archived ${plural(archived.length, 'workspace')}${failed ? `; ${failed} failed (see plugin logs)` : ''}.`,
              error: failed > 0,
            }))
            .catch(error => setStatus({ text: error instanceof Error ? error.message : String(error), error: true }))
            .finally(() => void candidates.refetch())} />
        {status && !status.error ? <Text style={{ color: theme.colors.foregroundMuted, padding: 12 }}>{status.text}</Text> : null}
        {last ? <Text style={{ color: theme.colors.foregroundMuted, padding: 12 }}>
          Last sweep {new Date(last.at).toLocaleString()}: archived {last.archived}{last.failed ? `, ${last.failed} failed` : ''}.
        </Text> : null}
      </SettingsCard>
    </SettingsSection>
    {settings.saveError ? <Text style={{ color: theme.colors.statusDanger }}>{settings.saveError}</Text> : null}
  </View>;
}
