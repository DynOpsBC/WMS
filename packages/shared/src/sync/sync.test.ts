import { describe, expect, it } from 'vitest';
import { SYNC_LIMITS, backoffDelay, shouldRetry } from './index';

describe('backoffDelay', () => {
  it('grows exponentially with attempt count', () => {
    // rnd=1 → full window; compare ceilings across attempts.
    const at = (n: number) => backoffDelay(n, 0, () => 1);
    expect(at(0)).toBeLessThan(at(1));
    expect(at(1)).toBeLessThan(at(2));
  });

  it('never exceeds the cap', () => {
    const d = backoffDelay(20, 0, () => 1);
    expect(d).toBeLessThanOrEqual(SYNC_LIMITS.MAX_DELAY_MS);
  });

  it('applies jitter (rnd=0 → no extra delay)', () => {
    expect(backoffDelay(5, 1000, () => 0)).toBe(1000);
  });
});

describe('shouldRetry', () => {
  it('stops on permanent errors', () => {
    expect(shouldRetry(1, true)).toBe(false);
  });
  it('stops after max attempts', () => {
    expect(shouldRetry(SYNC_LIMITS.MAX_ATTEMPTS, false)).toBe(false);
  });
  it('retries transient errors under the cap', () => {
    expect(shouldRetry(2, false)).toBe(true);
  });
});
