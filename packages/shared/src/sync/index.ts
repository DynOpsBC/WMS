export const SYNC_LIMITS = {
  MAX_ATTEMPTS: 8,
  BASE_DELAY_MS: 2000,
  MAX_DELAY_MS: 5 * 60 * 1000,
} as const;

/**
 * Exponential backoff with full jitter, capped at MAX_DELAY_MS.
 * Returns an absolute epoch-ms timestamp for the next attempt.
 */
export function backoffDelay(
  attempt: number,
  now: number = Date.now(),
  rnd: () => number = Math.random,
): number {
  const exp = Math.min(SYNC_LIMITS.MAX_DELAY_MS, SYNC_LIMITS.BASE_DELAY_MS * 2 ** attempt);
  return now + Math.floor(rnd() * exp);
}

/** Whether an action should keep retrying given its attempt count and error class. */
export function shouldRetry(attempts: number, permanent: boolean): boolean {
  return !permanent && attempts < SYNC_LIMITS.MAX_ATTEMPTS;
}
