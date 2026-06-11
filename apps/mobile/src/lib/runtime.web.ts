// Web shim: use navigator.onLine + an `online` event listener instead of expo-network polling.
import { BcApiError, BcClient } from '@bcwmsapp/shared';
import { auth } from './auth';
import { loadDevice, markRevoked } from './device';
import { SyncEngine } from './syncEngine';

const env = {
  tenantId: process.env.EXPO_PUBLIC_BC_TENANT_ID ?? '',
  environmentName: process.env.EXPO_PUBLIC_BC_ENVIRONMENT ?? 'Production',
  companyId: process.env.EXPO_PUBLIC_BC_COMPANY_ID ?? '',
};

export const bcClient = new BcClient({ env, getAccessToken: auth.getAccessToken });
export const syncEngine = new SyncEngine(bcClient);

let onlineHandler: (() => void) | null = null;
let heartbeatTimer: ReturnType<typeof setInterval> | null = null;

export function startRuntime(): void {
  syncEngine.start();
  if (!onlineHandler) {
    onlineHandler = () => { void syncEngine.flush(); };
    window.addEventListener('online', onlineHandler);
  }
  if (!heartbeatTimer) {
    heartbeatTimer = setInterval(() => void sendHeartbeat(), 60_000);
    void sendHeartbeat();
  }
}

export function stopRuntime(): void {
  syncEngine.stop();
  if (onlineHandler) {
    window.removeEventListener('online', onlineHandler);
    onlineHandler = null;
  }
  if (heartbeatTimer) clearInterval(heartbeatTimer);
  heartbeatTimer = null;
}

async function sendHeartbeat(): Promise<void> {
  const d = loadDevice();
  if (!d || d.status !== 'active') return;
  try {
    await bcClient.recordHeartbeat(d.deviceId, '0.1.0');
  } catch (e) {
    if (e instanceof BcApiError && (e.status === 404 || e.status === 410)) {
      markRevoked();
    }
  }
}
