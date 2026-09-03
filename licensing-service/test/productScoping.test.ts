// Multi-product scoping: the service is the shared licensing spine for the DynOpsBC
// family (BCWMSApp, BCTraining), and these tests pin the three behaviours that keep the
// products from stepping on each other — issue rejects unknown products, replaceActive
// supersedes only its own product, and verify refuses a key minted for another product.

import "./setup.js";
import test from "node:test";
import assert from "node:assert/strict";
import type { HttpRequest, InvocationContext } from "@azure/functions";

const { handleIssue } = await import("../license-issue/index.js");
const { signLicense } = await import("../shared/JwtSigner.js");
const licenseVerify = (await import("../license-verify/index.js")).default;
import type { IssueDeps } from "../license-issue/index.js";

function makeRequest(body: unknown, headers: Record<string, string> = {}): HttpRequest {
  const all: Record<string, string> = { "x-bcwms-admin-token": "test-admin-token", ...headers };
  return {
    text: async () => JSON.stringify(body),
    headers: { get: (name: string) => all[name.toLowerCase()] ?? null },
    query: { get: () => null },
  } as unknown as HttpRequest;
}

const context = { error: () => undefined } as unknown as InvocationContext;

function makeDeps() {
  const superseded: Array<{ tenantId: string; product?: string }> = [];
  const created: Array<Record<string, unknown>> = [];
  const deps: IssueDeps = {
    isAdminAuthorized: (request) => (request.headers.get("x-bcwms-admin-token") ?? "") === "test-admin-token",
    createLicense: async (input) => {
      created.push(input as Record<string, unknown>);
      return {
        partitionKey: String(input.partitionKey).toLowerCase(),
        rowKey: String(input.id ?? "rk-1"),
        tier: input.tier,
        seats: input.seats,
        product: input.product,
        email: input.email,
        status: "active",
        issuedAt: new Date().toISOString(),
        validUntil: input.validUntil,
      };
    },
    supersedeActive: async (tenantId, product) => {
      superseded.push({ tenantId, product });
    },
  };
  return { deps, superseded, created };
}

const future = new Date(Date.now() + 86_400_000).toISOString();

test("issue — accepts BCTraining as a product", async () => {
  const { deps, created } = makeDeps();
  const res = await handleIssue(
    makeRequest({ tenantId: "tenant-1", product: "BCTraining", tier: "Advanced", seats: 5, validUntil: future, customerEmail: "x@y.z" }),
    context,
    deps,
  );
  assert.equal(res.status, 200);
  assert.equal(created[0]?.product, "BCTraining");
});

test("issue — rejects an unknown product with the known list in the error", async () => {
  const { deps } = makeDeps();
  const res = await handleIssue(
    makeRequest({ tenantId: "tenant-1", product: "BCTrainning", tier: "Advanced", seats: 5, validUntil: future, customerEmail: "x@y.z" }),
    context,
    deps,
  );
  assert.equal(res.status, 400);
  const body = res.jsonBody as { error: string };
  assert.match(body.error, /unknown product 'BCTrainning'/);
  assert.match(body.error, /BCWMSApp/);
  assert.match(body.error, /BCTraining/);
});

test("issue — replaceActive supersedes only the issued product", async () => {
  const { deps, superseded } = makeDeps();
  const res = await handleIssue(
    makeRequest({ tenantId: "tenant-1", product: "BCTraining", tier: "Essentials", seats: 1, validUntil: future, customerEmail: "x@y.z", replaceActive: true }),
    context,
    deps,
  );
  assert.equal(res.status, 200);
  assert.deepEqual(superseded, [{ tenantId: "tenant-1", product: "BCTraining" }]);
});

test("verify — refuses a key minted for another product", async () => {
  const { jwt } = await signLicense({
    sub: "lic-1",
    tid: "tenant-1",
    product: "BCWMSApp",
    tier: "Enterprise",
    seats: 99,
    email: "x@y.z",
    validUntil: Math.floor(Date.now() / 1000) + 3600,
  });
  // No storage env is set in tests: the store cross-check inside the handler throws,
  // is caught, and is skipped — which is exactly the code path under test here.
  const res = await licenseVerify(
    makeRequest({ tenantId: "tenant-1", key: jwt, product: "BCTraining" }),
    context,
  );
  assert.equal(res.status, 200);
  const body = res.jsonBody as { valid: boolean; reason?: string };
  assert.equal(body.valid, false);
  assert.equal(body.reason, "product_mismatch");
});

test("verify — same product passes, and legacy callers without a product still pass", async () => {
  const { jwt } = await signLicense({
    sub: "lic-2",
    tid: "tenant-1",
    product: "BCTraining",
    tier: "Advanced",
    seats: 10,
    email: "x@y.z",
    validUntil: Math.floor(Date.now() / 1000) + 3600,
  });

  const withProduct = await licenseVerify(makeRequest({ tenantId: "tenant-1", key: jwt, product: "BCTraining" }), context);
  assert.equal((withProduct.jsonBody as { valid: boolean }).valid, true);
  assert.equal((withProduct.jsonBody as { product: string }).product, "BCTraining");

  // The shipped BCWMSApp extension sends only tenantId + key; it must keep working.
  const legacy = await licenseVerify(makeRequest({ tenantId: "tenant-1", key: jwt }), context);
  assert.equal((legacy.jsonBody as { valid: boolean }).valid, true);
});
