import { TableClient, TableServiceClient } from "@azure/data-tables";
import { DefaultAzureCredential } from "@azure/identity";
import { randomUUID } from "node:crypto";

export type LicenseRecord = {
  partitionKey: string; // tenantId (lowercased)
  rowKey: string;       // license id (uuid)
  tier: "Essentials" | "Advanced" | "Enterprise";
  seats: number;
  product: string;
  email: string;
  status: "active" | "revoked" | "superseded";
  issuedAt: string;     // ISO
  validUntil: string;   // ISO
  history?: string;     // optional JSON-encoded history blob
};

const TABLE = "licenses";

let cached: TableClient | null = null;

async function table(): Promise<TableClient> {
  if (cached) return cached;
  const conn = process.env.LICENSE_STORAGE_CONNECTION;
  const account = process.env.LICENSE_STORAGE_ACCOUNT;
  if (!conn && !account) throw new Error("LICENSE_STORAGE_CONNECTION or LICENSE_STORAGE_ACCOUNT must be set");

  if (conn) {
    cached = TableClient.fromConnectionString(conn, TABLE, { allowInsecureConnection: conn.includes("UseDevelopmentStorage") });
  } else {
    const url = `https://${account}.table.core.windows.net`;
    const credential = new DefaultAzureCredential();
    // Best-effort create; ignore "already exists" 409.
    const service = new TableServiceClient(url, credential);
    try { await service.createTable(TABLE); } catch { /* ignored */ }
    cached = new TableClient(url, TABLE, credential);
  }
  try { await cached.createTable(); } catch { /* ignored */ }
  return cached;
}

export async function createLicense(input: Omit<LicenseRecord, "rowKey" | "issuedAt" | "status"> & {
  id?: string;
  issuedAt?: string;
}): Promise<LicenseRecord> {
  const t = await table();
  const id = input.id ?? randomUUID();
  const record: LicenseRecord = {
    partitionKey: input.partitionKey.toLowerCase(),
    rowKey: id,
    tier: input.tier,
    seats: input.seats,
    product: input.product,
    email: input.email,
    status: "active",
    issuedAt: input.issuedAt ?? new Date().toISOString(),
    validUntil: input.validUntil,
    history: input.history,
  };
  await t.createEntity(record);
  return record;
}

export async function getLicense(tenantId: string, id: string): Promise<LicenseRecord | null> {
  const t = await table();
  try {
    return (await t.getEntity<LicenseRecord>(tenantId.toLowerCase(), id)) as LicenseRecord;
  } catch (err) {
    if ((err as { statusCode?: number }).statusCode === 404) return null;
    throw err;
  }
}

export async function listActiveByTenant(tenantId: string): Promise<LicenseRecord[]> {
  const t = await table();
  const records: LicenseRecord[] = [];
  for await (const entity of t.listEntities<LicenseRecord>({
    queryOptions: { filter: `PartitionKey eq '${tenantId.toLowerCase()}' and status eq 'active'` },
  })) {
    records.push(entity as LicenseRecord);
  }
  return records;
}

export async function supersedeActive(tenantId: string): Promise<void> {
  const t = await table();
  for (const record of await listActiveByTenant(tenantId)) {
    await t.updateEntity({ ...record, status: "superseded" }, "Merge");
  }
}

export async function revoke(tenantId: string, id: string, reason: string): Promise<void> {
  const t = await table();
  const existing = await getLicense(tenantId, id);
  if (!existing) return;
  await t.updateEntity({
    ...existing,
    status: "revoked",
    history: appendHistory(existing.history, { event: "revoked", reason, at: new Date().toISOString() }),
  }, "Merge");
}

function appendHistory(existing: string | undefined, entry: Record<string, unknown>): string {
  const arr = existing ? (JSON.parse(existing) as Record<string, unknown>[]) : [];
  arr.push(entry);
  return JSON.stringify(arr);
}
