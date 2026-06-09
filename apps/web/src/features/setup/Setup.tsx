import { useState } from 'react';

type SetupTab = 'locations' | 'zones' | 'bins' | 'workers' | 'devices' | 'barcodes' | 'policies';

const TABS: Array<{ id: SetupTab; label: string }> = [
  { id: 'locations', label: 'Locations' },
  { id: 'zones', label: 'Zones' },
  { id: 'bins', label: 'Bins' },
  { id: 'workers', label: 'Workers' },
  { id: 'devices', label: 'Mobile Devices' },
  { id: 'barcodes', label: 'Item Barcodes' },
  { id: 'policies', label: 'Packing Policies' },
];

export function Setup() {
  const [tab, setTab] = useState<SetupTab>('locations');

  return (
    <div className="max-w-6xl mx-auto">
      <h2 className="text-2xl font-semibold mb-4">Setup</h2>
      <div className="bg-white rounded-xl shadow">
        <div className="flex border-b border-slate-200 overflow-x-auto">
          {TABS.map((t) => (
            <button
              key={t.id}
              type="button"
              onClick={() => setTab(t.id)}
              className={`px-4 py-3 text-sm font-medium whitespace-nowrap transition ${
                tab === t.id
                  ? 'border-b-2 border-brand-500 text-brand-700'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              {t.label}
            </button>
          ))}
        </div>
        <div className="p-6">
          {tab === 'locations' && <LocationsPane />}
          {tab === 'zones' && <Placeholder label="Zone master" entity="zones" />}
          {tab === 'bins' && <Placeholder label="Bin master with ranking + class" entity="bins" />}
          {tab === 'workers' && <Placeholder label="Workers + mobile users + menu assignment" entity="workers" />}
          {tab === 'devices' && <Placeholder label="Registered mobile devices (Zebra / Honeywell)" entity="devices" />}
          {tab === 'barcodes' && <Placeholder label="Item barcode master (per UoM)" entity="barcodes" />}
          {tab === 'policies' && <Placeholder label="Packing / put-away templates" entity="policies" />}
        </div>
      </div>
    </div>
  );
}

function LocationsPane() {
  return (
    <div>
      <p className="text-sm text-slate-600 mb-4">
        Manage warehouse locations. Toggle <code>WMS Enabled</code> per location, set the default packing
        policy, and allow license-plate receiving / picking.
      </p>
      <table className="w-full text-sm">
        <thead className="text-left text-slate-500 border-b border-slate-200">
          <tr>
            <th className="py-2">Code</th>
            <th>Name</th>
            <th>WMS</th>
            <th>LP Receive</th>
            <th>LP Pick</th>
            <th>Packing Policy</th>
          </tr>
        </thead>
        <tbody>
          <tr className="border-b border-slate-100">
            <td className="py-2 font-mono">MAIN</td>
            <td>Main warehouse</td>
            <td>✓</td><td>✓</td><td>✓</td><td>STANDARD</td>
          </tr>
          <tr className="border-b border-slate-100">
            <td className="py-2 font-mono">EAST</td>
            <td>East distribution</td>
            <td>✓</td><td>✓</td><td>—</td><td>STANDARD</td>
          </tr>
        </tbody>
      </table>
      <p className="text-xs text-slate-500 mt-3">
        Reading from <code>/wmsLocations</code> (extends standard BC <code>Location</code>) lands in M1.
      </p>
    </div>
  );
}

function Placeholder({ label, entity }: { label: string; entity: string }) {
  return (
    <div className="text-sm text-slate-600">
      <p className="mb-2">{label}</p>
      <p className="text-xs text-slate-400">
        Wires to <code>/wms{entity[0]?.toUpperCase()}{entity.slice(1)}</code>.
      </p>
    </div>
  );
}
