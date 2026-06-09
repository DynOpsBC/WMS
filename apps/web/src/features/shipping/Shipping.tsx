export function Shipping() {
  return (
    <div className="max-w-6xl mx-auto">
      <h2 className="text-2xl font-semibold mb-4">Shipping & carriers</h2>
      <p className="text-sm text-slate-600 mb-6">
        Rate shopping (FedEx · UPS · USPS · DHL), label printing, tracking dashboard, manifest close (M6).
      </p>
      <div className="bg-white rounded-xl shadow p-6 text-sm text-slate-500">
        Dynamic-Ship parity. Carrier adapters live in BC AL behind a <code>WMS Carrier Adapter</code> interface.
      </div>
    </div>
  );
}
