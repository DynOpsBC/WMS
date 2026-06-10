// Web shim: use navigator.onLine + an `online` event listener instead of expo-network polling.
import { BcClient } from '@bcwmsapp/shared';
import { auth } from './auth';
import { SyncEngine } from './syncEngine';

const env = {
  tenantId: process.env.EXPO_PUBLIC_BC_TENANT_ID ?? '',
  environmentName: process.env.EXPO_PUBLIC_BC_ENVIRONMENT ?? 'Production',
  companyId: process.env.EXPO_PUBLIC_BC_COMPANY_ID ?? '',
};

export const bcClient = new BcClient({ env, getAccessToken: auth.getAccessToken });
export const syncEngine = new SyncEngine(bcClient);

let onlineHandler: (() => void) | null = null;

export function startRuntime(): void {
  syncEngine.start();
  if (onlineHandler) return;
  onlineHandler = () => { void syncEngine.flush(); };
  window.addEventListener('online', onlineHandler);
}

export function stopRuntime(): void {
  syncEngine.stop();
  if (onlineHandler) {
    window.removeEventListener('online', onlineHandler);
    onlineHandler = null;
  }
}
