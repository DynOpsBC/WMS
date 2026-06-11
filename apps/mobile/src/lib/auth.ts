import * as AuthSession from 'expo-auth-session';
import * as WebBrowser from 'expo-web-browser';
import { SessionStore } from './storage';

WebBrowser.maybeCompleteAuthSession();

const tenantId = process.env.EXPO_PUBLIC_ENTRA_TENANT_ID ?? '';
const clientId = process.env.EXPO_PUBLIC_ENTRA_CLIENT_ID ?? '';

const discovery: AuthSession.DiscoveryDocument = {
  authorizationEndpoint: `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/authorize`,
  tokenEndpoint: `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`,
  // Device-code endpoint (RFC 8628) — used by the one-time admin pairing.
  ...({ deviceAuthorizationEndpoint: `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/devicecode` } as Record<string, string>),
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

/**
 * Interactive PKCE flow. Used by the web target for admin-side pairing.
 * On hand-held devices we prefer `startDeviceCode` so the admin can sign in
 * on a separate trusted computer without ever touching the warehouse device.
 */
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

export interface DeviceCodeChallenge {
  /** Short alphanumeric code shown to the admin. */
  userCode: string;
  /** URL the admin visits in a browser. */
  verificationUri: string;
  /** Seconds until the challenge expires. */
  expiresInSec: number;
  /** Poll interval to check whether the admin has completed sign-in. */
  intervalSec: number;
  /** Internal handle — keep it to poll for the token. */
  deviceCode: string;
}

interface DeviceCodeResponse {
  user_code: string;
  device_code: string;
  verification_uri: string;
  verification_uri_complete?: string;
  expires_in: number;
  interval: number;
}

interface TokenResponse {
  access_token?: string;
  refresh_token?: string;
  id_token?: string;
  expires_in?: number;
  error?: string;
  error_description?: string;
}

/** Start an Entra ID Device Code Flow. The admin will see the code + url in the app. */
export async function startDeviceCode(): Promise<DeviceCodeChallenge> {
  if (!tenantId || !clientId) {
    throw new Error('Entra ID not configured');
  }
  const url = `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/devicecode`;
  const body = new URLSearchParams({ client_id: clientId, scope: SCOPES.join(' ') });
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });
  if (!res.ok) throw new Error(`Device-code request failed: ${res.status}`);
  const j = (await res.json()) as DeviceCodeResponse;
  return {
    userCode: j.user_code,
    verificationUri: j.verification_uri_complete ?? j.verification_uri,
    expiresInSec: j.expires_in,
    intervalSec: j.interval,
    deviceCode: j.device_code,
  };
}

/**
 * Poll the token endpoint until the admin has completed sign-in (or the challenge expires).
 * Returns the established session. `signal` lets the caller cancel early.
 */
export async function awaitDeviceCode(challenge: DeviceCodeChallenge, signal?: AbortSignal): Promise<AuthSessionData> {
  const tokenUrl = `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`;
  const deadline = Date.now() + challenge.expiresInSec * 1000;
  let interval = challenge.intervalSec;

  while (Date.now() < deadline) {
    if (signal?.aborted) throw new Error('Pairing cancelled');
    await new Promise((r) => setTimeout(r, interval * 1000));

    const body = new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
      client_id: clientId,
      device_code: challenge.deviceCode,
    });
    const res = await fetch(tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
    });
    const j = (await res.json()) as TokenResponse;

    if (res.ok && j.access_token) {
      const expiresInMs = (j.expires_in ?? 3600) * 1000;
      const claims = decodeIdToken(j.id_token);
      const session: AuthSessionData = {
        accessToken: j.access_token,
        ...(j.refresh_token ? { refreshToken: j.refresh_token } : {}),
        expiresAt: new Date(Date.now() + expiresInMs).toISOString(),
        username: claims.preferred_username ?? '',
        name: claims.name ?? claims.preferred_username ?? 'Admin',
        objectId: claims.oid ?? '',
      };
      SessionStore.save(session);
      return session;
    }

    // Standard polling-error handling.
    switch (j.error) {
      case 'authorization_pending':
        continue;
      case 'slow_down':
        interval += 5;
        continue;
      case 'expired_token':
        throw new Error('Pairing challenge expired. Start again.');
      case 'authorization_declined':
        throw new Error('Pairing was declined.');
      default:
        if (j.error) throw new Error(`Pairing failed: ${j.error_description ?? j.error}`);
    }
  }
  throw new Error('Pairing timed out.');
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
  const expired = new Date(s.expiresAt).getTime() < Date.now() + 60_000;
  if (!expired) return s.accessToken;
  if (!s.refreshToken) throw new Error('Session expired — re-pair the device');
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
  startDeviceCode,
  awaitDeviceCode,
  tenantId,
  clientId,
  redirectUri,
  configured: Boolean(tenantId && clientId),
};
