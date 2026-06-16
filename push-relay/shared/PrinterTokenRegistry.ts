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

export function verifyPrinterSignature(
  headers: Record<string, string | string[] | undefined>,
  body: string,
  secret: string,
): boolean {
  const sig = header(headers, "x-bcwms-signature");
  const ts = header(headers, "x-bcwms-timestamp");
  if (!sig || !ts || !secret) return false;
  const tsNum = Number(ts);
  if (!Number.isFinite(tsNum)) return false;
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - tsNum) > 300) return false;
  const expected = createHmac("sha256", secret).update(`${ts}.${body}`).digest("hex");
  return safeEquals(sig, expected);
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
