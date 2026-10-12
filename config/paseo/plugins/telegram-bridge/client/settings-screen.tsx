import { useRpc, useSettings, type PluginSurfaceProps } from '@getpaseo/plugin/client';
import { SettingsAction, SettingsCard, SettingsInput, SettingsSection, SettingsSwitch } from '@getpaseo/plugin/client/ui';
import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { Text, View } from 'react-native';
import { bridgeSettings, configSchema, type Config } from '../shared/settings.ts';
import { bridgeStatus } from '../shared/rpc.ts';

export function SettingsScreen({ theme, layout }: PluginSurfaceProps) {
  const settings = useSettings(bridgeSettings);
  const statusRpc = useRpc(bridgeStatus);
  const [draft, setDraft] = useState<Partial<Config>>({});
  const status = useQuery({ queryKey: ['telegram-bridge', 'status'], queryFn: () => statusRpc({}), refetchInterval: 5000 });
  if (settings.status === 'loading') return <Text style={{ color: theme.colors.foregroundMuted }}>Loading settings...</Text>;
  if (settings.status !== 'ready') return <Text style={{ color: theme.colors.statusDanger }}>Could not read settings: {settings.error}</Text>;
  const values = { ...settings.values, ...draft };
  const checked = configSchema.safeParse(values);
  const error = !checked.success ? checked.error.issues[0]?.message
    : values.enabled && (!values.ownerId || !values.tokenFile.startsWith('/')) ? 'Enabling requires a numeric owner ID and an absolute token file path.'
    : values.defaultProvider && !/^[^/\s]+\/\S+$/.test(values.defaultProvider) ? 'Use provider/model, or leave the default provider empty.' : null;
  const change = (patch: Partial<Config>) => setDraft(current => ({ ...current, ...patch }));
  return <View style={{ gap: 16, padding: layout.compact ? 12 : 20 }}>
    <SettingsSection title="Connection">
      <SettingsCard>
        <SettingsSwitch label="Enable Telegram bridge" hint="Your private chat and groups you register with /start can control their own workspace."
          value={values.enabled} onValueChange={enabled => change({ enabled })} />
        <SettingsInput label="Your Telegram user ID" hint="Your numeric user ID, not a username or the bot ID."
          initialValue={settings.values.ownerId} onChangeText={ownerId => change({ ownerId: ownerId.trim() })} placeholder="123456789" />
        <SettingsInput label="Bot token file" hint="Absolute path on this daemon, readable only by its owner. Store the token through SOPS."
          initialValue={settings.values.tokenFile} onChangeText={tokenFile => change({ tokenFile: tokenFile.trim() })} placeholder="/run/secrets/paseo_telegram_bot_token" />
        <SettingsInput label="Default provider/model" hint="Used by /new. Copy a provider/model supported by this Paseo daemon. The first prompt in each chat creates an agent."
          initialValue={settings.values.defaultProvider} onChangeText={defaultProvider => change({ defaultProvider: defaultProvider.trim() })} placeholder="provider/model" />
        <SettingsAction label="Save bridge settings" actionLabel="Save" error={error ?? settings.saveError ?? null}
          disabled={Boolean(error) || settings.saving || !Object.keys(draft).length}
          onPress={async () => { if (await settings.save(values, settings.revision)) setDraft({}); }} />
      </SettingsCard>
    </SettingsSection>
    <SettingsSection title="Status">
      <SettingsCard>
        <SettingsAction label={status.data?.status ?? 'Checking connection...'} actionLabel="Refresh"
          error={status.error ? 'Could not reach the bridge on this daemon.' : null}
          hint={status.data ? `${status.data.bot ? '@' + status.data.bot : 'Bot not connected'}\nSelected agent: ${status.data.selectedAgent ?? 'none'}\nMessages queued: ${status.data.queued}` : undefined}
          onPress={() => { void status.refetch(); }} />
      </SettingsCard>
    </SettingsSection>
    <Text style={{ color: theme.colors.foregroundMuted }}>
      Each chat gets its own workspace. Send /start in a group yourself to register it. All group members can then send prompts and approve actions.
      Send /new followed by a prompt to create an agent with TREK access. /agents and /use show only this chat’s agents.
    </Text>
    <Text style={{ color: theme.colors.foregroundMuted }}>
      Use /send@your_bot followed by a prompt in groups, or disable privacy mode with @BotFather for ordinary text. Only one daemon can poll a bot token. Approval buttons expire after 15 minutes. Structured questions must be answered in Paseo.
    </Text>
  </View>;
}
