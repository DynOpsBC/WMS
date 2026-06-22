import { createHmac, timingSafeEqual } from "node:crypto";

export type PrinterRegistryConfig = {
  defaultTenant?: string;
  tenants: Record<string, TenantPrinters>;
};

export type TenantPrinters = {
  bcBaseUrl: string;
  bcCompanyId: string;
  bcBearer: string;
  printerSecrets: Record<string, string>;
};

export class PrinterTokenRegistry {
  static fromEnv(): PrinterTokenRegistry {
    const raw = process.env.PRINT_TENANT_CONFIG_JSON ?? "{}";
    const parsed = JSON.parse(raw) as PrinterRegistryConfig;
    return new PrinterTokenRegistry(parsed);
  }

  constructor(private readonly config: PrinterRegistryConfig) {}

  tenant(tenantId: string): TenantPrinters {
    const key = tenantId || this.config.defaultTenant || "default";
    const tenant = this.config.tenants[key];
    if (!tenant) throw new Error(`Print tenant not configured: ${key}`);
    return tenant;
  }

  secretFor(tenantId: string, printerId: string): string | undefined {
    return this.tenant(tenantId).printerSecrets[printerId];
  }
}

// 5-minute nonce cache prevents replay within the timestamp tolerance window.
// Stores `${printerId}:${nonce}` until the timestamp window closes.
const seenNonces = new Map<string, number>();
const NONCE_TTL_MS = 5 * 60 * 1000;

function rememberNonce(key: string): boolean {
  const now = Date.now();
  // Lazy GC: clear entries older than TTL on every check.
  for (const [k, ts] of seenNonces) {
    if (now - ts > NONCE_TTL_MS) seenNonces.delete(k);
  }
  if (seenNonces.has(key)) return false;
  seenNonces.set(key, now);
  return true;
}

export function verifyPrinterSignature(
  headers: Record<string, string | string[] | undefined>,
  body: string,
  secret: string,
  printerId?: string,
): boolean {
  const sig = header(headers, "x-bcwms-signature");
  const ts = header(headers, "x-bcwms-timestamp");
  const nonce = header(headers, "x-bcwms-nonce");
  if (!sig || !ts || !nonce || !secret) return false;
  const tsNum = Number(ts);
  if (!Number.isFinite(tsNum)) return false;
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - tsNum) > 300) return false;

  // Signature input now includes the nonce so a captured request cannot
  // be replayed once the nonce is consumed.
  const expected = createHmac("sha256", secret).update(`${ts}.${nonce}.${body}`).digest("hex");
  if (!safeEquals(sig, expected)) return false;
  const cacheKey = `${printerId ?? ""}:${nonce}`;
  return rememberNonce(cacheKey);
}

function header(headers: Record<string, string | string[] | undefined>, key: string): string | undefined {
  const value = headers[key] ?? headers[key.toLowerCase()];
  return Array.isArray(value) ? value[0] : value;
}

function safeEquals(a: string, b: string): boolean {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}
