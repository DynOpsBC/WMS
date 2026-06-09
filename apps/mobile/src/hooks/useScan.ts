import { useEffect, useState, useCallback } from 'react';
import { scanner, type ScanEvent } from '@/lib/scanner';

/** Subscribe to the next scan, then auto-unsubscribe. Returns the latest event. */
export function useScan(handler: (e: ScanEvent) => void, deps: ReadonlyArray<unknown> = []): void {
  const stable = useCallback(handler, deps); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    const off = scanner.on(stable);
    return () => { off(); };
  }, [stable]);
}

/** Convenience: keep the last N scans in state. */
export function useScanHistory(limit = 5): ScanEvent[] {
  const [hist, setHist] = useState<ScanEvent[]>([]);
  useScan((e) => setHist((h) => [e, ...h].slice(0, limit)), [limit]);
  return hist;
}
