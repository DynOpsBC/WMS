import { BcApiError, BcClient, BcOfflineError, SYNC_LIMITS, backoffDelay } from '@bcwmsapp/shared';
import { OfflineQueue, type QueuedAction } from './offlineQueue';

export type SyncStatus = 'idle' | 'syncing' | 'offline' | 'error';

export interface SyncState {
  status: SyncStatus;
  pending: number;
  lastSyncedAt: string | null;
  lastError: string | null;
}

type Listener = (s: SyncState) => void;

const { MAX_ATTEMPTS, BASE_DELAY_MS, MAX_DELAY_MS } = SYNC_LIMITS;

/**
 * Drains the offline queue into BC. The single piece that actually makes the
 * mobile app synchronize: every completed flow lands here and is POSTed to the
 * `wmsActionRequests` endpoint with idempotency + retry/backoff.
 *
 * - Network failures (`BcOfflineError`) → flips to "offline", retries with backoff.
 * - Transient HTTP (5xx/429) → retries with backoff.
 * - Permanent HTTP (4xx) → after MAX_ATTEMPTS the action is dropped to a dead state
 *   (kept in queue with status surfaced) so it never blocks the rest.
 */
export class SyncEngine {
  private listeners = new Set<Listener>();
  private running = false;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private state: SyncState = {
    status: 'idle',
    pending: OfflineQueue.size(),
    lastSyncedAt: null,
    lastError: null,
  };

  constructor(private readonly client: BcClient) {}

  subscribe(l: Listener): () => void {
    this.listeners.add(l);
    l(this.state);
    return () => this.listeners.delete(l);
  }

  getState(): SyncState {
    return this.state;
  }

  /** Kick a drain pass. Safe to call often (foreground, connectivity regained, after enqueue). */
  async flush(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      await this.drain();
    } finally {
      this.running = false;
      this.scheduleNext();
    }
  }

  /** Begin periodic flushing. */
  start(): void {
    void this.flush();
  }

  stop(): void {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
  }

  private async drain(): Promise<void> {
    let action: QueuedAction | undefined;
    while ((action = OfflineQueue.nextDue())) {
      this.patch({ status: 'syncing', pending: OfflineQueue.size() });
      try {
        const result = await this.client.submitAction(action.request);
        if (result.status === 'Failed') {
          // BC processed it but the business operation failed — permanent.
          OfflineQueue.recordFailure(action.requestId, result.resultMessage, Number.MAX_SAFE_INTEGER);
          this.patch({ status: 'error', lastError: result.resultMessage });
          continue;
        }
        OfflineQueue.remove(action.requestId);
        this.patch({
          status: 'idle',
          pending: OfflineQueue.size(),
          lastSyncedAt: new Date().toISOString(),
          lastError: null,
        });
      } catch (e) {
        const permanent = e instanceof BcApiError && !e.retryable;
        const attempts = action.attempts + 1;
        const msg = e instanceof Error ? e.message : String(e);

        if (permanent || attempts >= MAX_ATTEMPTS) {
          OfflineQueue.recordFailure(action.requestId, msg, Number.MAX_SAFE_INTEGER);
          this.patch({ status: 'error', lastError: msg, pending: OfflineQueue.size() });
          continue;
        }

        const next = backoffDelay(attempts);
        OfflineQueue.recordFailure(action.requestId, msg, next);
        this.patch({
          status: e instanceof BcOfflineError ? 'offline' : 'error',
          lastError: msg,
          pending: OfflineQueue.size(),
        });
        // Stop this pass; the timer will pick up due items later.
        return;
      }
    }
    if (OfflineQueue.size() === 0) {
      this.patch({ status: 'idle', pending: 0 });
    }
  }

  private scheduleNext(): void {
    if (this.timer) clearTimeout(this.timer);
    const next = OfflineQueue.nextDue(0);
    if (!next) return; // nothing queued
    const delay = Math.max(0, next.nextAttemptAt - Date.now());
    this.timer = setTimeout(() => void this.flush(), Math.min(delay || BASE_DELAY_MS, MAX_DELAY_MS));
  }

  private patch(p: Partial<SyncState>): void {
    this.state = { ...this.state, ...p };
    for (const l of this.listeners) l(this.state);
  }
}
