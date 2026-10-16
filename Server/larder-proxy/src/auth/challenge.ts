import { fromBase64Url, toBase64Url, utf8 } from "../encoding.js";

/** How long a challenge stays usable, in seconds. */
export const CHALLENGE_TTL_SECONDS = 5 * 60;

// Prefix keeps challenge MACs apart from session-token MACs made with the same key.
const DOMAIN = "larder-challenge.";

function importKey(signingKey: string, usage: "sign" | "verify"): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", utf8(signingKey), { name: "HMAC", hash: "SHA-256" }, false, [usage]);
}

/**
 * Issues a stateless App Attest challenge: `random.expiry.mac`, all base64url except the expiry in
 * Unix seconds. Nothing is stored, so the unauthenticated challenge endpoint costs no KV writes.
 * Replay inside the five minutes is stopped elsewhere: an attestation needs a key that is not yet
 * registered, and an assertion needs a counter above the stored one.
 */
export async function issueChallenge(signingKey: string, now: Date): Promise<{ challenge: string; expiresAt: string }> {
  const exp = Math.floor(now.getTime() / 1000) + CHALLENGE_TTL_SECONDS;
  const payload = `${toBase64Url(crypto.getRandomValues(new Uint8Array(32)))}.${exp}`;
  const mac = await crypto.subtle.sign("HMAC", await importKey(signingKey, "sign"), utf8(DOMAIN + payload));
  return { challenge: `${payload}.${toBase64Url(new Uint8Array(mac))}`, expiresAt: new Date(exp * 1000).toISOString() };
}

/** True when the challenge carries a valid MAC (checked in constant time by WebCrypto) and has not expired. */
export async function verifyChallenge(challenge: string, signingKey: string, now: Date): Promise<boolean> {
  const match = /^([A-Za-z0-9_-]{43})\.(\d{1,12})\.([A-Za-z0-9_-]{43})$/.exec(challenge);
  if (!match) return false;
  const [, random, exp, mac] = match as unknown as [string, string, string, string];
  const valid = await crypto.subtle.verify(
    "HMAC",
    await importKey(signingKey, "verify"),
    fromBase64Url(mac),
    utf8(`${DOMAIN}${random}.${exp}`),
  );
  return valid && Number(exp) * 1000 > now.getTime();
}

/** What the client signs over: SHA-256 of the challenge's UTF-8 bytes, as Apple's `clientDataHash`. */
export async function clientDataHash(challenge: string): Promise<Uint8Array<ArrayBuffer>> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", utf8(challenge)));
}
