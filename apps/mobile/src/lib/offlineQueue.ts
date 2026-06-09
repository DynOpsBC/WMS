import { storage } from './storage';

export type QueuedAction =
  | { type: 'POST'; path: string; body: unknown; idempotencyKey: string; queuedAt: string }
  | { type: 'PATCH'; path: string; body: unknown; idempotencyKey: string; queuedAt: string };

const QUEUE_KEY = 'bcwms.actionQueue';

function read(): QueuedAction[] {
  const raw = storage.getString(QUEUE_KEY);
  if (!raw) return [];
  try {
    return JSON.parse(raw) as QueuedAction[];
  } catch {
    return [];
  }
}

function write(q: QueuedAction[]): void {
  storage.set(QUEUE_KEY, JSON.stringify(q));
}

export const OfflineQueue = {
  enqueue(action: Omit<QueuedAction, 'queuedAt'>): void {
    const q = read();
    q.push({ ...action, queuedAt: new Date().toISOString() } as QueuedAction);
    write(q);
  },
  peek(): QueuedAction | undefined {
    return read()[0];
  },
  pop(): QueuedAction | undefined {
    const q = read();
    const first = q.shift();
    write(q);
    return first;
  },
  size(): number {
    return read().length;
  },
  list(): QueuedAction[] {
    return read();
  },
  clear(): void {
    write([]);
  },
};
