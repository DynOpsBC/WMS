import { useState } from 'react';

interface Rate {
  carrier: string;
  service: string;
  amount: number;
  days: number;
}

const SAMPLE_RATES: Rate[] = [
  { carrier: 'UPS',   service: 'Ground',           amount: 14.23, days: 3 },
  { carrier: 'UPS',   service: '2nd Day Air',      amount: 32.10, days: 2 },
  { carrier: 'FedEx', service: 'Home Delivery',    amount: 13.95, days: 3 },
  { carrier: 'FedEx', service: '2Day',             amount: 31.42, days: 2 },
  { carrier: 'USPS',  service: 'Priority Mail',    amount: 11.75, days: 3 },
  { carrier: 'DHL',   service: 'Express Worldwide', amount: 48.20, days: 2 },
];

export function Shipping() {
  const [shipmentNo, setShipmentNo] = useState('WHS-00043');
  const [selected, setSelected] = useState<string | null>(null);

  return (
    <div className="max-w-6xl mx-auto">
      <h2 className="text-2xl font-semibold mb-4">Shipping & carriers</h2>
      <p className="text-sm text-slate-600 mb-6">
        Rate-shop against active carriers, select the cheapest service, print a Zebra ZPL label.
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
          className="bg-brand-500 hover:bg-brand-700 text-white px-4 py-2 rounded text-sm"
        >
          Rate-shop
        </button>
      </div>

      <div className="bg-white rounded-xl shadow overflow-hidden">
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
            {SAMPLE_RATES
              .slice()
              .sort((a, b) => a.amount - b.amount)
              .map((r) => {
                const key = `${r.carrier}-${r.service}`;
                const isSelected = selected === key;
                return (
                  <tr key={key} className={`border-t border-slate-100 ${isSelected ? 'bg-brand-50' : ''}`}>
                    <td className="px-4 py-3 font-medium">{r.carrier}</td>
                    <td>{r.service}</td>
                    <td>${r.amount.toFixed(2)}</td>
                    <td>{r.days}</td>
                    <td>
                      <button
                        type="button"
                        onClick={() => setSelected(key)}
                        className={`text-xs px-3 py-1 rounded ${
                          isSelected
                            ? 'bg-brand-500 text-white'
                            : 'border border-slate-300 hover:bg-slate-50'
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
      </div>

      <p className="text-xs text-slate-500 mt-3">
        M6 binds <code>/wmsShippingRates</code> from BC. Real carrier adapters wire OAuth2 to FedEx/UPS/USPS/DHL.
      </p>
    </div>
  );
}
