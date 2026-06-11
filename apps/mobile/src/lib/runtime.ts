import { BcApiError, BcClient } from '@bcwmsapp/shared';
import * as Network from 'expo-network';
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

let netPoll: ReturnType<typeof setInterval> | null = null;
let heartbeatTimer: ReturnType<typeof setInterval> | null = null;
let lastOnline = true;

/** Start sync + connectivity + heartbeat. Call once after the device is paired. */
export function startRuntime(): void {
  syncEngine.start();

  if (!netPoll) {
    netPoll = setInterval(async () => {
      try {
        const state = await Network.getNetworkStateAsync();
        const online = Boolean(state.isConnected && state.isInternetReachable !== false);
        if (online && !lastOnline) void syncEngine.flush();
        lastOnline = online;
      } catch {
        /* ignore */
      }
    }, 5000);
  }

  if (!heartbeatTimer) {
    // Send a heartbeat every 60s. Surfaces remote revocation quickly.
    heartbeatTimer = setInterval(() => void sendHeartbeat(), 60_000);
    void sendHeartbeat();
  }
}

export function stopRuntime(): void {
  syncEngine.stop();
  if (netPoll) clearInterval(netPoll);
  if (heartbeatTimer) clearInterval(heartbeatTimer);
  netPoll = null;
  heartbeatTimer = null;
}

async function sendHeartbeat(): Promise<void> {
  const d = loadDevice();
  if (!d || d.status !== 'active') return;
  try {
    await bcClient.recordHeartbeat(d.deviceId, '0.1.0');
  } catch (e) {
    // 404/410 → device was revoked or deleted on the server.
    if (e instanceof BcApiError && (e.status === 404 || e.status === 410)) {
      markRevoked();
    }
    // Other errors are transient.
  }
}
