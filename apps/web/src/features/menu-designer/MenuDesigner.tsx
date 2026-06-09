import { useState } from 'react';

interface MenuItem {
  id: string;
  description: string;
  itemType: 'Sub-Menu' | 'Flow' | 'Inquiry' | 'Sign Out' | 'Change Warehouse';
  flowId?: string;
  childMenuCode?: string;
  icon?: string;
}

interface Menu {
  code: string;
  description: string;
  isRoot: boolean;
  items: MenuItem[];
}

const SAMPLE_MENU: Menu = {
  code: 'MAIN',
  description: 'Main menu',
  isRoot: true,
  items: [
    { id: '1', description: 'Receive', itemType: 'Sub-Menu', childMenuCode: 'INBOUND', icon: 'inbox' },
    { id: '2', description: 'Pick & Pack', itemType: 'Sub-Menu', childMenuCode: 'OUTBOUND', icon: 'box' },
    { id: '3', description: 'Movement', itemType: 'Flow', flowId: 'MOVEMENT', icon: 'arrows' },
    { id: '4', description: 'Cycle count', itemType: 'Flow', flowId: 'CYCLE-COUNT', icon: 'counter' },
    { id: '5', description: 'Inventory lookup', itemType: 'Inquiry', icon: 'search' },
    { id: '6', description: 'Change warehouse', itemType: 'Change Warehouse', icon: 'warehouse' },
    { id: '7', description: 'Sign out', itemType: 'Sign Out', icon: 'logout' },
  ],
};

const FLOW_CATALOG = [
  'PURCH-RECEIVE', 'LP-RECEIVE', 'MIXED-LP-RECEIVE', 'TRANSFER-RECEIVE', 'RMA-RECEIVE',
  'PUTAWAY', 'COMBINED-RECEIVE-PUTAWAY',
  'PICK', 'CLUSTER-PICK', 'PALLET-PICK', 'PACK', 'CONTAINER-CLOSE', 'SHIP',
  'MOVEMENT', 'MOVEMENT-TEMPLATE', 'TRANSFER',
  'CYCLE-COUNT', 'SPOT-COUNT', 'QUARANTINE', 'LP-LOAD',
  'RAF', 'PRODUCTION-PICK', 'KANBAN', 'ASSEMBLY-PICK',
];

export function MenuDesigner() {
  const [menu, setMenu] = useState<Menu>(SAMPLE_MENU);
  const [selected, setSelected] = useState<MenuItem | null>(menu.items[0] ?? null);

  function move(idx: number, dir: -1 | 1) {
    const next = [...menu.items];
    const target = idx + dir;
    if (target < 0 || target >= next.length) return;
    const a = next[idx];
    const b = next[target];
    if (!a || !b) return;
    next[idx] = b;
    next[target] = a;
    setMenu({ ...menu, items: next });
  }

  function addItem() {
    const id = String(Date.now());
    const it: MenuItem = { id, description: 'New item', itemType: 'Flow', flowId: 'PICK' };
    setMenu({ ...menu, items: [...menu.items, it] });
    setSelected(it);
  }

  function updateSelected(patch: Partial<MenuItem>) {
    if (!selected) return;
    const next = { ...selected, ...patch };
    setSelected(next);
    setMenu({ ...menu, items: menu.items.map((i) => (i.id === selected.id ? next : i)) });
  }

  return (
    <div className="max-w-6xl mx-auto">
      <h2 className="text-2xl font-semibold mb-2">Menu Designer</h2>
      <p className="text-sm text-slate-600 mb-4">
        Insight Works WMS App Designer parity. Drag-and-drop ordering, sub-menus, detours, and data inquiries
        rendered live to the mobile preview on the right.
      </p>
      <div className="grid grid-cols-12 gap-4">
        <section className="col-span-5 bg-white rounded-xl shadow p-4">
          <div className="flex justify-between items-center mb-3">
            <h3 className="font-semibold">{menu.description}</h3>
            <button
              type="button"
              onClick={addItem}
              className="text-sm bg-brand-500 hover:bg-brand-700 text-white px-3 py-1 rounded"
            >
              + Add item
            </button>
          </div>
          <ul className="space-y-1">
            {menu.items.map((it, idx) => (
              <li
                key={it.id}
                onClick={() => setSelected(it)}
                className={`p-2 rounded cursor-pointer border ${
                  selected?.id === it.id
                    ? 'border-brand-500 bg-brand-50'
                    : 'border-transparent hover:bg-slate-50'
                }`}
              >
                <div className="flex justify-between items-center">
                  <div>
                    <div className="font-medium text-sm">{it.description}</div>
                    <div className="text-xs text-slate-500 font-mono">
                      {it.itemType}
                      {it.flowId && ` · ${it.flowId}`}
                      {it.childMenuCode && ` → ${it.childMenuCode}`}
                    </div>
                  </div>
                  <div className="flex gap-1">
                    <button
                      type="button"
                      onClick={(e) => { e.stopPropagation(); move(idx, -1); }}
                      className="text-slate-400 hover:text-slate-700 px-1"
                    >↑</button>
                    <button
                      type="button"
                      onClick={(e) => { e.stopPropagation(); move(idx, 1); }}
                      className="text-slate-400 hover:text-slate-700 px-1"
                    >↓</button>
                  </div>
                </div>
              </li>
            ))}
          </ul>
        </section>
        <section className="col-span-4 bg-white rounded-xl shadow p-4">
          <h3 className="font-semibold mb-3">Item properties</h3>
          {selected ? (
            <div className="space-y-3">
              <label className="block text-xs text-slate-600">
                Description
                <input
                  className="mt-1 w-full border border-slate-300 rounded px-2 py-1 text-sm"
                  value={selected.description}
                  onChange={(e) => updateSelected({ description: e.target.value })}
                />
              </label>
              <label className="block text-xs text-slate-600">
                Type
                <select
                  className="mt-1 w-full border border-slate-300 rounded px-2 py-1 text-sm"
                  value={selected.itemType}
                  onChange={(e) => updateSelected({ itemType: e.target.value as MenuItem['itemType'] })}
                >
                  <option>Sub-Menu</option>
                  <option>Flow</option>
                  <option>Inquiry</option>
                  <option>Change Warehouse</option>
                  <option>Sign Out</option>
                </select>
              </label>
              {selected.itemType === 'Flow' && (
                <label className="block text-xs text-slate-600">
                  Flow ID
                  <select
                    className="mt-1 w-full border border-slate-300 rounded px-2 py-1 text-sm"
                    value={selected.flowId ?? ''}
                    onChange={(e) => updateSelected({ flowId: e.target.value })}
                  >
                    {FLOW_CATALOG.map((f) => <option key={f}>{f}</option>)}
                  </select>
                </label>
              )}
              {selected.itemType === 'Sub-Menu' && (
                <label className="block text-xs text-slate-600">
                  Child menu code
                  <input
                    className="mt-1 w-full border border-slate-300 rounded px-2 py-1 text-sm"
                    value={selected.childMenuCode ?? ''}
                    onChange={(e) => updateSelected({ childMenuCode: e.target.value })}
                  />
                </label>
              )}
            </div>
          ) : (
            <p className="text-sm text-slate-500">Select an item to edit.</p>
          )}
        </section>
        <section className="col-span-3">
          <h3 className="font-semibold mb-3 text-sm text-slate-600 text-center">Mobile preview</h3>
          <div className="bg-slate-900 rounded-3xl p-3 shadow-lg" style={{ aspectRatio: '9/19' }}>
            <div className="bg-slate-50 h-full rounded-2xl overflow-hidden flex flex-col">
              <div className="bg-brand-700 text-white text-sm font-medium px-3 py-2">
                {menu.description}
              </div>
              <ul className="flex-1 overflow-y-auto">
                {menu.items.map((it) => (
                  <li key={it.id} className="px-3 py-3 border-b border-slate-200 text-sm">
                    {it.description}
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}
