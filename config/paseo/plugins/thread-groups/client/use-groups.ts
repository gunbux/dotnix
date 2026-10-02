import { useSettings } from '@getpaseo/plugin/client';
import { useRef, useState } from 'react';
import { threadGroups } from '../shared/settings';
import type { Groups } from '../shared/groups';

export function useGroups() {
  const settings = useSettings(threadGroups);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const lock = useRef(false);
  async function save(next: () => Groups, revision: string): Promise<boolean> {
    if (lock.current) return false;
    lock.current = true;
    setPending(true);
    setError(null);
    try { return await settings.save(next(), revision); }
    catch (err) { setError(err instanceof Error ? err.message : String(err)); return false; }
    finally { lock.current = false; setPending(false); }
  }
  async function reload() {
    setError(null);
    await settings.reload();
  }
  return { settings, save, reload, pending: pending || settings.saving, error: error || settings.saveError };
}
