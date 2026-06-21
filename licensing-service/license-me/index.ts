import type { HttpRequest, InvocationContext, HttpResponseInit } from "@azure/functions";
import { listActiveByTenant } from "../shared/LicenseStore.js";

export default async function licenseMe(
  request: HttpRequest,
  _context: InvocationContext,
): Promise<HttpResponseInit> {
  const tenantId = request.query.get("tenant");
  if (!tenantId) {
    return { status: 400, jsonBody: { ok: false, error: "missing 'tenant' query" } };
  }

  const records = await listActiveByTenant(tenantId);
  if (records.length === 0) {
    return {
      status: 200,
      headers: { "Cache-Control": "private, max-age=300" },
      jsonBody: { ok: true, tenantId, active: null },
    };
  }

  records.sort((a, b) => (a.validUntil > b.validUntil ? -1 : 1));
  const current = records[0];

  return {
    status: 200,
    headers: { "Cache-Control": "private, max-age=300" },
    jsonBody: {
      ok: true,
      tenantId,
      active: {
        id: current.rowKey,
        tier: current.tier,
        seats: current.seats,
        product: current.product,
        email: current.email,
        issuedAt: current.issuedAt,
        validUntil: current.validUntil,
        status: current.status,
      },
    },
  };
}
