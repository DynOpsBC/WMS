import { BcClient } from '@bcwmsapp/shared';
import * as Network from 'expo-network';
import { auth } from './auth';
import { SyncEngine } from './syncEngine';

const env = {
  tenantId: process.env.EXPO_PUBLIC_BC_TENANT_ID ?? '',
  environmentName: process.env.EXPO_PUBLIC_BC_ENVIRONMENT ?? 'Production',
  companyId: process.env.EXPO_PUBLIC_BC_COMPANY_ID ?? '',
};

export const bcClient = new BcClient({ env, getAccessToken: auth.getAccessToken });
export const syncEngine = new SyncEngine(bcClient);

let netPoll: ReturnType<typeof setInterval> | null = null;
let lastOnline = true;

/** Start sync + connectivity watching. Call once after sign-in. */
export function startRuntime(): void {
  syncEngine.start();
  if (netPoll) return;
  netPoll = setInterval(async () => {
    try {
      const state = await Network.getNetworkStateAsync();
      const online = Boolean(state.isConnected && state.isInternetReachable !== false);
      if (online && !lastOnline) {
        // Connectivity regained → drain immediately.
        void syncEngine.flush();
      }
      lastOnline = online;
    } catch {
      /* ignore */
    }
  }, 5000);
}

export function stopRuntime(): void {
  syncEngine.stop();
  if (netPoll) clearInterval(netPoll);
  netPoll = null;
}
