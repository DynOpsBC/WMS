import type { ReactNode } from 'react';

interface Props {
  isLoading: boolean;
  isError: boolean;
  error?: unknown;
  isEmpty?: boolean;
  emptyLabel?: string;
  children: ReactNode;
}

/** Uniform loading / error / empty / offline framing for live BC data. */
export function QueryState({ isLoading, isError, error, isEmpty, emptyLabel, children }: Props) {
  if (isLoading) {
    return <div className="p-6 text-sm text-slate-500">Loading from Business Central…</div>;
  }
  if (isError) {
    const msg = error instanceof Error ? error.message : 'Request failed';
    return (
      <div className="p-4 rounded-lg bg-rose-50 border border-rose-200 text-sm text-rose-800">
        <div className="font-semibold mb-1">Can’t reach Business Central</div>
        <div className="text-xs font-mono break-all">{msg}</div>
        <div className="text-xs mt-2 text-rose-600">
          Check VITE_BC_* env vars and that you’re signed in with an Entra ID account that has the WMS permission set.
        </div>
      </div>
    );
  }
  if (isEmpty) {
    return <div className="p-6 text-sm text-slate-400">{emptyLabel ?? 'No records.'}</div>;
  }
  return <>{children}</>;
}
