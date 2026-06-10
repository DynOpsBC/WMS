import { useEffect, useState } from 'react';
import { syncEngine } from '@/lib/runtime';
import type { SyncState } from '@/lib/syncEngine';

/** Live sync status for status bars / badges. */
export function useSync(): SyncState {
  const [state, setState] = useState<SyncState>(syncEngine.getState());
  useEffect(() => syncEngine.subscribe(setState), []);
  return state;
}
