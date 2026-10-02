import type { PluginSurfaceProps } from '@getpaseo/plugin/client';
import type { ReactNode } from 'react';
import { Pressable, Text, TextInput, View } from 'react-native';

export type Theme = PluginSurfaceProps['theme'];
export function Button({ theme, children, onPress, disabled = false, selected = false, danger = false }: {
  theme: Theme; children: string; onPress: () => void; disabled?: boolean; selected?: boolean; danger?: boolean;
}) {
  return <Pressable accessibilityRole="button" accessibilityLabel={children}
    accessibilityState={{ disabled, selected }} disabled={disabled} onPress={onPress}
    style={{ minHeight: 42, justifyContent: 'center', paddingHorizontal: 14, paddingVertical: 10,
      borderRadius: 8, opacity: disabled ? 0.5 : 1, borderWidth: 1,
      borderColor: selected ? theme.colors.accent : theme.colors.border,
      backgroundColor: selected ? theme.colors.accent : theme.colors.surface1 }}>
    <Text style={{ color: selected ? theme.colors.accentForeground : theme.colors.foreground,
      fontWeight: selected || danger ? '600' : '400' }}>{children}</Text>
  </Pressable>;
}
export function Field({ theme, value, onChange, label, disabled = false }: {
  theme: Theme; value: string; onChange: (value: string) => void; label: string; disabled?: boolean;
}) {
  return <TextInput accessibilityLabel={label} placeholder={label} placeholderTextColor={theme.colors.foregroundMuted}
    value={value} onChangeText={onChange} editable={!disabled}
    style={{ minHeight: 44, borderWidth: 1, borderColor: theme.colors.border, borderRadius: 8,
      padding: 12, color: theme.colors.foreground, backgroundColor: theme.colors.surface1 }} />;
}
export function Note({ theme, children }: { theme: Theme; children: ReactNode }) {
  return <Text accessibilityRole="text" style={{ color: theme.colors.foregroundMuted }}>{children}</Text>;
}
export function Row({ children }: { children: ReactNode }) {
  return <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, alignItems: 'center' }}>{children}</View>;
}
