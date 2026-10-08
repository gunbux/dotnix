import { showToast, Toast } from "@vicinae/api";
import { useCallback, useEffect, useState } from "react";
import { snapshot, type Snapshot } from "./paseo";

export function useSnapshot() {
  const [data, setData] = useState<Snapshot | null>(null);
  const [isLoading, setLoading] = useState(true);
  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      setData(await snapshot());
    } catch (error) {
      await showFailure("Could not reach Paseo", error);
    } finally {
      setLoading(false);
    }
  }, []);
  useEffect(() => void refresh(), [refresh]);
  return { data, isLoading, refresh };
}

export const showFailure = (title: string, error: unknown) =>
  showToast({ style: Toast.Style.Failure, title, message: error instanceof Error ? error.message : String(error) });
