import { PublicClientApplication, type Configuration } from '@azure/msal-browser';

const tenantId = import.meta.env.VITE_ENTRA_TENANT_ID;
const clientId = import.meta.env.VITE_ENTRA_CLIENT_ID;

const msalConfig: Configuration = {
  auth: {
    clientId,
    authority: `https://login.microsoftonline.com/${tenantId}`,
    redirectUri: window.location.origin,
    postLogoutRedirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: 'sessionStorage',
    storeAuthStateInCookie: false,
  },
};

export const BC_SCOPE = 'https://api.businesscentral.dynamics.com/.default';

export const msalInstance = new PublicClientApplication(msalConfig);

export async function getAccessToken(): Promise<string> {
  const accounts = msalInstance.getAllAccounts();
  if (accounts.length === 0) {
    throw new Error('Not signed in');
  }
  const result = await msalInstance.acquireTokenSilent({
    scopes: [BC_SCOPE],
    account: accounts[0],
  });
  return result.accessToken;
}
