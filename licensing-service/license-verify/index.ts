import type { HttpRequest, InvocationContext, HttpResponseInit } from "@azure/functions";
import { verifyLicense } from "../shared/JwtSigner.js";
import { getLicense } from "../shared/LicenseStore.js";

type VerifyBody = {
  tenantId: string;
  key: string;
  // Optional for backward compatibility: the BCWMSApp extension predates multi-product
  // and sends only tenantId + key. Newer extensions (BCTraining onwards) send their
  // product name, and then a key minted for a different product is refused — without
  // this, one product's Enterprise key would unlock every product's paid tier.
  product?: string;
};

export default async function licenseVerify(
  request: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  const raw = await request.text();
  let body: VerifyBody;
  try {
    body = JSON.parse(raw) as VerifyBody;
  } catch {
    return { status: 400, jsonBody: { ok: false, error: "invalid JSON body" } };
  }
  if (!body.tenantId || !body.key) {
    return { status: 400, jsonBody: { ok: false, error: "tenantId and key are required" } };
  }

  try {
    const result = await verifyLicense(body.key, body.tenantId);
    if (!result.valid) {
      return {
        status: 200,
        jsonBody: { ok: true, valid: false, reason: result.reason },
      };
    }

    if (body.product && result.claims.product !== body.product) {
      return {
        status: 200,
        jsonBody: { ok: true, valid: false, reason: "product_mismatch" },
      };
    }

    // Cross-check storage status (revoked / superseded should fail even with valid signature).
    const record = await getLicense(body.tenantId, result.claims.sub).catch(() => null);
    if (record && record.status !== "active") {
      return { status: 200, jsonBody: { ok: true, valid: false, reason: record.status } };
    }

    return {
      status: 200,
      jsonBody: {
        ok: true,
        valid: true,
        tier: result.claims.tier,
        seats: result.claims.seats,
        product: result.claims.product,
        email: result.claims.email,
        tenantId: result.claims.tid,
        issuedAt: new Date(result.claims.iat * 1000).toISOString(),
        expiresAt: new Date(result.claims.exp * 1000).toISOString(),
        kid: result.claims.kid,
      },
    };
  } catch (err) {
    context.error("license/verify failed", err);
    return { status: 502, jsonBody: { ok: false, error: (err as Error).message } };
  }
}
