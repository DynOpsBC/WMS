import { useState } from 'react';
import { Dashboard } from './features/dashboard/Dashboard.tsx';
import { LoginScreen } from './features/auth/LoginScreen.tsx';

export default function App() {
  const [signedIn, setSignedIn] = useState(false);

  return (
    <div className="min-h-screen flex flex-col">
      <header className="bg-brand-700 text-white px-6 py-3 flex items-center justify-between shadow">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 bg-brand-500 rounded" aria-hidden />
          <h1 className="font-semibold tracking-tight text-lg">BCWMSApp</h1>
        </div>
        <span className="text-xs text-brand-100">
          M0 scaffold · BC SaaS · v0.1.0
        </span>
      </header>
      <main className="flex-1 p-6">
        {signedIn ? <Dashboard /> : <LoginScreen onSignedIn={() => setSignedIn(true)} />}
      </main>
    </div>
  );
}
