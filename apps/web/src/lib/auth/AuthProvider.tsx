import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import type { AccountInfo } from '@azure/msal-browser';
import { msalInstance, BC_SCOPE } from './msal.ts';

interface AuthContextValue {
  account: AccountInfo | null;
  signIn: () => Promise<void>;
  signOut: () => Promise<void>;
  ready: boolean;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [account, setAccount] = useState<AccountInfo | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    msalInstance
      .initialize()
      .then(() => msalInstance.handleRedirectPromise())
      .then(() => {
        const all = msalInstance.getAllAccounts();
        setAccount(all[0] ?? null);
        setReady(true);
      })
      .catch(() => setReady(true));
  }, []);

  async function signIn() {
    const result = await msalInstance.loginPopup({ scopes: [BC_SCOPE] });
    setAccount(result.account ?? null);
  }

  async function signOut() {
    await msalInstance.logoutPopup();
    setAccount(null);
  }

  return (
    <AuthContext.Provider value={{ account, signIn, signOut, ready }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
  return ctx;
}
