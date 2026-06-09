import { SessionStore } from '../storage';

const tenantId = process.env.EXPO_PUBLIC_ENTRA_TENANT_ID!;
const clientId = process.env.EXPO_PUBLIC_ENTRA_CLIENT_ID!;
const redirectUri = 'bcwmsapp://auth';

export interface AuthSession {
  accessToken: string;
  expiresAt: string;
  username: string;
  name: string;
  objectId: string;
}

const BC_SCOPE = 'https://api.businesscentral.dynamics.com/.default';

/**
 * Entra ID PKCE flow.
 *
 * Implementation lives in M1.5: wraps expo-auth-session/providers/microsoft
 * with the authority `https://login.microsoftonline.com/{tenantId}/v2.0`
 * and the scopes `[BC_SCOPE, 'offline_access']`. The returned token is
 * cached via SessionStore and refreshed silently on expiry.
 *
 * The placeholder below short-circuits with a fake session so the rest of
 * the app can be exercised offline.
 */
export async function signIn(): Promise<AuthSession> {
  const session: AuthSession = {
    accessToken: 'PLACEHOLDER',
    expiresAt: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    username: 'demo@dynopsbc.com',
    name: 'Demo Worker',
    objectId: '00000000-0000-0000-0000-000000000001',
  };
  SessionStore.save(session);
  return session;
}

export function signOut(): void {
  SessionStore.clear();
}

export function loadSession(): AuthSession | null {
  return SessionStore.load();
}

export async function getAccessToken(): Promise<string> {
  const s = SessionStore.load();
  if (!s) throw new Error('Not signed in');
  if (new Date(s.expiresAt).getTime() < Date.now()) {
    throw new Error('Session expired — re-authenticate');
  }
  return s.accessToken;
}

export const auth = { signIn, signOut, loadSession, getAccessToken, tenantId, clientId, redirectUri, BC_SCOPE };
