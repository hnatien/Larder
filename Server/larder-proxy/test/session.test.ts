import { describe, expect, it } from "vitest";
import { issueSessionToken, requireSession, SESSION_TTL_SECONDS, verifySessionToken } from "../src/auth/session.js";
import { fromBase64Url, toBase64Url } from "../src/encoding.js";
import { DEV_SECRET, makeHarness, NOW, post, SIGNING_KEY } from "./helpers/fixtures.js";

describe("session tokens", () => {
  it("verifies a freshly issued token and carries an anonymous random subject", async () => {
    const { token, claims } = await issueSessionToken(SIGNING_KEY, NOW);
    const result = await verifySessionToken(token, SIGNING_KEY, NOW);
    expect(result).toEqual({ ok: true, claims });
    expect(claims.tier).toBe("anonymous");
    expect(claims.exp).toBe(Math.floor(NOW.getTime() / 1000) + SESSION_TTL_SECONDS);
  });

  it("issues a different subject for every session", async () => {
    const first = await issueSessionToken(SIGNING_KEY, NOW);
    const second = await issueSessionToken(SIGNING_KEY, NOW);
    expect(first.claims.sub).not.toBe(second.claims.sub);
  });

  it("rejects an expired token at and after its expiry", async () => {
    const { token } = await issueSessionToken(SIGNING_KEY, NOW);
    const atExpiry = new Date(NOW.getTime() + SESSION_TTL_SECONDS * 1000);
    expect(await verifySessionToken(token, SIGNING_KEY, atExpiry)).toEqual({ ok: false, reason: "expired" });
    const justBefore = new Date(atExpiry.getTime() - 1000);
    expect((await verifySessionToken(token, SIGNING_KEY, justBefore)).ok).toBe(true);
  });

  it("rejects a token whose payload was edited", async () => {
    const { token } = await issueSessionToken(SIGNING_KEY, NOW);
    const [payload, signature] = token.split(".") as [string, string];
    const claims = JSON.parse(new TextDecoder().decode(fromBase64Url(payload)));
    claims.exp += 86_400;
    const forged = `${toBase64Url(new TextEncoder().encode(JSON.stringify(claims)))}.${signature}`;
    expect(await verifySessionToken(forged, SIGNING_KEY, NOW)).toEqual({ ok: false, reason: "bad_signature" });
  });

  it("rejects a token whose signature was edited", async () => {
    const { token } = await issueSessionToken(SIGNING_KEY, NOW);
    const [payload, signature] = token.split(".") as [string, string];
    const bytes = fromBase64Url(signature);
    bytes[0] = (bytes[0] ?? 0) ^ 0xff;
    const result = await verifySessionToken(`${payload}.${toBase64Url(bytes)}`, SIGNING_KEY, NOW);
    expect(result).toEqual({ ok: false, reason: "bad_signature" });
  });

  it("rejects a token signed with a different key", async () => {
    const { token } = await issueSessionToken(`${SIGNING_KEY}-other`, NOW);
    expect(await verifySessionToken(token, SIGNING_KEY, NOW)).toEqual({ ok: false, reason: "bad_signature" });
  });

  it.each(["", "abc", "a.b.c", "a.!!!"])("rejects malformed token %j", async (token) => {
    const result = await verifySessionToken(token, SIGNING_KEY, NOW);
    expect(result.ok).toBe(false);
  });

  it("requires a Bearer authorization header", async () => {
    const request = new Request("https://proxy.test/", { headers: { authorization: "Token abc" } });
    expect(await requireSession(request, SIGNING_KEY, NOW)).toEqual({ ok: false, reason: "missing" });
  });
});

describe("POST /v1/session", () => {
  it("issues a token for a valid dev attestation that later authenticates", async () => {
    const { app } = makeHarness();
    const response = await post(app, "/v1/session", { attestation: { kind: "dev", clientSecret: DEV_SECRET } });
    expect(response.status).toBe(200);
    const body = (await response.json()) as { token: string; expiresAt: string };
    expect(body.expiresAt).toBe(new Date(NOW.getTime() + SESSION_TTL_SECONDS * 1000).toISOString());
    expect((await verifySessionToken(body.token, SIGNING_KEY, NOW)).ok).toBe(true);
  });

  it("rejects a wrong dev secret with 401", async () => {
    const { app } = makeHarness();
    const response = await post(app, "/v1/session", { attestation: { kind: "dev", clientSecret: "nope" } });
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "attestation_rejected" });
  });

  it("refuses dev attestation unless ALLOW_DEV_ATTESTATION is true", async () => {
    const { app } = makeHarness({ env: { ALLOW_DEV_ATTESTATION: "false" } });
    const response = await post(app, "/v1/session", { attestation: { kind: "dev", clientSecret: DEV_SECRET } });
    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({ error: "dev_attestation_disabled" });
  });

  it("fails closed when dev attestation is allowed but no secret is configured", async () => {
    const { app } = makeHarness({ env: { DEV_CLIENT_SECRET: undefined } });
    const response = await post(app, "/v1/session", { attestation: { kind: "dev", clientSecret: DEV_SECRET } });
    expect(response.status).toBe(500);
  });

  it("reports App Attest as not implemented with 501", async () => {
    const { app } = makeHarness();
    const response = await post(app, "/v1/session", {
      attestation: { kind: "appAttest", keyId: "k", attestationObject: "o", challenge: "c" },
    });
    expect(response.status).toBe(501);
    const body = (await response.json()) as { error: string; message: string };
    expect(body.error).toBe("app_attest_not_implemented");
    expect(body.message).toMatch(/not implemented/);
  });

  it("returns 400 with issues for an unknown attestation kind", async () => {
    const { app } = makeHarness();
    const response = await post(app, "/v1/session", { attestation: { kind: "magic" } });
    expect(response.status).toBe(400);
    const body = (await response.json()) as { error: string; issues: unknown[] };
    expect(body.error).toBe("invalid_request");
    expect(body.issues.length).toBeGreaterThan(0);
  });

  it("returns 400 for a body that is not JSON", async () => {
    const { app } = makeHarness();
    const response = await post(app, "/v1/session", "{not json");
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid_json" });
  });

  it("returns 500 without echoing values when the signing key is too short", async () => {
    const { app } = makeHarness({ env: { SESSION_SIGNING_KEY: "short" } });
    const response = await post(app, "/v1/session", { attestation: { kind: "dev", clientSecret: DEV_SECRET } });
    expect(response.status).toBe(500);
    const text = await response.text();
    expect(text).toBe(JSON.stringify({ error: "server_misconfigured" }));
  });
});
