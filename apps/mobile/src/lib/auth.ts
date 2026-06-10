import * as AuthSession from 'expo-auth-session';
import * as WebBrowser from 'expo-web-browser';
import { SessionStore } from './storage';

WebBrowser.maybeCompleteAuthSession();

const tenantId = process.env.EXPO_PUBLIC_ENTRA_TENANT_ID ?? '';
const clientId = process.env.EXPO_PUBLIC_ENTRA_CLIENT_ID ?? '';

const discovery: AuthSession.DiscoveryDocument = {
  authorizationEndpoint: `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/authorize`,
  tokenEndpoint: `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`,
};

const BC_SCOPE = 'https://api.businesscentral.dynamics.com/user_impersonation';
const SCOPES = [BC_SCOPE, 'offline_access', 'openid', 'profile'];

const redirectUri = AuthSession.makeRedirectUri({ scheme: 'bcwmsapp', path: 'auth' });

export interface AuthSessionData {
  accessToken: string;
  refreshToken?: string;
  expiresAt: string;
  username: string;
  name: string;
  objectId: string;
}

interface JwtClaims {
  preferred_username?: string;
  name?: string;
  oid?: string;
}

function decodeIdToken(idToken?: string): JwtClaims {
  if (!idToken) return {};
  try {
    const payload = idToken.split('.')[1];
    if (!payload) return {};
    const json = atob(payload.replace(/-/g, '+').replace(/_/g, '/'));
    return JSON.parse(json) as JwtClaims;
  } catch {
    return {};
  }
}

function persist(token: AuthSession.TokenResponse, claims: JwtClaims): AuthSessionData {
  const expiresInMs = (token.expiresIn ?? 3600) * 1000;
  const session: AuthSessionData = {
    accessToken: token.accessToken,
    ...(token.refreshToken ? { refreshToken: token.refreshToken } : {}),
    expiresAt: new Date(Date.now() + expiresInMs).toISOString(),
    username: claims.preferred_username ?? '',
    name: claims.name ?? claims.preferred_username ?? 'Worker',
    objectId: claims.oid ?? '',
  };
  SessionStore.save(session);
  return session;
}

/** Interactive Entra ID sign-in using PKCE (Authorization Code + code_verifier). */
export async function signIn(): Promise<AuthSessionData> {
  if (!tenantId || !clientId) {
    throw new Error('Entra ID not configured: set EXPO_PUBLIC_ENTRA_TENANT_ID and EXPO_PUBLIC_ENTRA_CLIENT_ID');
  }

  const request = new AuthSession.AuthRequest({
    clientId,
    scopes: SCOPES,
    redirectUri,
    usePKCE: true,
    extraParams: { prompt: 'select_account' },
  });

  const result = await request.promptAsync(discovery);
  if (result.type !== 'success' || !result.params['code']) {
    throw new Error(`Sign-in ${result.type}`);
  }

  const token = await AuthSession.exchangeCodeAsync(
    {
      clientId,
      code: result.params['code'],
      redirectUri,
      extraParams: { code_verifier: request.codeVerifier ?? '' },
    },
    discovery,
  );

  return persist(token, decodeIdToken(token.idToken));
}

export function signOut(): void {
  SessionStore.clear();
}

export function loadSession(): AuthSessionData | null {
  return SessionStore.load();
}

/** Returns a valid bearer token, silently refreshing via the refresh token when expired. */
export async function getAccessToken(): Promise<string> {
  const s = SessionStore.load();
  if (!s) throw new Error('Not signed in');

  const expired = new Date(s.expiresAt).getTime() < Date.now() + 60_000; // 60s skew
  if (!expired) return s.accessToken;

  if (!s.refreshToken) throw new Error('Session expired — re-authenticate');

  const refreshed = await AuthSession.refreshAsync(
    { clientId, refreshToken: s.refreshToken, scopes: SCOPES },
    discovery,
  );
  const next = persist(refreshed, decodeIdToken(refreshed.idToken));
  return next.accessToken;
}

export const auth = {
  signIn,
  signOut,
  loadSession,
  getAccessToken,
  tenantId,
  clientId,
  redirectUri,
  configured: Boolean(tenantId && clientId),
};
