import * as Crypto from 'expo-crypto';

/** RFC4122 v4 UUID, used as the idempotency key / BC requestId. */
export function newRequestId(): string {
  return Crypto.randomUUID();
}
