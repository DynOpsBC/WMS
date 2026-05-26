import type { HttpRequest, InvocationContext, HttpResponseInit } from "@azure/functions";
import { WebPubSubServiceClient } from "@azure/web-pubsub";
import { verifyHmac } from "../shared/BcHmacVerifier.js";
import { FcmClient } from "../shared/FcmClient.js";
import { TenantRegistry } from "../shared/TenantRegistry.js";

export default async function webhook(
  request: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  const body = await request.text();
  const tenantId = request.query.get("tenant") ?? "default";
  const registry = TenantRegistry.fromEnv();
  const tenant = registry.get(tenantId);

  if (!verifyHmac(Object.fromEntries(request.headers.entries()), body, tenant.hmacSecret)) {
    return { status: 401, jsonBody: { ok: false, error: "invalid signature" } };
  }

  const event = JSON.parse(body || "{}");
  const type = event.type ?? event.eventType ?? "";

  if (type.startsWith("pick.")) {
    const client = new WebPubSubServiceClient(process.env.AzureSignalRConnectionString ?? "", tenant.signalRHub || "picks");
    await client.sendToAll(body, { contentType: "application/json" });
  } else {
    const fcm = new FcmClient();
    const tokens = Object.values(tenant.fcmTokens ?? {});
    await Promise.all(tokens.map((token) => fcm.send({
      token,
      title: "BCWMS update",
      body: type || "Warehouse update",
      data: Object.fromEntries(Object.entries(event).map(([key, value]) => [key, String(value)])),
    })));
  }

  return {
    status: 200,
    jsonBody: {
      ok: true,
    },
  };
}
