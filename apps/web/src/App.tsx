import { useState } from 'react';
import { Dashboard } from './features/dashboard/Dashboard.tsx';
import { Setup } from './features/setup/Setup.tsx';
import { MenuDesigner } from './features/menu-designer/MenuDesigner.tsx';
import { Receipts } from './features/inbound/Receipts.tsx';
import { Shipments } from './features/outbound/Shipments.tsx';
import { Counts } from './features/counts/Counts.tsx';
import { Production } from './features/production/Production.tsx';
import { Shipping } from './features/shipping/Shipping.tsx';
import { AuthProvider, useAuth } from './lib/auth/AuthProvider.tsx';
import { LoginScreen } from './features/auth/LoginScreen.tsx';

type Route =
  | 'dashboard'
  | 'setup'
  | 'menu-designer'
  | 'receipts'
  | 'shipments'
  | 'counts'
  | 'production'
  | 'shipping';

const NAV: Array<{ id: Route; label: string }> = [
  { id: 'dashboard', label: 'Dashboard' },
  { id: 'setup', label: 'Setup' },
  { id: 'menu-designer', label: 'Menu Designer' },
  { id: 'receipts', label: 'Receipts' },
  { id: 'shipments', label: 'Shipments' },
  { id: 'counts', label: 'Counts' },
  { id: 'production', label: 'Production' },
  { id: 'shipping', label: 'Shipping' },
];

function Shell() {
  const { account, signIn, signOut, ready } = useAuth();
  const [route, setRoute] = useState<Route>('dashboard');

  if (!ready) return null;
  if (!account) return <LoginScreen onSignedIn={() => signIn()} />;

  return (
    <div className="min-h-screen flex flex-col">
      <header className="bg-brand-700 text-white px-6 py-3 flex items-center justify-between shadow">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 bg-brand-500 rounded" aria-hidden />
          <h1 className="font-semibold tracking-tight text-lg">BCWMSApp</h1>
        </div>
        <div className="flex items-center gap-4 text-sm">
          <span className="text-brand-100">{account.username}</span>
          <button
            type="button"
            onClick={() => signOut()}
            className="px-3 py-1 bg-brand-900 hover:bg-brand-500 rounded text-xs"
          >
            Sign out
          </button>
        </div>
      </header>
      <div className="flex flex-1">
        <nav className="w-56 bg-white border-r border-slate-200 py-4">
          {NAV.map((n) => (
            <button
              key={n.id}
              type="button"
              onClick={() => setRoute(n.id)}
              className={`block w-full text-left px-4 py-2 text-sm transition ${
                route === n.id
                  ? 'bg-brand-50 text-brand-700 font-medium border-l-4 border-brand-500'
                  : 'text-slate-700 hover:bg-slate-50'
              }`}
            >
              {n.label}
            </button>
          ))}
        </nav>
        <main className="flex-1 p-6 bg-slate-50">
          {route === 'dashboard' && <Dashboard />}
          {route === 'setup' && <Setup />}
          {route === 'menu-designer' && <MenuDesigner />}
          {route === 'receipts' && <Receipts />}
          {route === 'shipments' && <Shipments />}
          {route === 'counts' && <Counts />}
          {route === 'production' && <Production />}
          {route === 'shipping' && <Shipping />}
        </main>
      </div>
    </div>
  );
}

export default function App() {
  return (
    <AuthProvider>
      <Shell />
    </AuthProvider>
  );
}
