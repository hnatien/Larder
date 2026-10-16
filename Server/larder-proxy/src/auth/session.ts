import { z } from "zod";
import { fromBase64Url, fromUtf8, toBase64Url, utf8 } from "../encoding.js";

/** Session lifetime in seconds. */
export const SESSION_TTL_SECONDS = 60 * 60;

const ClaimsSchema = z.object({
  sub: z.uuid(),
  exp: z.number().int(),
  tier: z.literal("anonymous"),
});

/** Claims inside a session token. `sub` is random, or derived from an App Attest key id; it links to nothing about the person. */
export type SessionClaims = z.infer<typeof ClaimsSchema>;

/** Why a token was rejected. */
export type SessionFailure = "missing" | "malformed" | "bad_signature" | "expired";

function importKey(signingKey: string, usage: "sign" | "verify"): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", utf8(signingKey), { name: "HMAC", hash: "SHA-256" }, false, [usage]);
}

/** Issues a compact `payload.signature` token, both parts base64url, signed with HMAC-SHA256. */
export async function issueSessionToken(
  signingKey: string,
  now: Date,
  subject: string = crypto.randomUUID(),
): Promise<{ token: string; claims: SessionClaims }> {
  const claims: SessionClaims = {
    sub: subject,
    exp: Math.floor(now.getTime() / 1000) + SESSION_TTL_SECONDS,
    tier: "anonymous",
  };
  const payload = toBase64Url(utf8(JSON.stringify(claims)));
  const signature = await crypto.subtle.sign("HMAC", await importKey(signingKey, "sign"), utf8(payload));
  return { token: `${payload}.${toBase64Url(new Uint8Array(signature))}`, claims };
}

/** Verifies signature (constant time via WebCrypto) and expiry. */
export async function verifySessionToken(
  token: string,
  signingKey: string,
  now: Date,
): Promise<{ ok: true; claims: SessionClaims } | { ok: false; reason: SessionFailure }> {
  const parts = token.split(".");
  if (parts.length !== 2) return { ok: false, reason: "malformed" };
  const [payload, signaturePart] = parts as [string, string];
  let signature: Uint8Array<ArrayBuffer>;
  try {
    signature = fromBase64Url(signaturePart);
  } catch {
    return { ok: false, reason: "malformed" };
  }
  const valid = await crypto.subtle.verify("HMAC", await importKey(signingKey, "verify"), signature, utf8(payload));
  if (!valid) return { ok: false, reason: "bad_signature" };
  let claims: SessionClaims;
  try {
    const parsed = ClaimsSchema.safeParse(JSON.parse(fromUtf8(fromBase64Url(payload))));
    if (!parsed.success) return { ok: false, reason: "malformed" };
    claims = parsed.data;
  } catch {
    return { ok: false, reason: "malformed" };
  }
  if (claims.exp * 1000 <= now.getTime()) return { ok: false, reason: "expired" };
  return { ok: true, claims };
}

/** Reads `Authorization: Bearer <token>` and verifies it. */
export async function requireSession(
  request: Request,
  signingKey: string,
  now: Date,
): Promise<{ ok: true; claims: SessionClaims } | { ok: false; reason: SessionFailure }> {
  const match = /^Bearer (\S+)$/.exec(request.headers.get("authorization") ?? "");
  if (!match?.[1]) return { ok: false, reason: "missing" };
  return verifySessionToken(match[1], signingKey, now);
}
