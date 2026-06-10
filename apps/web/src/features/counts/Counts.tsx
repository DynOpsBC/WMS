import { useCountVariances, useSubmitAction } from '../../lib/api/hooks.ts';
import { QueryState } from '../../components/QueryState.tsx';

export function Counts() {
  const variances = useCountVariances();
  const submit = useSubmitAction();

  const rows = variances.data ?? [];
  const pendingApproval = rows.filter((v) => !v.approvedBy);

  function approve(planNumber: string, lineNumber: number) {
    submit.mutate({
      requestId: crypto.randomUUID(),
      flowId: 'APPROVE-VARIANCE',
      payload: { planNo: planNumber, lineNo: lineNumber },
    });
  }

  return (
    <div className="max-w-6xl mx-auto">
      <h2 className="text-2xl font-semibold mb-4">Counts &amp; variance</h2>
      <div className="grid grid-cols-3 gap-4 mb-6">
        <Card label="Variance lines" value={String(rows.length)} />
        <Card label="Pending approval" value={String(pendingApproval.length)} />
        <Card
          label="Net variance"
          value={String(rows.reduce((s, v) => s + (v.variance ?? 0), 0))}
        />
      </div>

      <div className="bg-white rounded-xl shadow overflow-hidden">
        <QueryState
          isLoading={variances.isLoading}
          isError={variances.isError}
          error={variances.error}
          isEmpty={rows.length === 0}
          emptyLabel="No count variances. Run a cycle count from the mobile app."
        >
          <table className="w-full text-sm">
            <thead className="bg-slate-50 text-left text-slate-500 text-xs uppercase">
              <tr>
                <th className="px-4 py-3">Plan</th>
                <th>Item</th>
                <th>Bin</th>
                <th>System</th>
                <th>Counted</th>
                <th>Variance</th>
                <th>Counted by</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {rows.map((v) => (
                <tr key={`${v.planNumber}-${v.lineNumber}`} className="border-t border-slate-100">
                  <td className="px-4 py-3 font-mono">{v.planNumber}</td>
                  <td>{v.itemNumber}</td>
                  <td className="font-mono text-xs">{v.binCode}</td>
                  <td>{v.systemQuantity}</td>
                  <td>{v.countedQuantity}</td>
                  <td className={v.variance < 0 ? 'text-rose-600 font-semibold' : 'text-emerald-700 font-semibold'}>
                    {v.variance > 0 ? `+${v.variance}` : v.variance}
                  </td>
                  <td className="font-mono text-xs">{v.countedBy}</td>
                  <td>
                    {v.approvedBy ? (
                      <span className="text-xs text-emerald-700">Approved</span>
                    ) : (
                      <button
                        type="button"
                        onClick={() => approve(v.planNumber, v.lineNumber)}
                        disabled={submit.isPending}
                        className="text-xs px-3 py-1 rounded bg-brand-500 text-white disabled:opacity-50"
                      >
                        Approve
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </QueryState>
      </div>
    </div>
  );
}

function Card({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-white rounded-xl shadow p-4">
      <div className="text-xs uppercase text-slate-500">{label}</div>
      <div className="text-3xl font-semibold text-brand-700 mt-2">{value}</div>
    </div>
  );
}
