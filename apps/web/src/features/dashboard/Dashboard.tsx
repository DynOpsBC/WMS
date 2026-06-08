const milestones = [
  { id: 'M0', name: 'Foundation', state: 'in progress' },
  { id: 'M1', name: 'Master data & menu designer', state: 'next' },
  { id: 'M2', name: 'Inbound flows', state: 'planned' },
  { id: 'M3', name: 'Outbound flows', state: 'planned' },
  { id: 'M4', name: 'Internal + counts', state: 'planned' },
  { id: 'M5', name: 'Production', state: 'planned' },
  { id: 'M6', name: 'Shipping & labels', state: 'planned' },
  { id: 'M7', name: 'Manager web PWA', state: 'planned' },
  { id: 'M8', name: 'Advanced & polish', state: 'planned' },
  { id: 'M9', name: 'Hardening / GA', state: 'planned' },
] as const;

export function Dashboard() {
  return (
    <div className="max-w-4xl mx-auto">
      <h2 className="text-2xl font-semibold mb-4">Build status</h2>
      <p className="text-slate-600 mb-6">
        Live milestone tracker. Real BC data binds in M1 when{' '}
        <code className="bg-slate-100 px-1 rounded">/wmsWorkers</code> and{' '}
        <code className="bg-slate-100 px-1 rounded">/wmsLicensePlates</code> become callable.
      </p>
      <ul className="bg-white rounded-xl shadow divide-y">
        {milestones.map((m) => (
          <li key={m.id} className="flex items-center justify-between px-5 py-3">
            <span className="font-mono text-sm text-slate-500 w-10">{m.id}</span>
            <span className="flex-1 font-medium">{m.name}</span>
            <span
              className={
                m.state === 'in progress'
                  ? 'text-amber-600 text-sm'
                  : m.state === 'next'
                    ? 'text-brand-500 text-sm'
                    : 'text-slate-400 text-sm'
              }
            >
              {m.state}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}
