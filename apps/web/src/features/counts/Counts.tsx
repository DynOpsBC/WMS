export function Counts() {
  return (
    <div className="max-w-6xl mx-auto">
      <h2 className="text-2xl font-semibold mb-4">Counts & variance</h2>
      <div className="grid grid-cols-3 gap-4 mb-6">
        <Card label="Open count plans" value="3" />
        <Card label="Lines pending recount" value="12" />
        <Card label="Pending variance approval" value="5" />
      </div>
      <div className="bg-white rounded-xl shadow p-6 text-sm text-slate-600">
        Cycle count scheduler, variance review with supervisor approval, replenishment worksheet (M4 wires
        to <code>/wmsCycleCountPlans</code>).
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
