export function Shipments() {
  const rows = [
    { no: 'WHS-00043', customer: '10000 · Cronus', lines: 6, qty: 240, status: 'Picking', wave: 'W-12' },
    { no: 'WHS-00042', customer: '30000 · School',  lines: 3, qty: 120, status: 'Packed',  wave: 'W-12' },
    { no: 'WHS-00041', customer: '40000 · Selangor', lines: 1, qty: 12,  status: 'Shipped', wave: 'W-11' },
  ];
  return (
    <div className="max-w-6xl mx-auto">
      <h2 className="text-2xl font-semibold mb-4">Outbound shipments</h2>
      <p className="text-sm text-slate-600 mb-6">
        Wave planning, release-to-pick, pack station overview, container manifest.
      </p>
      <div className="bg-white rounded-xl shadow overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-slate-50 text-left text-slate-500 text-xs uppercase">
            <tr><th className="px-4 py-3">Shipment</th><th>Customer</th><th>Lines</th><th>Qty</th><th>Status</th><th>Wave</th></tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.no} className="border-t border-slate-100">
                <td className="px-4 py-3 font-mono">{r.no}</td>
                <td>{r.customer}</td>
                <td>{r.lines}</td>
                <td>{r.qty}</td>
                <td>
                  <span className={`text-xs px-2 py-0.5 rounded ${
                    r.status === 'Shipped' ? 'bg-emerald-100 text-emerald-800' :
                    r.status === 'Picking' ? 'bg-amber-100 text-amber-800' :
                    'bg-brand-50 text-brand-700'
                  }`}>{r.status}</span>
                </td>
                <td className="font-mono text-xs">{r.wave}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
