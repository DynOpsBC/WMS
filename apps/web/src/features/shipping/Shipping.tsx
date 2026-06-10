import { useState } from 'react';
import { useCarriers, useShippingRates } from '../../lib/api/hooks.ts';
import { QueryState } from '../../components/QueryState.tsx';

export function Shipping() {
  const [shipmentNo, setShipmentNo] = useState('WHS-00043');
  const [query, setQuery] = useState(shipmentNo);
  const carriers = useCarriers();
  const rates = useShippingRates(query);
  const [selected, setSelected] = useState<string | null>(null);

  const sorted = (rates.data ?? []).slice().sort((a, b) => a.amount - b.amount);

  return (
    <div className="max-w-6xl mx-auto">
      <h2 className="text-2xl font-semibold mb-4">Shipping &amp; carriers</h2>
      <p className="text-sm text-slate-600 mb-2">
        Rate-shop against active carriers, select the cheapest service, print a Zebra ZPL label.
      </p>
      <p className="text-xs text-slate-500 mb-6">
        Active carriers:{' '}
        {carriers.data ? carriers.data.filter((c) => c.active).map((c) => c.code).join(', ') || 'none configured' : '…'}
      </p>

      <div className="bg-white rounded-xl shadow p-6 mb-4">
        <label className="block text-xs text-slate-600 mb-2">Shipment number</label>
        <input
          value={shipmentNo}
          onChange={(e) => setShipmentNo(e.target.value)}
          className="border border-slate-300 rounded px-3 py-2 text-sm font-mono mr-3"
        />
        <button
          type="button"
          onClick={() => setQuery(shipmentNo)}
          className="bg-brand-500 hover:bg-brand-700 text-white px-4 py-2 rounded text-sm"
        >
          Rate-shop
        </button>
      </div>

      <div className="bg-white rounded-xl shadow overflow-hidden">
        <QueryState
          isLoading={rates.isLoading}
          isError={rates.isError}
          error={rates.error}
          isEmpty={sorted.length === 0}
          emptyLabel="No rate quotes yet for this shipment. Trigger rate-shop from the shipment, or check carrier configuration."
        >
          <table className="w-full text-sm">
            <thead className="bg-slate-50 text-left text-slate-500 text-xs uppercase">
              <tr>
                <th className="px-4 py-3">Carrier</th>
                <th>Service</th>
                <th>Amount</th>
                <th>Days</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {sorted.map((r) => {
                const key = r.rateId;
                const isSelected = selected === key;
                return (
                  <tr key={key} className={`border-t border-slate-100 ${isSelected ? 'bg-brand-50' : ''}`}>
                    <td className="px-4 py-3 font-medium">{r.carrierCode}</td>
                    <td>{r.serviceName}</td>
                    <td>
                      {r.amount.toFixed(2)} {r.currency}
                    </td>
                    <td>{r.estimatedDays}</td>
                    <td>
                      <button
                        type="button"
                        onClick={() => setSelected(key)}
                        className={`text-xs px-3 py-1 rounded ${
                          isSelected ? 'bg-brand-500 text-white' : 'border border-slate-300 hover:bg-slate-50'
                        }`}
                      >
                        {isSelected ? 'Selected · print' : 'Select'}
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </QueryState>
      </div>
    </div>
  );
}
