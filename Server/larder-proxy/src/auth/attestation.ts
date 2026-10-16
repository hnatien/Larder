import { z } from "zod";
import { bytesEqual, fromBase64, toBase64, toBase64Url, utf8 } from "../encoding.js";
import type { KVNamespaceLike } from "../env.js";
import { errorReply, type ErrorReply } from "../http.js";
import { verifyAssertion, verifyAttestation, type AppAttestEnvironment, type AppAttestFailure } from "./appAttest.js";
import { clientDataHash, verifyChallenge } from "./challenge.js";

const Base64 = z.string().regex(/^[A-Za-z0-9+/]+={0,2}$/);
const Challenge = z.string().min(1).max(256);

/** Body of `POST /v1/session`. */
export const AttestationSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("dev"), clientSecret: z.string().min(1).max(512) }),
  // First contact: a fresh Secure Enclave key, attested by Apple. Standard base64, as DCAppAttestService returns.
  z.object({
    kind: z.literal("appAttest"),
    keyId: Base64.max(64),
    attestationObject: Base64.max(65_536),
    challenge: Challenge,
  }),
  // Every later session: an assertion signed by the already attested key.
  z.object({
    kind: z.literal("appAssert"),
    keyId: Base64.max(64),
    assertion: Base64.max(4096),
    challenge: Challenge,
  }),
]);

export const SessionRequestSchema = z.object({ attestation: AttestationSchema });

export type Attestation = z.infer<typeof AttestationSchema>;

/**
 * Outcome of attestation. An accepted attestation may name the session subject (App Attest derives it
 * from the key so quotas follow the device key); a rejection carries the reply and a loggable reason.
 */
export type AttestationResult =
  | { accepted: true; subject?: string }
  | { accepted: false; reply: ErrorReply; reason?: AppAttestFailure };

/** Proves a request comes from a genuine Larder client. */
export interface Attestor {
  verify(attestation: Attestation): Promise<AttestationResult>;
}

const reject = (reply: ErrorReply, reason?: AppAttestFailure): AttestationResult => ({ accepted: false, reply, reason });

/** Shared-secret attestation for local development and CI; disabled unless explicitly allowed. */
export class DevAttestor implements Attestor {
  constructor(private readonly options: { enabled: boolean; clientSecret: string | undefined }) {}

  async verify(attestation: Attestation): Promise<AttestationResult> {
    if (attestation.kind !== "dev") return reject(errorReply(400, "wrong_attestation_kind"));
    if (!this.options.enabled) return reject(errorReply(403, "dev_attestation_disabled"));
    if (!this.options.clientSecret) return reject(errorReply(500, "server_misconfigured"));
    const matches = await constantTimeEqual(attestation.clientSecret, this.options.clientSecret);
    return matches ? { accepted: true } : reject(errorReply(401, "attestation_rejected"));
  }
}

const StoredKeySchema = z.object({ spki: Base64, counter: z.number().int().nonnegative() });

/** KV key for an attested key's record; the key id is public, so it is stored as is. */
export function attestedKeyStorageKey(keyId: Uint8Array): string {
  return `appattest:key:${toBase64Url(keyId)}`;
}

/**
 * App Attest: `appAttest` registers a new key after full attestation verification, `appAssert` proves
 * possession of a registered key. Both must sign over a live challenge from `POST /v1/challenge`.
 * KV holds `{ spki, counter }` per key; KV is eventually consistent, so two assertions racing through
 * different locations within about a minute could both pass the counter check. Each still needs its
 * own fresh challenge and the device's private key.
 */
export class AppAttestAttestor implements Attestor {
  constructor(
    private readonly options: {
      kv: KVNamespaceLike;
      signingKey: string;
      teamId: string | undefined;
      bundleId: string;
      environment: AppAttestEnvironment;
      rootPEMs: readonly string[];
      now: Date;
    },
  ) {}

  async verify(attestation: Attestation): Promise<AttestationResult> {
    if (attestation.kind === "dev") return reject(errorReply(400, "wrong_attestation_kind"));
    const { kv, signingKey, teamId, bundleId, environment, rootPEMs, now } = this.options;
    if (!teamId) {
      console.error(JSON.stringify({ event: "config_invalid", variables: ["APPLE_TEAM_ID"] }));
      return reject(errorReply(500, "server_misconfigured"));
    }
    if (!(await verifyChallenge(attestation.challenge, signingKey, now))) {
      return reject(errorReply(401, "challenge_invalid"));
    }
    const keyId = decodeBase64(attestation.keyId);
    const evidence = decodeBase64(attestation.kind === "appAttest" ? attestation.attestationObject : attestation.assertion);
    if (!keyId || !evidence) return reject(errorReply(400, "invalid_request"));
    const hash = await clientDataHash(attestation.challenge);
    const appId = `${teamId}.${bundleId}`;
    const storageKey = attestedKeyStorageKey(keyId);
    const stored = await kv.get(storageKey);

    if (attestation.kind === "appAttest") {
      if (stored !== null) return reject(errorReply(409, "key_already_attested"));
      const result = await verifyAttestation(
        { keyId, attestationObject: evidence, clientDataHash: hash },
        { appId, environment, rootPEMs, now },
      );
      if (!result.ok) return reject(errorReply(401, "attestation_rejected"), result.reason);
      await kv.put(storageKey, JSON.stringify({ spki: toBase64(result.key.spki), counter: 0 }));
      return { accepted: true, subject: await subjectForKey(keyId) };
    }

    const record = stored === null ? null : parseStoredKey(stored);
    if (!record) return reject(errorReply(401, "unknown_key"));
    const result = await verifyAssertion(
      { assertion: evidence, clientDataHash: hash, key: record },
      { appId },
    );
    if (!result.ok) return reject(errorReply(401, "attestation_rejected"), result.reason);
    await kv.put(storageKey, JSON.stringify({ spki: toBase64(record.spki), counter: result.counter }));
    return { accepted: true, subject: await subjectForKey(keyId) };
  }
}

// The schema regex admits strings like "A" that are not whole base64 quanta; atob rejects those.
function decodeBase64(text: string): Uint8Array | null {
  try {
    return fromBase64(text);
  } catch {
    return null;
  }
}

function parseStoredKey(text: string): { spki: Uint8Array; counter: number } | null {
  try {
    const parsed = StoredKeySchema.safeParse(JSON.parse(text));
    return parsed.success ? { spki: fromBase64(parsed.data.spki), counter: parsed.data.counter } : null;
  } catch {
    return null;
  }
}

/**
 * A stable, UUID-shaped session subject for an attested key (version 8, RFC 9562), so a device keeps
 * one daily quota across sessions. It is a hash of a random Secure Enclave key id and links to
 * nothing about the person.
 */
export async function subjectForKey(keyId: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", utf8(`larder-subject.${toBase64Url(keyId)}`)));
  const bytes = digest.subarray(0, 16);
  bytes[6] = ((bytes[6] ?? 0) & 0x0f) | 0x80;
  bytes[8] = ((bytes[8] ?? 0) & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

// Hashing first gives equal-length inputs, so the comparison time does not depend on the secret's length or content.
async function constantTimeEqual(a: string, b: string): Promise<boolean> {
  const [hashA, hashB] = await Promise.all([
    crypto.subtle.digest("SHA-256", utf8(a)),
    crypto.subtle.digest("SHA-256", utf8(b)),
  ]);
  return bytesEqual(new Uint8Array(hashA), new Uint8Array(hashB));
}
