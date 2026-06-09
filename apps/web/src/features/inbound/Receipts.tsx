export function Receipts() {
  return (
    <div className="max-w-6xl mx-auto">
      <h2 className="text-2xl font-semibold mb-4">Inbound receipts</h2>
      <p className="text-sm text-slate-600 mb-6">
        Live queue of open / partially received / closed warehouse receipts. ASN import, exception triage,
        receiver-assignment.
      </p>
      <ReceiptsTable />
    </div>
  );
}

function ReceiptsTable() {
  const rows = [
    { no: 'WHR-00012', vendor: '10000 · Fabrikam', lines: 8, qty: 480, status: 'In progress', worker: 'PETER' },
    { no: 'WHR-00011', vendor: '10000 · Fabrikam', lines: 4, qty: 220, status: 'Released', worker: '—' },
    { no: 'WHR-00010', vendor: '20000 · Adatum',   lines: 2, qty: 60,  status: 'Closed',   worker: 'ANNA' },
  ];
  return (
    <div className="bg-white rounded-xl shadow overflow-hidden">
      <table className="w-full text-sm">
        <thead className="bg-slate-50 text-left text-slate-500 text-xs uppercase">
          <tr>
            <th className="px-4 py-3">Receipt No.</th>
            <th>Vendor</th>
            <th>Lines</th>
            <th>Qty</th>
            <th>Status</th>
            <th>Worker</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.no} className="border-t border-slate-100">
              <td className="px-4 py-3 font-mono">{r.no}</td>
              <td>{r.vendor}</td>
              <td>{r.lines}</td>
              <td>{r.qty}</td>
              <td>
                <span className={`text-xs px-2 py-0.5 rounded ${
                  r.status === 'Closed' ? 'bg-emerald-100 text-emerald-800' :
                  r.status === 'In progress' ? 'bg-amber-100 text-amber-800' :
                  'bg-slate-100 text-slate-700'
                }`}>{r.status}</span>
              </td>
              <td className="font-mono text-xs">{r.worker}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
