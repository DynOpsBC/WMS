import type { HttpRequest, InvocationContext, HttpResponseInit } from "@azure/functions";
import { PrinterTokenRegistry, verifyPrinterSignature } from "../shared/PrinterTokenRegistry.js";
import { BcODataClient } from "../shared/BcODataClient.js";

export default async function printJobsStatus(
  request: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  const jobId = Number(request.params.jobId);
  const tenantId = request.query.get("tenant") ?? "default";
  const printerId = request.query.get("printer") ?? "";

  if (!jobId || !printerId) {
    return { status: 400, jsonBody: { ok: false, error: "jobId and printer required" } };
  }

  const body = await request.text();
  const registry = PrinterTokenRegistry.fromEnv();
  let tenant;
  try {
    tenant = registry.tenant(tenantId);
  } catch (err) {
    return { status: 404, jsonBody: { ok: false, error: (err as Error).message } };
  }
  const secret = tenant.printerSecrets[printerId];
  if (!secret) return { status: 404, jsonBody: { ok: false, error: `printer ${printerId} not registered` } };

  if (!verifyPrinterSignature(Object.fromEntries(request.headers.entries()), body, secret, printerId)) {
    return { status: 401, jsonBody: { ok: false, error: "invalid signature" } };
  }

  const payload = body ? (JSON.parse(body) as { status?: string; message?: string }) : {};
  const success = (payload.status ?? "").toLowerCase() === "sent";
  const message = (payload.message ?? "").slice(0, 250);
  try {
    const client = new BcODataClient(tenant);
    const ok = await client.markStatus(jobId, success, message);
    return { status: ok ? 200 : 502, jsonBody: { ok } };
  } catch (err) {
    context.error("BC OData status error", err);
    return { status: 502, jsonBody: { ok: false, error: (err as Error).message } };
  }
}
