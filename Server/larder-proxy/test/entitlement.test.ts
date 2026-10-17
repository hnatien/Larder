import { beforeAll, describe, expect, it } from "vitest";
import { APPLE_ROOT_CA_G3_PEM } from "../src/auth/appleRoot.js";
import { DerError, decodeOid, readRoot } from "../src/auth/der.js";
import { verifySignedTransaction } from "../src/auth/entitlement.js";
import { derSignatureToRaw, parseCertificate, pemToDer } from "../src/auth/x509.js";
import { toBase64Url } from "../src/encoding.js";
import { makeCert, makeChain, signTransaction, signXcodeTransaction, type TestChain } from "./helpers/certs.js";
import { BUNDLE_ID, NOW } from "./helpers/fixtures.js";

const validPayload = {
  bundleId: BUNDLE_ID,
  productId: "com.larder.plus.annual",
  expiresDate: NOW.getTime() + 30 * 86_400_000,
  signedDate: NOW.getTime() - 60_000,
};

describe("verifySignedTransaction", () => {
  let chain: TestChain;
  const verify = (jws: string | null, roots = [chain.rootPem], now = NOW, allowXcodeTransactions = false) =>
    verifySignedTransaction(jws, { now, appleRootPEMs: roots, bundleId: BUNDLE_ID, allowXcodeTransactions });
  const verifyAllowingXcode = (jws: string) => verify(jws, [chain.rootPem], NOW, true);

  beforeAll(async () => {
    chain = await makeChain();
  });

  it("grants Plus for a valid chain and active Plus product", async () => {
    expect(await verify(await signTransaction(chain, validPayload))).toEqual({ tier: "plus", reason: "verified" });
  });

  it("accepts the monthly product too", async () => {
    const jws = await signTransaction(chain, { ...validPayload, productId: "com.larder.plus.monthly" });
    expect((await verify(jws)).tier).toBe("plus");
  });

  it("treats an expired transaction as free", async () => {
    const jws = await signTransaction(chain, { ...validPayload, expiresDate: NOW.getTime() - 1 });
    expect(await verify(jws)).toEqual({ tier: "free", reason: "expired" });
  });

  it("treats a transaction without expiresDate as free", async () => {
    const { expiresDate: _omitted, ...withoutExpiry } = validPayload;
    expect(await verify(await signTransaction(chain, withoutExpiry))).toEqual({ tier: "free", reason: "expired" });
  });

  it("treats a wrong bundle id as free", async () => {
    const jws = await signTransaction(chain, { ...validPayload, bundleId: "com.example.other" });
    expect(await verify(jws)).toEqual({ tier: "free", reason: "wrong_bundle" });
  });

  it("treats a revoked transaction as free", async () => {
    const jws = await signTransaction(chain, { ...validPayload, revocationDate: NOW.getTime() - 1000 });
    expect(await verify(jws)).toEqual({ tier: "free", reason: "revoked" });
  });

  it("treats a non-Plus product as free", async () => {
    const jws = await signTransaction(chain, { ...validPayload, productId: "com.larder.tip.small" });
    expect(await verify(jws)).toEqual({ tier: "free", reason: "unknown_product" });
  });

  it("rejects a tampered payload signature", async () => {
    const jws = await signTransaction(chain, validPayload);
    const [header, , signature] = jws.split(".");
    const forgedPayload = toBase64Url(
      new TextEncoder().encode(JSON.stringify({ ...validPayload, expiresDate: NOW.getTime() + 9e11 })),
    );
    expect(await verify(`${header}.${forgedPayload}.${signature}`)).toEqual({ tier: "free", reason: "invalid_signature" });
  });

  it("rejects a root that is not trusted", async () => {
    const other = await makeChain();
    expect(await verify(await signTransaction(chain, validPayload), [other.rootPem])).toEqual({
      tier: "free",
      reason: "untrusted_root",
    });
  });

  it("does not trust the test chain under the real Apple root", async () => {
    expect((await verify(await signTransaction(chain, validPayload), [APPLE_ROOT_CA_G3_PEM])).reason).toBe(
      "untrusted_root",
    );
  });

  it("rejects an intermediate not signed by the trusted root", async () => {
    const impostor = await makeCert({ name: "Impostor", curve: "P-384" });
    const forged = await makeChain({ intermediate: { signingKeyOverride: impostor.keys.privateKey } });
    const jws = await signTransaction({ ...forged, root: chain.root }, validPayload);
    expect(await verify(jws)).toEqual({ tier: "free", reason: "invalid_chain" });
  });

  it("rejects a leaf without the Apple receipt-signing marker", async () => {
    const unmarked = await makeChain({ leaf: { extensionOids: [] } });
    expect(await verify(await signTransaction(unmarked, validPayload), [unmarked.rootPem])).toEqual({
      tier: "free",
      reason: "invalid_chain",
    });
  });

  it("rejects an intermediate without the Apple WWDR marker", async () => {
    const unmarked = await makeChain({ intermediate: { extensionOids: ["1.2.3.4"] } });
    expect(await verify(await signTransaction(unmarked, validPayload), [unmarked.rootPem])).toEqual({
      tier: "free",
      reason: "invalid_chain",
    });
  });

  it("rejects a chain with an expired certificate", async () => {
    const stale = await makeChain({ leaf: { notAfter: new Date(NOW.getTime() - 1000) } });
    expect(await verify(await signTransaction(stale, validPayload), [stale.rootPem])).toEqual({
      tier: "free",
      reason: "certificate_expired",
    });
  });

  it("rejects algorithms other than ES256", async () => {
    const jws = await signTransaction(chain, validPayload, { alg: "none" });
    expect(await verify(jws)).toEqual({ tier: "free", reason: "malformed" });
  });

  it.each([null, "", "a.b", "a.b.c", "!!!.???.***"])("treats %j as free without throwing", async (value) => {
    expect((await verify(value)).tier).toBe("free");
  });

  it("treats a non-certificate x5c entry as malformed", async () => {
    const jws = await signTransaction(chain, validPayload, { x5c: ["AAAA", "AAAA", "AAAA"] });
    expect(await verify(jws)).toEqual({ tier: "free", reason: "malformed" });
  });

  it("treats an Xcode StoreKit testing transaction as free unless allowed", async () => {
    expect(await verify(await signXcodeTransaction(validPayload))).toEqual({ tier: "free", reason: "xcode_not_allowed" });
  });

  it("grants Plus for an Xcode StoreKit testing transaction when allowed", async () => {
    expect(await verifyAllowingXcode(await signXcodeTransaction(validPayload))).toEqual({ tier: "plus", reason: "verified" });
  });

  it("still checks bundle, expiry, revocation and product on an allowed Xcode transaction", async () => {
    const cases = [
      [{ bundleId: "com.example.other" }, "wrong_bundle"],
      [{ expiresDate: NOW.getTime() - 1 }, "expired"],
      [{ revocationDate: NOW.getTime() - 1000 }, "revoked"],
      [{ productId: "com.larder.tip.small" }, "unknown_product"],
    ] as const;
    for (const [change, reason] of cases) {
      const jws = await signXcodeTransaction({ ...validPayload, ...change });
      expect(await verifyAllowingXcode(jws)).toEqual({ tier: "free", reason });
    }
  });

  it("keeps the Apple chain check for other environments when Xcode transactions are allowed", async () => {
    const jws = await signXcodeTransaction({ ...validPayload, environment: "Production" });
    expect(await verifyAllowingXcode(jws)).toEqual({ tier: "free", reason: "malformed" });
  });
});

describe("DER and X.509 parsing", () => {
  it("parses the embedded Apple Root CA - G3 and matches Apple's published fingerprint", async () => {
    const der = pemToDer(APPLE_ROOT_CA_G3_PEM);
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", der));
    const hex = Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
    expect(hex).toBe("63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179");
    const cert = parseCertificate(der);
    expect(cert.curve).toBe("P-384");
    expect(cert.signatureHash).toBe("SHA-384");
    expect(cert.notBefore.toISOString()).toBe("2014-04-30T18:19:06.000Z");
    expect(cert.notAfter.toISOString()).toBe("2039-04-30T18:19:06.000Z");
  });

  it("decodes multi-byte OID arcs", () => {
    const node = readRoot(new Uint8Array([0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x0b, 0x01]));
    expect(decodeOid(node)).toBe("1.2.840.113635.100.6.11.1");
  });

  it("rejects truncated and indefinite-length input", () => {
    expect(() => readRoot(new Uint8Array([0x30, 0x05, 0x02]))).toThrow(DerError);
    expect(() => readRoot(new Uint8Array([0x30, 0x80, 0x00, 0x00]))).toThrow(DerError);
    expect(() => readRoot(new Uint8Array([0x02, 0x01, 0x00, 0xff]))).toThrow(DerError);
  });

  it("left-pads short ECDSA integers and strips sign bytes when converting to raw", () => {
    const der = new Uint8Array([0x30, 0x07, 0x02, 0x02, 0x00, 0x80, 0x02, 0x01, 0x01]);
    const raw = derSignatureToRaw(der, 4);
    expect(Array.from(raw)).toEqual([0, 0, 0, 0x80, 0, 0, 0, 1]);
  });
});
