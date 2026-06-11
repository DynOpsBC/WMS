import * as Crypto from 'expo-crypto';
import { storage } from './storage';

export type PairingStatus = 'unpaired' | 'active' | 'revoked';

export interface PairedDevice {
  /** Locally-generated UUID; persisted forever on first run. */
  deviceId: string;
  deviceName: string;
  manufacturer: string;
  model: string;
  /** BC SystemId of the WMS Mobile Device record. */
  deviceSystemId?: string;
  /** BC company SystemId the device is bound to. */
  companyId?: string;
  /** ISO timestamp of the successful pairing. */
  pairedAt?: string;
  /** Username of the admin who paired the device. */
  pairedBy?: string;
  defaultWarehouse?: string;
  status: PairingStatus;
}

const KEY = 'device';

/** Read or lazily-generate the device record. The deviceId is created once and never changes. */
export function getOrCreateDevice(defaults?: Partial<PairedDevice>): PairedDevice {
  const raw = storage.getString(KEY);
  if (raw) {
    try {
      return JSON.parse(raw) as PairedDevice;
    } catch {
      /* fall through to create */
    }
  }
  const created: PairedDevice = {
    deviceId: Crypto.randomUUID(),
    deviceName: defaults?.deviceName ?? 'Unnamed device',
    manufacturer: defaults?.manufacturer ?? 'Other',
    model: defaults?.model ?? '',
    status: 'unpaired',
  };
  storage.set(KEY, JSON.stringify(created));
  return created;
}

export function loadDevice(): PairedDevice | null {
  const raw = storage.getString(KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as PairedDevice;
  } catch {
    return null;
  }
}

export function saveDevice(d: PairedDevice): void {
  storage.set(KEY, JSON.stringify(d));
}

export function markPaired(patch: {
  deviceName: string;
  deviceSystemId: string;
  companyId: string;
  pairedBy: string;
  defaultWarehouse: string;
}): PairedDevice {
  const current = getOrCreateDevice();
  const updated: PairedDevice = {
    ...current,
    ...patch,
    status: 'active',
    pairedAt: new Date().toISOString(),
  };
  saveDevice(updated);
  return updated;
}

export function markRevoked(): void {
  const current = loadDevice();
  if (!current) return;
  saveDevice({ ...current, status: 'revoked' });
}

export function clearDevice(): void {
  storage.delete(KEY);
}
