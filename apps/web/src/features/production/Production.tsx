export function Production() {
  return (
    <div className="max-w-6xl mx-auto">
      <h2 className="text-2xl font-semibold mb-4">Production shop floor</h2>
      <p className="text-sm text-slate-600 mb-6">
        Released production orders, kanban refill signals, output / scrap capture (M5).
      </p>
      <div className="bg-white rounded-xl shadow p-6 text-sm text-slate-500">
        Wires to <code>/wmsProductionOrders</code> + standard BC <code>productionOrders</code>.
      </div>
    </div>
  );
}
