import { useEffect, useState } from 'react';

interface KPI { label: string; value: string; delta?: string; tone?: 'up' | 'down' | 'neutral' }

const KPIS: KPI[] = [
  { label: 'Open receipts', value: '7', delta: '+2', tone: 'neutral' },
  { label: 'Open shipments', value: '14', delta: '−3', tone: 'down' },
  { label: 'Pick lines remaining', value: '342', delta: '−128', tone: 'down' },
  { label: 'Dock-to-stock (avg)', value: '37m', delta: '−4m', tone: 'down' },
  { label: 'Count accuracy (30d)', value: '99.6%', delta: '+0.2', tone: 'up' },
  { label: 'Active workers', value: '11 / 14', tone: 'neutral' },
];

interface ActivityEvent {
  t: string;
  worker: string;
  action: string;
  doc: string;
}

const SAMPLE_ACTIVITY: ActivityEvent[] = [
  { t: '09:42:12', worker: 'PETER',  action: 'Picked',           doc: 'WHS-00043 · line 12' },
  { t: '09:41:58', worker: 'MARIA',  action: 'Received LP',      doc: 'LPN-0098 → BIN-A12' },
  { t: '09:41:30', worker: 'ANNA',   action: 'Packed container', doc: 'CNT-0014' },
  { t: '09:40:55', worker: 'JON',    action: 'Cycle count',      doc: 'BIN-B07 · −2 EA' },
  { t: '09:39:11', worker: 'PETER',  action: 'Moved',            doc: 'BIN-C01 → BIN-A12' },
];

export function Dashboard() {
  const [activity, setActivity] = useState<ActivityEvent[]>(SAMPLE_ACTIVITY);

  useEffect(() => {
    /**
     * M7: subscribe to BC webhooks / SignalR for real-time updates.
     * Placeholder: rotate the sample feed every 8s so the UI feels alive.
     */
    const i = setInterval(() => {
      setActivity((prev) => {
        const first = prev[0];
        if (!first) return prev;
        const rotated: ActivityEvent = { ...first, t: new Date().toTimeString().slice(0, 8) };
        return [rotated, ...prev.slice(0, 4)];
      });
    }, 8000);
    return () => clearInterval(i);
  }, []);

  return (
    <div className="max-w-6xl mx-auto">
      <h2 className="text-2xl font-semibold mb-4">Operations dashboard</h2>
      <div className="grid grid-cols-3 gap-4 mb-6">
        {KPIS.map((k) => (
          <div key={k.label} className="bg-white rounded-xl shadow p-4">
            <div className="text-xs uppercase text-slate-500">{k.label}</div>
            <div className="text-3xl font-semibold text-brand-700 mt-2">{k.value}</div>
            {k.delta && (
              <div className={`text-xs mt-1 ${
                k.tone === 'up' ? 'text-emerald-600' :
                k.tone === 'down' ? 'text-emerald-600' :
                'text-slate-500'
              }`}>
                {k.delta} from yesterday
              </div>
            )}
          </div>
        ))}
      </div>

      <div className="grid grid-cols-3 gap-4">
        <div className="col-span-2 bg-white rounded-xl shadow p-5">
          <h3 className="font-semibold mb-3">Real-time activity</h3>
          <table className="w-full text-sm">
            <thead className="text-left text-slate-500 text-xs uppercase">
              <tr><th className="py-2">Time</th><th>Worker</th><th>Action</th><th>Doc</th></tr>
            </thead>
            <tbody>
              {activity.map((a, idx) => (
                <tr key={`${a.t}-${idx}`} className="border-t border-slate-100">
                  <td className="py-2 font-mono text-xs">{a.t}</td>
                  <td className="font-mono text-xs">{a.worker}</td>
                  <td>{a.action}</td>
                  <td className="text-slate-600">{a.doc}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="text-xs text-slate-400 mt-3">
            Sample feed. M7 binds to BC webhook subscriptions delivered via SignalR.
          </p>
        </div>
        <div className="bg-white rounded-xl shadow p-5">
          <h3 className="font-semibold mb-3">Exceptions</h3>
          <ul className="text-sm text-slate-700 space-y-2">
            <li className="flex justify-between"><span>Over-receipt</span><span className="font-semibold text-amber-600">3</span></li>
            <li className="flex justify-between"><span>Pick shortfall</span><span className="font-semibold text-amber-600">5</span></li>
            <li className="flex justify-between"><span>Count variance &gt; 5%</span><span className="font-semibold text-rose-600">2</span></li>
            <li className="flex justify-between"><span>Label print failed</span><span className="font-semibold text-slate-500">0</span></li>
          </ul>
        </div>
      </div>
    </div>
  );
}
