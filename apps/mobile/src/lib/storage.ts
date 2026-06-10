import { MMKV } from 'react-native-mmkv';

export const storage = new MMKV({ id: 'bcwmsapp' });

interface StoredSession {
  accessToken: string;
  refreshToken?: string;
  expiresAt: string;
  username: string;
  name: string;
  objectId: string;
}

export const SessionStore = {
  save(s: StoredSession) {
    storage.set('session', JSON.stringify(s));
  },
  load(): StoredSession | null {
    const raw = storage.getString('session');
    if (!raw) return null;
    try {
      return JSON.parse(raw) as StoredSession;
    } catch {
      return null;
    }
  },
  clear() {
    storage.delete('session');
  },
};
