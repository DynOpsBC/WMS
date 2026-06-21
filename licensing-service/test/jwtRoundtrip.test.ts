import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";

const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
process.env.LICENSE_PRIVATE_KEY_PEM = privateKey.export({ type: "pkcs8", format: "pem" }) as string;
process.env.LICENSE_PUBLIC_KEY_PEM = publicKey.export({ type: "spki", format: "pem" }) as string;
process.env.LICENSE_SIGNING_KID = "test";

const { signLicense, verifyLicense } = await import("../shared/JwtSigner.js");

test("sign + verify round trip — valid", async () => {
  const exp = Math.floor(Date.now() / 1000) + 3600;
  const { jwt, claims } = await signLicense({
    sub: "abc",
    tid: "tenant-1",
    product: "BCWMSApp",
    tier: "Advanced",
    seats: 12,
    email: "ops@example.com",
    validUntil: exp,
  });
  const result = await verifyLicense(jwt, "tenant-1");
  assert.equal(result.valid, true);
  if (result.valid) {
    assert.equal(result.claims.tier, "Advanced");
    assert.equal(result.claims.seats, 12);
    assert.equal(result.claims.tid, "tenant-1");
    assert.equal(result.claims.sub, "abc");
    assert.equal(result.claims.exp, exp);
    assert.equal(claims.kid, "test");
  }
});

test("verify — tenant mismatch", async () => {
  const { jwt } = await signLicense({
    sub: "a",
    tid: "tenant-A",
    product: "BCWMSApp",
    tier: "Essentials",
    seats: 1,
    email: "x@x",
    validUntil: Math.floor(Date.now() / 1000) + 100,
  });
  const result = await verifyLicense(jwt, "tenant-B");
  assert.equal(result.valid, false);
  if (!result.valid) assert.equal(result.reason, "tenant_mismatch");
});

test("verify — expired", async () => {
  const exp = Math.floor(Date.now() / 1000) - 10;
  const { jwt } = await signLicense({
    sub: "a",
    tid: "t",
    product: "p",
    tier: "Essentials",
    seats: 1,
    email: "e",
    validFrom: exp - 100,
    validUntil: exp,
  });
  const result = await verifyLicense(jwt, "t");
  assert.equal(result.valid, false);
  if (!result.valid) assert.equal(result.reason, "expired");
});

test("sign — rejects validUntil <= iat", async () => {
  const now = Math.floor(Date.now() / 1000);
  await assert.rejects(
    () =>
      signLicense({
        sub: "a",
        tid: "t",
        product: "p",
        tier: "Essentials",
        seats: 1,
        email: "e",
        validFrom: now,
        validUntil: now,
      }),
    /validUntil/,
  );
});

test("verify — bad signature", async () => {
  const { jwt } = await signLicense({
    sub: "a",
    tid: "t",
    product: "p",
    tier: "Essentials",
    seats: 1,
    email: "e",
    validUntil: Math.floor(Date.now() / 1000) + 100,
  });
  const tampered = jwt.replace(/.$/, (c) => (c === "a" ? "b" : "a"));
  const result = await verifyLicense(tampered, "t");
  assert.equal(result.valid, false);
});

test("verify — malformed", async () => {
  const result = await verifyLicense("not.a.jwt-payload", "t");
  assert.equal(result.valid, false);
  if (!result.valid) assert.equal(result.reason, "format");
});
