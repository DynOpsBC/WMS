import test from "node:test";
import assert from "node:assert/strict";
import { createHmac, randomBytes } from "node:crypto";
import { verifyPrinterSignature } from "../PrinterTokenRegistry.js";

const SECRET = "test-secret-1234";
const PRINTER = "WH-LP1";

function makeHeaders(body: string, nonce = randomBytes(12).toString("hex"), tsOverride?: number) {
  const ts = String(tsOverride ?? Math.floor(Date.now() / 1000));
  const sig = createHmac("sha256", SECRET).update(`${ts}.${nonce}.${body}`).digest("hex");
  return {
    "x-bcwms-timestamp": ts,
    "x-bcwms-nonce": nonce,
    "x-bcwms-signature": sig,
  };
}

test("signature — fresh nonce passes", () => {
  const body = "{}";
  const headers = makeHeaders(body);
  assert.equal(verifyPrinterSignature(headers, body, SECRET, PRINTER), true);
});

test("signature — replay with same nonce is rejected", () => {
  const body = "{}";
  const nonce = randomBytes(12).toString("hex");
  const headers = makeHeaders(body, nonce);
  assert.equal(verifyPrinterSignature(headers, body, SECRET, PRINTER), true);
  // Second call with the same nonce must fail (cache hit).
  assert.equal(verifyPrinterSignature(headers, body, SECRET, PRINTER), false);
});

test("signature — different printer with same nonce is allowed", () => {
  const body = "{}";
  const nonce = randomBytes(12).toString("hex");
  const headers = makeHeaders(body, nonce);
  assert.equal(verifyPrinterSignature(headers, body, SECRET, "PR-A"), true);
  // Cache key is per-printer, so a different printer can use the same nonce.
  assert.equal(verifyPrinterSignature(headers, body, SECRET, "PR-B"), true);
});

test("signature — clock skew >5min is rejected", () => {
  const body = "{}";
  const headers = makeHeaders(body, undefined, Math.floor(Date.now() / 1000) - 400);
  assert.equal(verifyPrinterSignature(headers, body, SECRET, PRINTER), false);
});

test("signature — missing nonce is rejected", () => {
  const body = "{}";
  const ts = String(Math.floor(Date.now() / 1000));
  const sig = createHmac("sha256", SECRET).update(`${ts}..${body}`).digest("hex");
  const headers = { "x-bcwms-timestamp": ts, "x-bcwms-signature": sig };
  assert.equal(verifyPrinterSignature(headers, body, SECRET, PRINTER), false);
});

test("signature — tampered body invalidates signature", () => {
  const body = "{}";
  const headers = makeHeaders(body);
  assert.equal(verifyPrinterSignature(headers, "{\"tampered\":true}", SECRET, PRINTER), false);
});
