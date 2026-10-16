import { beforeAll, describe, expect, it, vi } from "vitest";
import { APPLE_APP_ATTESTATION_ROOT_CA_PEM } from "../src/auth/appleRoot.js";
import { verifyAssertion, verifyAttestation, type AppAttestContext } from "../src/auth/appAttest.js";
import { attestedKeyStorageKey, subjectForKey } from "../src/auth/attestation.js";
import { CborError, decodeCbor } from "../src/auth/cbor.js";
import { CHALLENGE_TTL_SECONDS, clientDataHash, issueChallenge, verifyChallenge } from "../src/auth/challenge.js";
import { issueSessionToken, verifySessionToken } from "../src/auth/session.js";
import { parseCertificate, pemToDer } from "../src/auth/x509.js";
import { fromBase64, fromBase64Url, toBase64 } from "../src/encoding.js";
import {
  DEVELOPMENT_AAGUID,
  encodeCbor,
  makeAssertion,
  makeAttestation,
  makeAttestCA,
  makeDeviceKey,
  type AttestCA,
  type CborInput,
  type DeviceKey,
} from "./helpers/appAttest.js";
import { makeCert } from "./helpers/certs.js";
import { BUNDLE_ID, makeHarness, NOW, post, SIGNING_KEY, TEAM_ID } from "./helpers/fixtures.js";

const APP_ID = `${TEAM_ID}.${BUNDLE_ID}`;

describe("CBOR reader", () => {
  it("decodes the shapes App Attest uses", () => {
    const input = new Map<string, CborInput>([["a", [1, 300, 70_000]], ["b", new Uint8Array([9])], ["c", "text"]]);
    expect(decodeCbor(encodeCbor(input))).toEqual(input);
  });

  it.each([
    ["trailing bytes", new Uint8Array([0x01, 0x02])],
    ["indefinite-length bytes", new Uint8Array([0x5f, 0x41, 0x00, 0xff])],
    ["a length past the end", new Uint8Array([0x45, 0x00])],
    ["a non-text map key", new Uint8Array([0xa1, 0x01, 0x01])],
    ["a duplicate map key", new Uint8Array([0xa2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02])],
    ["a tag", new Uint8Array([0xc0, 0x01])],
    ["a negative integer", new Uint8Array([0x20])],
    ["invalid UTF-8", new Uint8Array([0x61, 0xff])],
    ["empty input", new Uint8Array([])],
  ])("rejects %s", (_name, bytes) => {
    expect(() => decodeCbor(bytes)).toThrow(CborError);
  });

  it("rejects nesting deeper than any App Attest object", () => {
    const deep = new Uint8Array([...Array(20).fill(0x81), 0x00]);
    expect(() => decodeCbor(deep)).toThrow(/too deep/);
  });
});

describe("challenges", () => {
  it("verifies a fresh challenge until it expires", async () => {
    const { challenge, expiresAt } = await issueChallenge(SIGNING_KEY, NOW);
    expect(expiresAt).toBe(new Date(NOW.getTime() + CHALLENGE_TTL_SECONDS * 1000).toISOString());
    expect(await verifyChallenge(challenge, SIGNING_KEY, NOW)).toBe(true);
    expect(await verifyChallenge(challenge, SIGNING_KEY, new Date(expiresAt))).toBe(false);
  });

  it("issues a different challenge every time", async () => {
    const [a, b] = await Promise.all([issueChallenge(SIGNING_KEY, NOW), issueChallenge(SIGNING_KEY, NOW)]);
    expect(a.challenge).not.toBe(b.challenge);
  });

  it("rejects an extended expiry, another key and a session token", async () => {
    const { challenge } = await issueChallenge(SIGNING_KEY, NOW);
    const [random, exp, mac] = challenge.split(".") as [string, string, string];
    expect(await verifyChallenge(`${random}.${Number(exp) + 3600}.${mac}`, SIGNING_KEY, NOW)).toBe(false);
    expect(await verifyChallenge(challenge, `${SIGNING_KEY}-other`, NOW)).toBe(false);
    const { token } = await issueSessionToken(SIGNING_KEY, NOW);
    expect(await verifyChallenge(token, SIGNING_KEY, NOW)).toBe(false);
  });

  it.each(["", "a.b.c", "x".repeat(300)])("rejects malformed challenge %#", async (challenge) => {
    expect(await verifyChallenge(challenge, SIGNING_KEY, NOW)).toBe(false);
  });
});

describe("verifyAttestation", () => {
  let ca: AttestCA;
  let device: DeviceKey;
  const challenge = "test-challenge";
  const context = (): AppAttestContext => ({ appId: APP_ID, environment: "production", rootPEMs: [ca.rootPem], now: NOW });
  const verify = async (attestation: string, overrides: Partial<AppAttestContext> = {}, keyId = device.keyId) =>
    verifyAttestation(
      { keyId, attestationObject: fromBase64(attestation), clientDataHash: await clientDataHash(challenge) },
      { ...context(), ...overrides },
    );

  beforeAll(async () => {
    ca = await makeAttestCA();
    device = await makeDeviceKey();
  });

  it("accepts a valid attestation and returns the credential key with counter zero", async () => {
    const result = await verify(await makeAttestation(ca, device, challenge, APP_ID));
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.key.counter).toBe(0);
    const spki = new Uint8Array((await crypto.subtle.exportKey("spki", device.keys.publicKey)) as ArrayBuffer);
    expect(result.key.spki).toEqual(spki);
  });

  it("accepts the development AAGUID only in the development environment", async () => {
    const attestation = await makeAttestation(ca, device, challenge, APP_ID, { aaguid: DEVELOPMENT_AAGUID });
    expect((await verify(attestation, { environment: "development" })).ok).toBe(true);
    expect(await verify(attestation)).toEqual({ ok: false, reason: "wrong_environment" });
  });

  it("rejects a chain from another root", async () => {
    const other = await makeAttestCA();
    expect(await verify(await makeAttestation(other, device, challenge, APP_ID))).toEqual({ ok: false, reason: "untrusted_root" });
  });

  it("rejects a credential certificate not issued by the intermediate", async () => {
    const rogue = await makeCert({ name: "Rogue", curve: "P-384", hash: "SHA-384" });
    const attestation = await makeAttestation(ca, device, challenge, APP_ID, { credentialIssuer: rogue });
    expect(await verify(attestation)).toEqual({ ok: false, reason: "invalid_chain" });
  });

  it("rejects an expired credential certificate", async () => {
    const attestation = await makeAttestation(ca, device, challenge, APP_ID, { credentialNotAfter: new Date(NOW.getTime() - 1000) });
    expect(await verify(attestation)).toEqual({ ok: false, reason: "certificate_expired" });
  });

  it("rejects an attestation made for another challenge", async () => {
    expect(await verify(await makeAttestation(ca, device, "other-challenge", APP_ID))).toEqual({ ok: false, reason: "nonce_mismatch" });
  });

  it("rejects a certificate whose nonce was altered", async () => {
    const attestation = await makeAttestation(ca, device, challenge, APP_ID, { nonce: new Uint8Array(32) });
    expect(await verify(attestation)).toEqual({ ok: false, reason: "nonce_mismatch" });
  });

  it("rejects a key id that is not the credential public key's hash", async () => {
    const other = await makeDeviceKey();
    const attestation = await makeAttestation(ca, device, challenge, APP_ID, { credentialId: other.keyId });
    expect(await verify(attestation, {}, other.keyId)).toEqual({ ok: false, reason: "key_id_mismatch" });
  });

  it("rejects a credential id that differs from the key id", async () => {
    const attestation = await makeAttestation(ca, device, challenge, APP_ID, { credentialId: new Uint8Array(32) });
    expect(await verify(attestation)).toEqual({ ok: false, reason: "key_id_mismatch" });
  });

  it("rejects authenticator data without attested credential data", async () => {
    const attestation = await makeAttestation(ca, device, challenge, APP_ID, { flags: 0 });
    expect(await verify(attestation)).toEqual({ ok: false, reason: "key_id_mismatch" });
  });

  it("rejects another app's attestation", async () => {
    const attestation = await makeAttestation(ca, device, challenge, APP_ID, { appId: `${TEAM_ID}.com.example.other` });
    expect(await verify(attestation)).toEqual({ ok: false, reason: "wrong_app" });
  });

  it("rejects a non-zero counter", async () => {
    expect(await verify(await makeAttestation(ca, device, challenge, APP_ID, { counter: 1 }))).toEqual({ ok: false, reason: "bad_counter" });
  });

  it("rejects another attestation format", async () => {
    expect(await verify(await makeAttestation(ca, device, challenge, APP_ID, { fmt: "packed" }))).toEqual({ ok: false, reason: "wrong_format" });
  });

  it("rejects an x5c that is not exactly credential and intermediate", async () => {
    const attestation = await makeAttestation(ca, device, challenge, APP_ID, { x5c: (credential) => [credential] });
    expect(await verify(attestation)).toEqual({ ok: false, reason: "malformed" });
  });

  it.each([
    ["not CBOR", new Uint8Array([0xff])],
    ["a CBOR array", encodeCbor([1])],
    ["no authData", encodeCbor(new Map<string, CborInput>([["fmt", "apple-appattest"], ["attStmt", new Map([["x5c", []]])]]))],
  ])("rejects %s", async (_name, bytes) => {
    expect(await verify(toBase64(bytes))).toEqual({ ok: false, reason: "malformed" });
  });

  it("trusts the embedded Apple root only for Apple-issued chains", async () => {
    const apple = parseCertificate(pemToDer(APPLE_APP_ATTESTATION_ROOT_CA_PEM));
    expect(apple.curve).toBe("P-384");
    const attestation = await makeAttestation(ca, device, challenge, APP_ID);
    expect(await verify(attestation, { rootPEMs: [APPLE_APP_ATTESTATION_ROOT_CA_PEM] })).toEqual({ ok: false, reason: "untrusted_root" });
  });
});

describe("verifyAssertion", () => {
  let device: DeviceKey;
  let spki: Uint8Array;
  const challenge = "assert-challenge";
  const verify = async (assertion: string, counter = 0, appId = APP_ID) =>
    verifyAssertion(
      { assertion: fromBase64(assertion), clientDataHash: await clientDataHash(challenge), key: { spki, counter } },
      { appId },
    );

  beforeAll(async () => {
    device = await makeDeviceKey();
    spki = new Uint8Array((await crypto.subtle.exportKey("spki", device.keys.publicKey)) as ArrayBuffer);
  });

  it("accepts a signature from the stored key with a higher counter and returns that counter", async () => {
    expect(await verify(await makeAssertion(device, challenge, APP_ID, 5), 4)).toEqual({ ok: true, counter: 5 });
  });

  it("rejects a counter that did not increase", async () => {
    const assertion = await makeAssertion(device, challenge, APP_ID, 5);
    expect(await verify(assertion, 5)).toEqual({ ok: false, reason: "bad_counter" });
    expect(await verify(assertion, 9)).toEqual({ ok: false, reason: "bad_counter" });
  });

  it("rejects a signature from another key", async () => {
    const other = await makeDeviceKey();
    const assertion = await makeAssertion(device, challenge, APP_ID, 1, other.keys.privateKey);
    expect(await verify(assertion)).toEqual({ ok: false, reason: "invalid_signature" });
  });

  it("rejects an assertion over another challenge", async () => {
    expect(await verify(await makeAssertion(device, "other", APP_ID, 1))).toEqual({ ok: false, reason: "invalid_signature" });
  });

  it("rejects another app's assertion", async () => {
    const assertion = await makeAssertion(device, challenge, `${TEAM_ID}.com.example.other`, 1);
    expect(await verify(assertion)).toEqual({ ok: false, reason: "wrong_app" });
  });

  it.each([
    ["not CBOR", new Uint8Array([0xff])],
    ["no signature", encodeCbor(new Map([["authenticatorData", new Uint8Array(37)]]))],
    ["short authenticator data", encodeCbor(new Map([["signature", new Uint8Array([0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01])], ["authenticatorData", new Uint8Array(10)]]))],
  ])("rejects %s", async (_name, bytes) => {
    expect(await verify(toBase64(bytes))).toEqual({ ok: false, reason: "malformed" });
  });
});

describe("POST /v1/challenge and App Attest sessions", () => {
  let ca: AttestCA;

  beforeAll(async () => {
    ca = await makeAttestCA();
  });

  const harness = (env = {}, now = NOW) => makeHarness({ appAttestRootPEMs: [ca.rootPem], env, now });

  async function challengeFrom(app: ReturnType<typeof harness>["app"]): Promise<string> {
    const response = await post(app, "/v1/challenge", {});
    expect(response.status).toBe(200);
    return ((await response.json()) as { challenge: string }).challenge;
  }

  async function subjectOf(response: Response): Promise<string> {
    const { token } = (await response.json()) as { token: string };
    const verified = await verifySessionToken(token, SIGNING_KEY, NOW);
    if (!verified.ok) throw new Error(verified.reason);
    return verified.claims.sub;
  }

  const attestBody = (device: DeviceKey, challenge: string, attestationObject: string) => ({
    attestation: { kind: "appAttest", keyId: toBase64(device.keyId), attestationObject, challenge },
  });
  const assertBody = (device: DeviceKey, challenge: string, assertion: string) => ({
    attestation: { kind: "appAssert", keyId: toBase64(device.keyId), assertion, challenge },
  });

  it("attests once, then asserts, with one stable subject derived from the key", async () => {
    const { app, kv } = harness();
    const device = await makeDeviceKey();

    const first = await challengeFrom(app);
    const attested = await post(app, "/v1/session", attestBody(device, first, await makeAttestation(ca, device, first, APP_ID)));
    expect(attested.status).toBe(200);
    const subject = await subjectOf(attested);
    expect(subject).toBe(await subjectForKey(device.keyId));
    expect(JSON.parse((await kv.get(attestedKeyStorageKey(device.keyId))) ?? "null")).toMatchObject({ counter: 0 });

    const second = await challengeFrom(app);
    const asserted = await post(app, "/v1/session", assertBody(device, second, await makeAssertion(device, second, APP_ID, 1)));
    expect(asserted.status).toBe(200);
    expect(await subjectOf(asserted)).toBe(subject);
    expect(JSON.parse((await kv.get(attestedKeyStorageKey(device.keyId))) ?? "null")).toMatchObject({ counter: 1 });
  });

  it("gives different keys different subjects", async () => {
    const [a, b] = await Promise.all([makeDeviceKey(), makeDeviceKey()]);
    expect(await subjectForKey(a.keyId)).not.toBe(await subjectForKey(b.keyId));
  });

  it("refuses to attest a key that is already registered", async () => {
    const { app } = harness();
    const device = await makeDeviceKey();
    const first = await challengeFrom(app);
    await post(app, "/v1/session", attestBody(device, first, await makeAttestation(ca, device, first, APP_ID)));
    const again = await challengeFrom(app);
    const response = await post(app, "/v1/session", attestBody(device, again, await makeAttestation(ca, device, again, APP_ID)));
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ error: "key_already_attested" });
  });

  it("rejects a replayed assertion counter even with a fresh challenge", async () => {
    const { app } = harness();
    const device = await makeDeviceKey();
    const first = await challengeFrom(app);
    await post(app, "/v1/session", attestBody(device, first, await makeAttestation(ca, device, first, APP_ID)));
    const second = await challengeFrom(app);
    expect((await post(app, "/v1/session", assertBody(device, second, await makeAssertion(device, second, APP_ID, 3)))).status).toBe(200);
    const third = await challengeFrom(app);
    const replay = await post(app, "/v1/session", assertBody(device, third, await makeAssertion(device, third, APP_ID, 3)));
    expect(replay.status).toBe(401);
    expect(await replay.json()).toEqual({ error: "attestation_rejected" });
  });

  it("answers unknown_key for an assertion from an unregistered key, so the client re-attests", async () => {
    const { app } = harness();
    const device = await makeDeviceKey();
    const challenge = await challengeFrom(app);
    const response = await post(app, "/v1/session", assertBody(device, challenge, await makeAssertion(device, challenge, APP_ID, 1)));
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unknown_key" });
  });

  it("rejects an invalid attestation with a generic error and logs only the reason", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { app, kv } = harness();
    const device = await makeDeviceKey();
    const challenge = await challengeFrom(app);
    const attestation = await makeAttestation(ca, device, challenge, APP_ID, { counter: 2 });
    const response = await post(app, "/v1/session", attestBody(device, challenge, attestation));
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "attestation_rejected" });
    expect(await kv.get(attestedKeyStorageKey(device.keyId))).toBeNull();
    const logged = warn.mock.calls.map((call) => String(call[0])).join("\n");
    expect(logged).toContain('"reason":"bad_counter"');
    expect(logged).not.toContain(challenge);
    expect(logged).not.toContain(toBase64(device.keyId));
    warn.mockRestore();
  });

  it("rejects a challenge the proxy did not issue, and one that expired", async () => {
    const device = await makeDeviceKey();
    const forged = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.9999999999.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    const { app } = harness();
    const response = await post(app, "/v1/session", attestBody(device, forged, await makeAttestation(ca, device, forged, APP_ID)));
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "challenge_invalid" });

    const challenge = await challengeFrom(app);
    const later = harness({}, new Date(NOW.getTime() + (CHALLENGE_TTL_SECONDS + 1) * 1000));
    const expired = await post(later.app, "/v1/session", attestBody(device, challenge, await makeAttestation(ca, device, challenge, APP_ID)));
    expect(expired.status).toBe(401);
    expect(await expired.json()).toEqual({ error: "challenge_invalid" });
  });

  it("returns 400, not 500, for base64 the schema admits but atob rejects", async () => {
    const { app } = harness();
    const challenge = await challengeFrom(app);
    const response = await post(app, "/v1/session", {
      attestation: { kind: "appAssert", keyId: "A", assertion: "AA==", challenge },
    });
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid_request" });
  });

  it("fails closed with 500 when APPLE_TEAM_ID is not configured", async () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    const { app } = harness({ APPLE_TEAM_ID: undefined });
    const device = await makeDeviceKey();
    const challenge = await challengeFrom(app);
    const response = await post(app, "/v1/session", attestBody(device, challenge, await makeAttestation(ca, device, challenge, APP_ID)));
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({ error: "server_misconfigured" });
    expect(String(error.mock.calls[0]?.[0])).toContain("APPLE_TEAM_ID");
    error.mockRestore();
  });

  it("rejects a malformed team id as misconfiguration", async () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    const { app } = harness({ APPLE_TEAM_ID: "team" });
    expect((await post(app, "/v1/challenge", {})).status).toBe(500);
    error.mockRestore();
  });

  it("works with App Attest while dev attestation is disabled", async () => {
    const { app } = harness({ ALLOW_DEV_ATTESTATION: "false" });
    const device = await makeDeviceKey();
    const challenge = await challengeFrom(app);
    const response = await post(app, "/v1/session", attestBody(device, challenge, await makeAttestation(ca, device, challenge, APP_ID)));
    expect(response.status).toBe(200);
  });

  it.each([
    ["a non-base64 key id", { kind: "appAttest", keyId: "not base64!", attestationObject: "AA==", challenge: "c" }],
    ["an oversized assertion", { kind: "appAssert", keyId: "AA==", assertion: "A".repeat(5000), challenge: "c" }],
    ["a missing challenge", { kind: "appAssert", keyId: "AA==", assertion: "AA==" }],
  ])("returns 400 for %s", async (_name, attestation) => {
    const { app } = harness();
    const response = await post(app, "/v1/session", { attestation });
    expect(response.status).toBe(400);
  });

  it("issues challenges whose expiry decodes from the challenge itself", async () => {
    const { app } = harness();
    const response = await post(app, "/v1/challenge", {});
    const body = (await response.json()) as { challenge: string; expiresAt: string };
    const exp = Number(body.challenge.split(".")[1]);
    expect(new Date(exp * 1000).toISOString()).toBe(body.expiresAt);
    expect(fromBase64Url(body.challenge.split(".")[0] ?? "").length).toBe(32);
  });
});
