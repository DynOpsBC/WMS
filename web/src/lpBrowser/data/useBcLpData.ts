import { useCallback, useEffect, useMemo, useState } from "react";

export type LpNode = {
  no: string;
  parentLpNo?: string;
  binCode?: string;
  status?: string;
  children?: LpNode[];
};

type ApiLp = {
  no?: string;
  parentLpNo?: string;
  binCode?: string;
  status?: string;
  lines?: ApiLp[];
  children?: ApiLp[];
};

export function useBcLpData() {
  const [lps, setLps] = useState<LpNode[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await fetch("/api/dynops/advWms/v2.0/licensePlates?$expand=lines");
      if (!response.ok) throw new Error(`LP fetch failed: ${response.status}`);
      const payload = await response.json() as { value?: ApiLp[] } | ApiLp[];
      setLps(normalize(Array.isArray(payload) ? payload : payload.value ?? []));
    } catch (err) {
      setError(err instanceof Error ? err.message : "LP fetch failed");
      setLps([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return useMemo(() => ({ lps, setLps, loading, error, refresh }), [lps, loading, error, refresh]);
}

export function normalize(items: ApiLp[]): LpNode[] {
  const map = new Map<string, LpNode>();
  items.forEach((item) => {
    if (!item.no) return;
    map.set(item.no, {
      no: item.no,
      parentLpNo: item.parentLpNo,
      binCode: item.binCode,
      status: item.status,
      children: normalize(item.children ?? item.lines ?? []),
    });
  });
  map.forEach((node) => {
    if (!node.parentLpNo) return;
    const parent = map.get(node.parentLpNo);
    if (parent) {
      parent.children = [...(parent.children ?? []), node];
    }
  });
  return [...map.values()].filter((node) => !node.parentLpNo || !map.has(node.parentLpNo));
}
