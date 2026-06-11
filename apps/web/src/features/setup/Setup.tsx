import { useState } from 'react';
import { useMobileDevices, useRevokeDevice } from '../../lib/api/hooks.ts';
import { QueryState } from '../../components/QueryState.tsx';

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
  const [tab, setTab] = useState<SetupTab>('devices');

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
          {tab === 'devices' && <DevicesPane />}
          {tab === 'barcodes' && <Placeholder label="Item barcode master (per UoM)" entity="barcodes" />}
          {tab === 'policies' && <Placeholder label="Packing / put-away templates" entity="policies" />}
        </div>
      </div>
    </div>
  );
}

function DevicesPane() {
  const devices = useMobileDevices();
  const revoke = useRevokeDevice();
  const rows = devices.data ?? [];

  function onRevoke(deviceId: string) {
    const reason = window.prompt('Reason for revoking this device?', 'Admin revoked') ?? '';
    if (reason) revoke.mutate({ deviceId, reason });
  }

  return (
    <div>
      <div className="flex items-start justify-between mb-4">
        <div>
          <h3 className="text-lg font-semibold mb-1">Paired mobile devices</h3>
          <p className="text-xs text-slate-500 max-w-2xl">
            Devices listed here have completed the one-time pairing with this Business Central company. Workers
            using them no longer see a Microsoft sign-in screen. Revoke a device to force re-pairing.
          </p>
        </div>
      </div>

      <QueryState
        isLoading={devices.isLoading}
        isError={devices.isError}
        error={devices.error}
        isEmpty={rows.length === 0}
        emptyLabel="No paired devices yet. Open the mobile app and tap “Begin pairing”."
      >
        <table className="w-full text-sm">
          <thead className="bg-slate-50 text-left text-slate-500 text-xs uppercase">
            <tr>
              <th className="px-4 py-3">Device name</th>
              <th>Status</th>
              <th>Warehouse</th>
              <th>Paired by</th>
              <th>Paired</th>
              <th>Last seen</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {rows.map((d) => (
              <tr key={d.deviceId} className="border-t border-slate-100">
                <td className="px-4 py-3">
                  <div className="font-medium">{d.deviceName}</div>
                  <div className="text-xs text-slate-400 font-mono">
                    {d.deviceId.slice(0, 8)}… · {d.manufacturer} {d.model}
                  </div>
                </td>
                <td>
                  <span
                    className={`text-xs px-2 py-0.5 rounded ${
                      d.status === 'Active'
                        ? 'bg-emerald-100 text-emerald-800'
                        : d.status === 'Pending'
                          ? 'bg-amber-100 text-amber-800'
                          : d.status === 'Revoked'
                            ? 'bg-rose-100 text-rose-800'
                            : 'bg-slate-100 text-slate-700'
                    }`}
                  >
                    {d.status}
                  </span>
                </td>
                <td className="font-mono text-xs">{d.defaultWarehouse || '—'}</td>
                <td className="font-mono text-xs">{d.pairedBy || '—'}</td>
                <td className="text-xs text-slate-500">{d.pairedAt ? new Date(d.pairedAt).toLocaleString() : '—'}</td>
                <td className="text-xs text-slate-500">{d.lastSeen ? new Date(d.lastSeen).toLocaleString() : '—'}</td>
                <td>
                  {d.status === 'Active' && (
                    <button
                      type="button"
                      onClick={() => onRevoke(d.deviceId)}
                      disabled={revoke.isPending}
                      className="text-xs px-3 py-1 rounded border border-rose-300 text-rose-700 hover:bg-rose-50 disabled:opacity-50"
                    >
                      Revoke
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </QueryState>
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
