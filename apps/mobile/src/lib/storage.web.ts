// Web shim: localStorage instead of MMKV. Same shape so the rest of the app
// (SessionStore, OfflineQueue) doesn't have to know which target it's on.

interface KvStore {
  set(key: string, value: string): void;
  getString(key: string): string | undefined;
  delete(key: string): void;
}

const hasLs = typeof window !== 'undefined' && typeof window.localStorage !== 'undefined';
const mem = new Map<string, string>();

class LocalStorageKv implements KvStore {
  set(key: string, value: string): void {
    if (hasLs) { try { window.localStorage.setItem(`bcwmsapp.${key}`, value); } catch { /* quota */ } }
    else mem.set(key, value);
  }
  getString(key: string): string | undefined {
    if (hasLs) {
      const v = window.localStorage.getItem(`bcwmsapp.${key}`);
      return v === null ? undefined : v;
    }
    return mem.get(key);
  }
  delete(key: string): void {
    if (hasLs) window.localStorage.removeItem(`bcwmsapp.${key}`);
    else mem.delete(key);
  }
}

export const storage: KvStore = new LocalStorageKv();

interface StoredSession {
  accessToken: string;
  refreshToken?: string;
  expiresAt: string;
  username: string;
  name: string;
  objectId: string;
}

export const SessionStore = {
  save(s: StoredSession) { storage.set('session', JSON.stringify(s)); },
  load(): StoredSession | null {
    const raw = storage.getString('session');
    if (!raw) return null;
    try { return JSON.parse(raw) as StoredSession; } catch { return null; }
  },
  clear() { storage.delete('session'); },
};
