import type { HttpRequest, InvocationContext, HttpResponseInit } from "@azure/functions";
import { PrinterTokenRegistry, verifyPrinterSignature } from "../shared/PrinterTokenRegistry.js";
import { BcODataClient } from "../shared/BcODataClient.js";

export default async function printJobsGet(
  request: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  const printerId = request.query.get("printer") ?? "";
  const tenantId = request.query.get("tenant") ?? "default";
  const top = Number(request.query.get("top") ?? "10");

  if (!printerId) {
    return { status: 400, jsonBody: { ok: false, error: "missing 'printer' query" } };
  }

  const registry = PrinterTokenRegistry.fromEnv();
  let tenant;
  try {
    tenant = registry.tenant(tenantId);
  } catch (err) {
    return { status: 404, jsonBody: { ok: false, error: (err as Error).message } };
  }

  const secret = tenant.printerSecrets[printerId];
  if (!secret) {
    return { status: 404, jsonBody: { ok: false, error: `printer ${printerId} not registered` } };
  }

  const headers = Object.fromEntries(request.headers.entries());
  const body = ""; // GET has no body — sign empty string
  if (!verifyPrinterSignature(headers, body, secret, printerId)) {
    return { status: 401, jsonBody: { ok: false, error: "invalid signature" } };
  }

  try {
    const client = new BcODataClient(tenant);
    const jobs = await client.listQueued(printerId, Number.isFinite(top) ? top : 10);
    return { status: 200, jsonBody: { ok: true, jobs } };
  } catch (err) {
    context.error("BC OData error", err);
    return { status: 502, jsonBody: { ok: false, error: (err as Error).message } };
  }
}
