import { storage } from './storage';
import type { WmsActionRequest } from '@bcwmsapp/shared';

export interface QueuedAction {
  /** Idempotency key — also the BC requestId. */
  requestId: string;
  request: WmsActionRequest;
  queuedAt: string;
  attempts: number;
  lastError?: string;
  /** Epoch ms; the sync engine won't retry before this (backoff). */
  nextAttemptAt: number;
}

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
  /** Enqueue a flow submission. De-dupes on requestId. */
  enqueue(request: WmsActionRequest): void {
    const q = read();
    if (q.some((a) => a.requestId === request.requestId)) return;
    q.push({
      requestId: request.requestId,
      request,
      queuedAt: new Date().toISOString(),
      attempts: 0,
      nextAttemptAt: 0,
    });
    write(q);
  },

  /** Next action that is due (nextAttemptAt <= now), FIFO. */
  nextDue(now = Date.now()): QueuedAction | undefined {
    return read().find((a) => a.nextAttemptAt <= now);
  },

  /** Remove a successfully-synced (or permanently-failed) action. */
  remove(requestId: string): void {
    write(read().filter((a) => a.requestId !== requestId));
  },

  /** Record a failed attempt + schedule the next retry. */
  recordFailure(requestId: string, error: string, nextAttemptAt: number): void {
    const q = read();
    const a = q.find((x) => x.requestId === requestId);
    if (!a) return;
    a.attempts += 1;
    a.lastError = error;
    a.nextAttemptAt = nextAttemptAt;
    write(q);
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
